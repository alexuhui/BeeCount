import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

import '../../data/db.dart';
import '../system/logger_service.dart';

class BeeCountSyncEngine {
  BeeCountSyncEngine({
    required this.db,
    required this.provider,
    this.onFlushComplete,
    this.onConnectionLost,
    this.onConnectionRestored,
  });

  final BeeDatabase db;
  final CloudProvider provider;

  /// flush 完成后的回调（用于更新版本号）
  final Future<void> Function()? onFlushComplete;
  final void Function(Object error)? onConnectionLost;
  final void Function()? onConnectionRestored;

  Timer? _debounce;
  Timer? _poll;
  bool _flushing = false;

  void start() {
    _ensureLocalTables();
    _poll ??= Timer.periodic(const Duration(seconds: 20), (_) {
      flush();
    });
  }

  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
  }

  Future<void> enqueueUpsert(String entity, int localId,
      {int? createdAt}) async {
    await _ensureLocalTables();
    final createdAtValue =
        createdAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await db.customStatement(
      '''
      INSERT INTO sync_queue_items(entity, local_id, action, payload, retry_count, last_error, created_at, updated_at)
      VALUES(?, ?, 'upsert', NULL, 0, NULL, ?, strftime('%s','now'))
      ON CONFLICT(entity, local_id) DO UPDATE SET
        action='upsert',
        payload=NULL,
        created_at=MIN(created_at, ?),
        updated_at=strftime('%s','now');
      ''',
      [entity, localId, createdAtValue, createdAtValue],
    );
    await _touchLocalChange(entity, localId);
    _scheduleFlush();
  }

  Future<void> enqueueDelete(String entity, int localId) async {
    await _ensureLocalTables();
    await db.customStatement(
      '''
      INSERT INTO sync_queue_items(entity, local_id, action, payload, retry_count, last_error, created_at, updated_at)
      VALUES(?, ?, 'delete', NULL, 0, NULL, strftime('%s','now'), strftime('%s','now'))
      ON CONFLICT(entity, local_id) DO UPDATE SET
        action='delete',
        payload=NULL,
        updated_at=strftime('%s','now');
      ''',
      [entity, localId],
    );
    await _touchLocalChange(entity, localId);
    _scheduleFlush();
  }

  Future<int> pendingCount() async {
    await _ensureLocalTables();
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM sync_queue_items',
        )
        .getSingle();
    return (row.data['c'] as int?) ?? 0;
  }

  Future<void> _ensureLocalTables() async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_queue_items (
        entity TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        payload TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        PRIMARY KEY (entity, local_id)
      );
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_id_maps (
        entity TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        remote_id INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        PRIMARY KEY (entity, local_id)
      );
    ''');
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_id_maps_remote ON sync_id_maps(entity, remote_id);',
    );
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_change_log (
        entity TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        PRIMARY KEY (entity, local_id)
      );
    ''');
  }

  Future<void> _touchLocalChange(String entity, int localId) async {
    await db.customStatement(
      '''
      INSERT INTO local_change_log(entity, local_id, updated_at)
      VALUES(?, ?, strftime('%s','now'))
      ON CONFLICT(entity, local_id) DO UPDATE SET
        updated_at=strftime('%s','now');
      ''',
      [entity, localId],
    );
  }

  void _scheduleFlush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      flush();
    });
  }

  Future<void> flush({bool notifyConnectionLoss = true}) async {
    await _ensureLocalTables();
    if (_flushing) return;
    if (provider.databaseService == null) return;
    if (provider.currentUserId == null) return;

    _flushing = true;
    try {
      var madeProgress = true;
      var rounds = 0;
      while (madeProgress && rounds < 5) {
        rounds++;
        madeProgress =
            await _flushOnce(notifyConnectionLoss: notifyConnectionLoss);
      }

      // flush 完成后调用回调
      if (onFlushComplete != null) {
        await onFlushComplete!();
      }
    } finally {
      _flushing = false;
    }
  }

  static const List<String> _priority = [
    'ledgers',
    'accounts',
    'categories',
    'tags',
    'budgets',
    'recurring_transactions',
    'transactions',
    'transaction_tags',
    'receivables',
    'payables',
    'receivable_payments',
    'payable_payments',
  ];

  Future<bool> _flushOnce({required bool notifyConnectionLoss}) async {
    final rows = await db.customSelect(
      '''
      SELECT entity, local_id, action, payload, retry_count, last_error, created_at, updated_at
      FROM sync_queue_items
      ORDER BY created_at ASC
      ''',
    ).get();

    final items = rows
        .map(
          (r) => _QueueItem(
            entity: r.data['entity'] as String,
            localId: (r.data['local_id'] as num).toInt(),
            action: r.data['action'] as String,
            payload: r.data['payload'] as String?,
            retryCount: (r.data['retry_count'] as num?)?.toInt() ?? 0,
            lastError: r.data['last_error'] as String?,
            createdAtSec: (r.data['created_at'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    if (items.isEmpty) return false;

    items.sort((a, b) {
      final pa = _priority.indexOf(a.entity);
      final pb = _priority.indexOf(b.entity);
      final ca = pa == -1 ? 999 : pa;
      final cb = pb == -1 ? 999 : pb;
      if (ca != cb) return ca.compareTo(cb);
      final t = a.createdAtSec.compareTo(b.createdAtSec);
      if (t != 0) return t;
      return a.localId.compareTo(b.localId);
    });

    var progressed = false;

    for (final item in items) {
      try {
        if (item.action == 'delete') {
          final ok = await _applyDelete(item.entity, item.localId);
          if (ok) progressed = true;
          continue;
        }

        if (item.action == 'upsert') {
          final ok = await _applyUpsert(item.entity, item.localId);
          if (ok) progressed = true;
          continue;
        }

        await _markError(
            entity: item.entity,
            localId: item.localId,
            message: 'Unknown action: ${item.action}');
        break;
      } on _MissingDependencyException {
        continue;
      } catch (e) {
        if (notifyConnectionLoss && _isConnectionFailure(e)) {
          onConnectionLost?.call(e);
        }
        await _markError(
            entity: item.entity, localId: item.localId, message: e.toString());
        break;
      }
    }

    return progressed;
  }

  Future<void> _markError({
    required String entity,
    required int localId,
    required String message,
  }) async {
    final row = await db.customSelect(
      'SELECT retry_count FROM sync_queue_items WHERE entity=? AND local_id=? LIMIT 1',
      variables: [Variable.withString(entity), Variable.withInt(localId)],
    ).getSingleOrNull();
    final current = (row?.data['retry_count'] as num?)?.toInt() ?? 0;
    final nextRetry = current + 1;

    await db.customStatement(
      '''
      UPDATE sync_queue_items
      SET retry_count=?, last_error=?, updated_at=strftime('%s','now')
      WHERE entity=? AND local_id=?;
      ''',
      [nextRetry, message, entity, localId],
    );
  }

  Future<void> _removeQueueItem(String entity, int localId) async {
    await db.customStatement(
      'DELETE FROM sync_queue_items WHERE entity=? AND local_id=?',
      [entity, localId],
    );
  }

  Future<int?> _remoteIdOf(String entity, int localId) async {
    final row = await db.customSelect(
      'SELECT remote_id FROM sync_id_maps WHERE entity=? AND local_id=? LIMIT 1',
      variables: [Variable.withString(entity), Variable.withInt(localId)],
    ).getSingleOrNull();
    return (row?.data['remote_id'] as num?)?.toInt();
  }

  Future<void> _saveIdMap(String entity, int localId, int remoteId) async {
    await db.customStatement(
      '''
      INSERT INTO sync_id_maps(entity, local_id, remote_id, updated_at)
      VALUES(?, ?, ?, strftime('%s','now'))
      ON CONFLICT(entity, local_id) DO UPDATE SET
        remote_id=excluded.remote_id,
        updated_at=strftime('%s','now');
      ''',
      [entity, localId, remoteId],
    );
  }

  Future<void> _removeIdMap(String entity, int localId) async {
    await db.customStatement(
      'DELETE FROM sync_id_maps WHERE entity=? AND local_id=?',
      [entity, localId],
    );
  }

  Future<bool> _applyDelete(String entity, int localId) async {
    final remoteId = await _remoteIdOf(entity, localId);
    if (remoteId == null) {
      await _removeQueueItem(entity, localId);
      return true;
    }

    try {
      await provider.databaseService!
          .delete(table: entity, id: remoteId.toString());
    } on CloudDatabaseException catch (e) {
      if (e.statusCode == 404) {
        await _removeIdMap(entity, localId);
        await _removeQueueItem(entity, localId);
        onConnectionRestored?.call();
        return true;
      }
      rethrow;
    }
    await _removeIdMap(entity, localId);
    await _removeQueueItem(entity, localId);
    onConnectionRestored?.call();
    return true;
  }

  Future<bool> _applyUpsert(String entity, int localId) async {
    final payload = await _buildPayload(entity, localId);
    if (payload == null) {
      await _removeQueueItem(entity, localId);
      return true;
    }

    final remoteId = await _remoteIdOf(entity, localId);
    if (remoteId == null) {
      final result =
          await provider.databaseService!.insert(table: entity, data: payload);
      await _saveRemoteIdFromInsertResponse(entity, localId, result);
      await _removeQueueItem(entity, localId);
      onConnectionRestored?.call();
      return true;
    }

    try {
      await provider.databaseService!
          .update(table: entity, id: remoteId.toString(), data: payload);
    } on CloudDatabaseException catch (e) {
      if (e.statusCode == 404) {
        await _removeIdMap(entity, localId);
        final result = await provider.databaseService!
            .insert(table: entity, data: payload);
        await _saveRemoteIdFromInsertResponse(entity, localId, result);
        await _removeQueueItem(entity, localId);
        onConnectionRestored?.call();
        return true;
      }
      rethrow;
    }
    await _removeQueueItem(entity, localId);
    onConnectionRestored?.call();
    return true;
  }

  bool _isConnectionFailure(Object error) {
    if (error is CloudDatabaseException) {
      final statusCode = error.statusCode;
      return statusCode == null || statusCode == 0 || statusCode >= 500;
    }
    return true;
  }

  Future<void> _saveRemoteIdFromInsertResponse(
    String entity,
    int localId,
    Map<String, dynamic> result,
  ) async {
    final newRemoteId = result['id'];
    if (newRemoteId is int) {
      await _saveIdMap(entity, localId, newRemoteId);
    } else if (newRemoteId is String) {
      await _saveIdMap(entity, localId, int.parse(newRemoteId));
    } else {
      throw Exception('Insert returned invalid id: $newRemoteId');
    }
  }

  Future<int> _requireRemoteId(String entity, int localId) async {
    final id = await _remoteIdOf(entity, localId);
    if (id == null) {
      // 使用当前时间戳的负数（毫秒），确保依赖项排在前面
      // 后加入的依赖项会有更小的值，会排在更前面（处理多层依赖时，父分类会排在子分类之前）
      final createdAt = -DateTime.now().millisecondsSinceEpoch;
      await enqueueUpsert(entity, localId, createdAt: createdAt);
      throw _MissingDependencyException(entity, localId);
    }
    return id;
  }

  Future<Map<String, dynamic>?> _buildPayload(
      String entity, int localId) async {
    switch (entity) {
      case 'ledgers':
        final row = await (db.select(db.ledgers)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'name': row.name,
          'currency': row.currency,
          'type': row.type,
          'user_id': provider.currentUserId,
        };

      case 'accounts':
        final row = await (db.select(db.accounts)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remoteLedgerId = await _requireRemoteId('ledgers', row.ledgerId);
        return {
          'ledger_id': remoteLedgerId,
          'name': row.name,
          'type': row.type,
          'currency': row.currency,
          'initial_balance': row.initialBalance,
          if (row.createdAt != null)
            'created_at': row.createdAt!.toIso8601String(),
          if (row.updatedAt != null)
            'updated_at': row.updatedAt!.toIso8601String(),
          'user_id': provider.currentUserId,
        };

      case 'categories':
        final row = await (db.select(db.categories)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        int? parentRemoteId;
        if (row.parentId != null) {
          parentRemoteId = await _requireRemoteId('categories', row.parentId!);
        }
        return {
          'name': row.name,
          'kind': row.kind,
          'icon': row.icon,
          'sort_order': row.sortOrder,
          'parent_id': parentRemoteId,
          'level': row.level,
          'icon_type': row.iconType,
          'custom_icon_path': row.customIconPath,
          'community_icon_id': row.communityIconId,
          'user_id': provider.currentUserId,
        };

      case 'transactions':
        final row = await (db.select(db.transactions)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remoteLedgerId = await _requireRemoteId('ledgers', row.ledgerId);
        final remoteCategoryId = row.categoryId == null
            ? null
            : await _requireRemoteId('categories', row.categoryId!);
        final remoteAccountId = row.accountId == null
            ? null
            : await _requireRemoteId('accounts', row.accountId!);
        final remoteToAccountId = row.toAccountId == null
            ? null
            : await _requireRemoteId('accounts', row.toAccountId!);
        final remoteRecurringId = row.recurringId == null
            ? null
            : await _requireRemoteId(
                'recurring_transactions', row.recurringId!);
        return {
          'ledger_id': remoteLedgerId,
          'type': row.type,
          'amount': row.amount,
          'category_id': remoteCategoryId,
          'account_id': remoteAccountId,
          'to_account_id': remoteToAccountId,
          'happened_at': row.happenedAt.toIso8601String(),
          'note': row.note,
          'recurring_id': remoteRecurringId,
          'user_id': provider.currentUserId,
          'created_by': provider.currentUserId,
        };

      case 'recurring_transactions':
        final row = await (db.select(db.recurringTransactions)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remoteLedgerId = await _requireRemoteId('ledgers', row.ledgerId);
        final remoteCategoryId = row.categoryId == null
            ? null
            : await _requireRemoteId('categories', row.categoryId!);
        final remoteAccountId = row.accountId == null
            ? null
            : await _requireRemoteId('accounts', row.accountId!);
        final remoteToAccountId = row.toAccountId == null
            ? null
            : await _requireRemoteId('accounts', row.toAccountId!);
        return {
          'ledger_id': remoteLedgerId,
          'type': row.type,
          'amount': row.amount,
          'category_id': remoteCategoryId,
          'account_id': remoteAccountId,
          'to_account_id': remoteToAccountId,
          'note': row.note,
          'frequency': row.frequency,
          'interval': row.interval,
          'day_of_month': row.dayOfMonth,
          'day_of_week': row.dayOfWeek,
          'month_of_year': row.monthOfYear,
          'start_date': row.startDate.toIso8601String(),
          'end_date': row.endDate?.toIso8601String(),
          'last_generated_date': row.lastGeneratedDate?.toIso8601String(),
          'enabled': row.enabled,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
          'user_id': provider.currentUserId,
        };

      case 'tags':
        final row = await (db.select(db.tags)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        return {
          'name': row.name,
          'color': row.color,
          'sort_order': row.sortOrder,
          'created_at': row.createdAt.toIso8601String(),
          'user_id': provider.currentUserId,
        };

      case 'transaction_tags':
        final row = await (db.select(db.transactionTags)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remoteTxId =
            await _requireRemoteId('transactions', row.transactionId);
        final remoteTagId = await _requireRemoteId('tags', row.tagId);
        return {
          'transaction_id': remoteTxId,
          'tag_id': remoteTagId,
          'user_id': provider.currentUserId,
        };

      case 'budgets':
        final row = await (db.select(db.budgets)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remoteLedgerId = await _requireRemoteId('ledgers', row.ledgerId);
        final remoteCategoryId = row.categoryId == null
            ? null
            : await _requireRemoteId('categories', row.categoryId!);
        return {
          'ledger_id': remoteLedgerId,
          'year': row.year,
          'month': row.month,
          'category_id': remoteCategoryId,
          'amount': row.amount,
          'enabled': row.enabled,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
          'prompt': row.prompt,
          'prompt_day': row.promptDay,
          'ignored': row.ignored,
          'user_id': provider.currentUserId,
        };

      case 'receivables':
        final row = await (db.select(db.receivables)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remoteAccountId =
            await _requireRemoteId('accounts', row.accountId);
        final remoteFromAccountId = row.fromAccountId == null
            ? null
            : await _requireRemoteId('accounts', row.fromAccountId!);
        final remoteToAccountId = row.toAccountId == null
            ? null
            : await _requireRemoteId('accounts', row.toAccountId!);
        return {
          'account_id': remoteAccountId,
          'borrower_name': row.borrowerName,
          'amount': row.amount,
          'borrow_date': row.borrowDate.toIso8601String(),
          'note': row.note,
          'from_account_id': remoteFromAccountId,
          'is_received': row.isReceived,
          'receive_date': row.receiveDate?.toIso8601String(),
          'to_account_id': remoteToAccountId,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
          'user_id': provider.currentUserId,
        };

      case 'payables':
        final row = await (db.select(db.payables)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remoteAccountId =
            await _requireRemoteId('accounts', row.accountId);
        final remoteToAccountId = row.toAccountId == null
            ? null
            : await _requireRemoteId('accounts', row.toAccountId!);
        final remoteFromAccountId = row.fromAccountId == null
            ? null
            : await _requireRemoteId('accounts', row.fromAccountId!);
        return {
          'account_id': remoteAccountId,
          'payee_name': row.payeeName,
          'amount': row.amount,
          'pay_date': row.payDate.toIso8601String(),
          'note': row.note,
          'to_account_id': remoteToAccountId,
          'is_paid': row.isPaid,
          'paid_date': row.paidDate?.toIso8601String(),
          'from_account_id': remoteFromAccountId,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
          'user_id': provider.currentUserId,
        };

      case 'receivable_payments':
        final row = await (db.select(db.receivablePayments)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remoteReceivableId =
            await _requireRemoteId('receivables', row.receivableId);
        final remoteAccountId = row.accountId == null
            ? null
            : await _requireRemoteId('accounts', row.accountId!);
        return {
          'receivable_id': remoteReceivableId,
          'amount': row.amount,
          'interest_amount': row.interestAmount,
          'happened_at': row.happenedAt.toIso8601String(),
          if (remoteAccountId != null) 'account_id': remoteAccountId,
          'note': row.note,
          'user_id': provider.currentUserId,
        };

      case 'payable_payments':
        final row = await (db.select(db.payablePayments)
              ..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
        if (row == null) return null;
        final remotePayableId =
            await _requireRemoteId('payables', row.payableId);
        final remoteAccountId = row.accountId == null
            ? null
            : await _requireRemoteId('accounts', row.accountId!);
        return {
          'payable_id': remotePayableId,
          'amount': row.amount,
          'interest_amount': row.interestAmount,
          'happened_at': row.happenedAt.toIso8601String(),
          if (remoteAccountId != null) 'account_id': remoteAccountId,
          'note': row.note,
          'user_id': provider.currentUserId,
        };
    }

    final payload = await _readPayload(entity, localId);
    if (payload != null) {
      return (jsonDecode(payload) as Map).cast<String, dynamic>();
    }

    logger.warning('BeeCountSync',
        'No payload builder for entity=$entity localId=$localId');
    return null;
  }

  Future<String?> _readPayload(String entity, int localId) async {
    final row = await db.customSelect(
      'SELECT payload FROM sync_queue_items WHERE entity=? AND local_id=? LIMIT 1',
      variables: [Variable.withString(entity), Variable.withInt(localId)],
    ).getSingleOrNull();
    return row?.data['payload'] as String?;
  }
}

class _QueueItem {
  final String entity;
  final int localId;
  final String action;
  final String? payload;
  final int retryCount;
  final String? lastError;
  final int createdAtSec;

  const _QueueItem({
    required this.entity,
    required this.localId,
    required this.action,
    required this.payload,
    required this.retryCount,
    required this.lastError,
    required this.createdAtSec,
  });
}

class _MissingDependencyException implements Exception {
  final String entity;
  final int localId;
  const _MissingDependencyException(this.entity, this.localId);
}
