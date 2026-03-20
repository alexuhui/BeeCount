import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

import '../../data/db.dart';
import '../system/logger_service.dart';
import 'beecount_sync_engine.dart';

class BeeCountInitialSyncService {
  BeeCountInitialSyncService({
    required this.db,
    required this.provider,
    required this.sync,
  });

  final BeeDatabase db;
  final CloudProvider provider;
  final BeeCountSyncEngine sync;

  Future<void> run() async {
    await _ensureLocalTables();
    if (provider.databaseService == null) return;
    if (provider.currentUserId == null) return;

    await sync.flush();

    final remote = <String, List<Map<String, dynamic>>>{
      'ledgers': await _fetch('ledgers'),
      'accounts': await _fetch('accounts'),
      'categories': await _fetch('categories'),
      'tags': await _fetch('tags'),
      'budgets': await _fetch('budgets'),
      'recurring_transactions': await _fetch('recurring_transactions'),
      'transactions': await _fetch('transactions'),
      'transaction_tags': await _fetch('transaction_tags'),
    };

    await _merge(remote);
    await sync.flush();
  }

  Future<void> _ensureLocalTables() async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS local_change_log (
        entity TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        PRIMARY KEY (entity, local_id)
      );
    ''');
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_id_maps_remote ON sync_id_maps(entity, remote_id);',
    );
  }

  Future<List<Map<String, dynamic>>> _fetch(String table) async {
    try {
      final results = await provider.databaseService!.query(table: table);
      return results;
    } catch (e, st) {
      logger.error('InitialSync', '拉取失败: $table', e, st);
      return const [];
    }
  }

  Future<int?> _localIdByRemoteId(String entity, int remoteId) async {
    final row = await db.customSelect(
      'SELECT local_id FROM sync_id_maps WHERE entity=? AND remote_id=? LIMIT 1',
      variables: [d.Variable.withString(entity), d.Variable.withInt(remoteId)],
    ).getSingleOrNull();
    return (row?.data['local_id'] as num?)?.toInt();
  }

  Future<int?> _remoteIdByLocalId(String entity, int localId) async {
    final row = await db.customSelect(
      'SELECT remote_id FROM sync_id_maps WHERE entity=? AND local_id=? LIMIT 1',
      variables: [d.Variable.withString(entity), d.Variable.withInt(localId)],
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

  Future<int> _localUpdatedAtSec(String entity, int localId) async {
    final row = await db.customSelect(
      'SELECT updated_at FROM local_change_log WHERE entity=? AND local_id=? LIMIT 1',
      variables: [d.Variable.withString(entity), d.Variable.withInt(localId)],
    ).getSingleOrNull();
    return (row?.data['updated_at'] as num?)?.toInt() ?? 0;
  }

  Future<void> _setLocalUpdatedAtSec(String entity, int localId, int sec) async {
    await db.customStatement(
      '''
      INSERT INTO local_change_log(entity, local_id, updated_at)
      VALUES(?, ?, ?)
      ON CONFLICT(entity, local_id) DO UPDATE SET
        updated_at=excluded.updated_at;
      ''',
      [entity, localId, sec],
    );
  }

  int _remoteUpdatedAtSec(Map<String, dynamic> row) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final dt = parse(row['updated_at']) ??
        parse(row['updatedAt']) ??
        parse(row['created_at']) ??
        parse(row['createdAt']) ??
        parse(row['happened_at']) ??
        parse(row['happenedAt']) ??
        parse(row['start_date']) ??
        parse(row['startDate']);

    logger.info('InitialSync', '解析时间 $dt');
    if (dt == null) return 0;
    return dt.toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  Future<void> _merge(Map<String, List<Map<String, dynamic>>> remote) async {
    final order = [
      'ledgers',
      'accounts',
      'categories',
      'tags',
      'budgets',
      'recurring_transactions',
      'transactions',
      'transaction_tags',
    ];

    var progressed = true;
    var rounds = 0;
    while (progressed && rounds < 6) {
      rounds++;
      progressed = false;

      for (final entity in order) {
        final rows = remote[entity] ?? const [];
        for (final r in rows) {
          final idRaw = r['id'];
          if (idRaw == null) continue;
          final remoteId = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
          if (remoteId == null) continue;

          logger.info('InitialSync', '合并 $entity  $remoteId');
          final did = await _mergeOne(entity, remoteId, r);
          if (did) progressed = true;
        }
      }
    }
  }

  Future<bool> _mergeOne(
    String entity,
    int remoteId,
    Map<String, dynamic> row,
  ) async {
    final remoteSec = _remoteUpdatedAtSec(row);
    final localId = await _localIdByRemoteId(entity, remoteId);
    if (localId == null) {
      final inserted = await _insertRemote(entity, row);
      if (inserted == null) return false;
      await _saveIdMap(entity, inserted, remoteId);
      await _setLocalUpdatedAtSec(entity, inserted, remoteSec);
      return true;
    }

    final localSec = await _localUpdatedAtSec(entity, localId);
    if (remoteSec > localSec) {
      final ok = await _applyRemoteUpdate(entity, localId, row);
      if (ok) {
        await _setLocalUpdatedAtSec(entity, localId, remoteSec);
        return true;
      }
      return false;
    }

    if (localSec > remoteSec) {
      final mappedRemote = await _remoteIdByLocalId(entity, localId);
      if (mappedRemote != null) {
        await sync.enqueueUpsert(entity, localId);
        return true;
      }
    }

    return false;
  }

  Future<int?> _insertRemote(String entity, Map<String, dynamic> row) async {
    try {
      switch (entity) {
        case 'ledgers':
          final name = (row['name'] ?? 'Ledger').toString();
          final currency = (row['currency'] ?? 'CNY').toString();
          final type = (row['type'] ?? 'personal').toString();
          return await db.into(db.ledgers).insert(
                LedgersCompanion.insert(
                  name: name,
                  currency: d.Value(currency),
                  type: d.Value(type),
                ),
              );

        case 'accounts':
          final remoteLedgerId = row['ledger_id'];
          final remoteLedger = remoteLedgerId is int
              ? remoteLedgerId
              : int.tryParse(remoteLedgerId.toString());
          if (remoteLedger == null) return null;
          final localLedgerId = await _localIdByRemoteId('ledgers', remoteLedger);
          if (localLedgerId == null) return null;

          DateTime? parseDt(dynamic v) {
            if (v == null) return null;
            if (v is DateTime) return v;
            if (v is String) {
              try {
                return DateTime.parse(v);
              } catch (_) {
                return null;
              }
            }
            return null;
          }

          final createdAt = parseDt(row['created_at']) ?? parseDt(row['createdAt']) ?? DateTime.now();
          return await db.into(db.accounts).insert(
                AccountsCompanion.insert(
                  ledgerId: localLedgerId,
                  name: (row['name'] ?? '').toString(),
                  type: d.Value((row['type'] ?? 'cash').toString()),
                  currency: d.Value((row['currency'] ?? 'CNY').toString()),
                  initialBalance: d.Value(((row['initial_balance'] ?? 0) as num).toDouble()),
                  createdAt: d.Value(createdAt),
                ),
              );

        case 'categories':
          int? parentLocalId;
          final parentRemote = row['parent_id'];
          if (parentRemote != null) {
            final parentRemoteId = parentRemote is int ? parentRemote : int.tryParse(parentRemote.toString());
            if (parentRemoteId == null) return null;
            parentLocalId = await _localIdByRemoteId('categories', parentRemoteId);
            if (parentLocalId == null) return null;
          }

          return await db.into(db.categories).insert(
                CategoriesCompanion.insert(
                  name: (row['name'] ?? '').toString(),
                  kind: (row['kind'] ?? 'expense').toString(),
                  icon: d.Value(row['icon']?.toString()),
                  sortOrder: d.Value((row['sort_order'] as num?)?.toInt() ?? 0),
                  parentId: d.Value(parentLocalId),
                  level: d.Value((row['level'] as num?)?.toInt() ?? (parentLocalId == null ? 1 : 2)),
                  iconType: d.Value((row['icon_type'] ?? 'material').toString()),
                  customIconPath: d.Value(row['custom_icon_path']?.toString()),
                  communityIconId: d.Value(row['community_icon_id']?.toString()),
                ),
              );

        case 'tags':
          return await db.into(db.tags).insert(
                TagsCompanion.insert(
                  name: (row['name'] ?? '').toString(),
                  color: d.Value(row['color']?.toString()),
                  sortOrder: d.Value((row['sort_order'] as num?)?.toInt() ?? 0),
                ),
              );

        case 'budgets':
          final remoteLedgerId = row['ledger_id'];
          final remoteLedger = remoteLedgerId is int ? remoteLedgerId : int.tryParse(remoteLedgerId.toString());
          if (remoteLedger == null) return null;
          final localLedgerId = await _localIdByRemoteId('ledgers', remoteLedger);
          if (localLedgerId == null) return null;

          int? localCategoryId;
          final remoteCategoryId = row['category_id'];
          if (remoteCategoryId != null) {
            final remoteCat = remoteCategoryId is int ? remoteCategoryId : int.tryParse(remoteCategoryId.toString());
            if (remoteCat == null) return null;
            localCategoryId = await _localIdByRemoteId('categories', remoteCat);
            if (localCategoryId == null) return null;
          }

          return await db.into(db.budgets).insert(
                BudgetsCompanion.insert(
                  ledgerId: localLedgerId,
                  year: (row['year'] as num?)?.toInt() ?? DateTime.now().year,
                  month: (row['month'] as num?)?.toInt() ?? DateTime.now().month,
                  categoryId: d.Value(localCategoryId),
                  amount: ((row['amount'] ?? 0) as num).toDouble(),
                  prompt: d.Value((row['prompt'] as bool?) ?? false),
                  promptDay: d.Value((row['prompt_day'] as num?)?.toInt()),
                  ignored: d.Value(row['ignored'] as bool?),
                ),
              );

        case 'recurring_transactions':
          final remoteLedgerId = row['ledger_id'];
          final remoteLedger = remoteLedgerId is int ? remoteLedgerId : int.tryParse(remoteLedgerId.toString());
          if (remoteLedger == null) return null;
          final localLedgerId = await _localIdByRemoteId('ledgers', remoteLedger);
          if (localLedgerId == null) return null;

          int? localCategoryId;
          final remoteCategoryId = row['category_id'];
          if (remoteCategoryId != null) {
            final remoteCat = remoteCategoryId is int ? remoteCategoryId : int.tryParse(remoteCategoryId.toString());
            if (remoteCat == null) return null;
            localCategoryId = await _localIdByRemoteId('categories', remoteCat);
            if (localCategoryId == null) return null;
          }

          int? localAccountId;
          final remoteAccountId = row['account_id'];
          if (remoteAccountId != null) {
            final remoteAcc = remoteAccountId is int ? remoteAccountId : int.tryParse(remoteAccountId.toString());
            if (remoteAcc == null) return null;
            localAccountId = await _localIdByRemoteId('accounts', remoteAcc);
            if (localAccountId == null) return null;
          }

          int? localToAccountId;
          final remoteToAccountId = row['to_account_id'];
          if (remoteToAccountId != null) {
            final remoteAcc = remoteToAccountId is int ? remoteToAccountId : int.tryParse(remoteToAccountId.toString());
            if (remoteAcc == null) return null;
            localToAccountId = await _localIdByRemoteId('accounts', remoteAcc);
            if (localToAccountId == null) return null;
          }

          final startDate = DateTime.tryParse((row['start_date'] ?? '').toString()) ?? DateTime.now();
          final endRaw = row['end_date'];
          final endDate = endRaw == null ? null : DateTime.tryParse(endRaw.toString());
          final lastGenRaw = row['last_generated_date'];
          final lastGenerated = lastGenRaw == null ? null : DateTime.tryParse(lastGenRaw.toString());

          return await db.into(db.recurringTransactions).insert(
                RecurringTransactionsCompanion.insert(
                  ledgerId: localLedgerId,
                  type: (row['type'] ?? 'expense').toString(),
                  amount: ((row['amount'] ?? 0) as num).toDouble(),
                  categoryId: d.Value(localCategoryId),
                  accountId: d.Value(localAccountId),
                  toAccountId: d.Value(localToAccountId),
                  note: d.Value(row['note']?.toString()),
                  frequency: (row['frequency'] ?? 'monthly').toString(),
                  interval: d.Value((row['interval'] as num?)?.toInt() ?? 1),
                  dayOfMonth: d.Value((row['day_of_month'] as num?)?.toInt()),
                  dayOfWeek: d.Value((row['day_of_week'] as num?)?.toInt()),
                  monthOfYear: d.Value((row['month_of_year'] as num?)?.toInt()),
                  startDate: startDate,
                  endDate: d.Value(endDate),
                  lastGeneratedDate: d.Value(lastGenerated),
                  enabled: d.Value((row['enabled'] as bool?) ?? true),
                ),
              );

        case 'transactions':
          final remoteLedgerId = row['ledger_id'];
          final remoteLedger = remoteLedgerId is int ? remoteLedgerId : int.tryParse(remoteLedgerId.toString());
          if (remoteLedger == null) return null;
          final localLedgerId = await _localIdByRemoteId('ledgers', remoteLedger);
          if (localLedgerId == null) return null;

          int? localCategoryId;
          final remoteCategoryId = row['category_id'];
          if (remoteCategoryId != null) {
            final remoteCat = remoteCategoryId is int ? remoteCategoryId : int.tryParse(remoteCategoryId.toString());
            if (remoteCat == null) return null;
            localCategoryId = await _localIdByRemoteId('categories', remoteCat);
            if (localCategoryId == null) return null;
          }

          int? localAccountId;
          final remoteAccountId = row['account_id'];
          if (remoteAccountId != null) {
            final remoteAcc = remoteAccountId is int ? remoteAccountId : int.tryParse(remoteAccountId.toString());
            if (remoteAcc == null) return null;
            localAccountId = await _localIdByRemoteId('accounts', remoteAcc);
            if (localAccountId == null) return null;
          }

          int? localToAccountId;
          final remoteToAccountId = row['to_account_id'];
          if (remoteToAccountId != null) {
            final remoteAcc = remoteToAccountId is int ? remoteToAccountId : int.tryParse(remoteToAccountId.toString());
            if (remoteAcc == null) return null;
            localToAccountId = await _localIdByRemoteId('accounts', remoteAcc);
            if (localToAccountId == null) return null;
          }

          int? localRecurringId;
          final remoteRecurringId = row['recurring_id'];
          if (remoteRecurringId != null) {
            final remoteRec = remoteRecurringId is int ? remoteRecurringId : int.tryParse(remoteRecurringId.toString());
            if (remoteRec == null) return null;
            localRecurringId = await _localIdByRemoteId('recurring_transactions', remoteRec);
            if (localRecurringId == null) return null;
          }

          final happenedAt = DateTime.tryParse((row['happened_at'] ?? '').toString()) ?? DateTime.now();

          return await db.into(db.transactions).insert(
                TransactionsCompanion.insert(
                  ledgerId: localLedgerId,
                  type: (row['type'] ?? 'expense').toString(),
                  amount: ((row['amount'] ?? 0) as num).toDouble(),
                  categoryId: d.Value(localCategoryId),
                  accountId: d.Value(localAccountId),
                  toAccountId: d.Value(localToAccountId),
                  happenedAt: d.Value(happenedAt),
                  note: d.Value(row['note']?.toString()),
                  recurringId: d.Value(localRecurringId),
                ),
              );

        case 'transaction_tags':
          final remoteTx = row['transaction_id'];
          final remoteTag = row['tag_id'];
          final txId = remoteTx is int ? remoteTx : int.tryParse(remoteTx.toString());
          final tagId = remoteTag is int ? remoteTag : int.tryParse(remoteTag.toString());
          if (txId == null || tagId == null) return null;

          final localTxId = await _localIdByRemoteId('transactions', txId);
          final localTagId = await _localIdByRemoteId('tags', tagId);
          if (localTxId == null || localTagId == null) return null;

          return await db.into(db.transactionTags).insert(
                TransactionTagsCompanion.insert(
                  transactionId: localTxId,
                  tagId: localTagId,
                ),
              );
      }
    } catch (e, st) {
      logger.error('InitialSync', '插入失败: $entity', e, st);
    }
    return null;
  }

  Future<bool> _applyRemoteUpdate(String entity, int localId, Map<String, dynamic> row) async {
    try {
      switch (entity) {
        case 'ledgers':
          await (db.update(db.ledgers)..where((t) => t.id.equals(localId))).write(
            LedgersCompanion(
              name: d.Value((row['name'] ?? '').toString()),
              currency: d.Value((row['currency'] ?? 'CNY').toString()),
              type: d.Value((row['type'] ?? 'personal').toString()),
            ),
          );
          return true;

        case 'accounts':
          final remoteLedgerId = row['ledger_id'];
          final remoteLedger = remoteLedgerId is int ? remoteLedgerId : int.tryParse(remoteLedgerId.toString());
          if (remoteLedger == null) return false;
          final localLedgerId = await _localIdByRemoteId('ledgers', remoteLedger);
          if (localLedgerId == null) return false;

          await (db.update(db.accounts)..where((t) => t.id.equals(localId))).write(
            AccountsCompanion(
              ledgerId: d.Value(localLedgerId),
              name: d.Value((row['name'] ?? '').toString()),
              type: d.Value((row['type'] ?? 'cash').toString()),
              currency: d.Value((row['currency'] ?? 'CNY').toString()),
              initialBalance: d.Value(((row['initial_balance'] ?? 0) as num).toDouble()),
            ),
          );
          return true;

        case 'categories':
          int? parentLocalId;
          final parentRemote = row['parent_id'];
          if (parentRemote != null) {
            final parentRemoteId = parentRemote is int ? parentRemote : int.tryParse(parentRemote.toString());
            if (parentRemoteId == null) return false;
            parentLocalId = await _localIdByRemoteId('categories', parentRemoteId);
            if (parentLocalId == null) return false;
          }

          await (db.update(db.categories)..where((t) => t.id.equals(localId))).write(
            CategoriesCompanion(
              name: d.Value((row['name'] ?? '').toString()),
              kind: d.Value((row['kind'] ?? 'expense').toString()),
              icon: d.Value(row['icon']?.toString()),
              sortOrder: d.Value((row['sort_order'] as num?)?.toInt() ?? 0),
              parentId: d.Value(parentLocalId),
              level: d.Value((row['level'] as num?)?.toInt() ?? (parentLocalId == null ? 1 : 2)),
              iconType: d.Value((row['icon_type'] ?? 'material').toString()),
              customIconPath: d.Value(row['custom_icon_path']?.toString()),
              communityIconId: d.Value(row['community_icon_id']?.toString()),
            ),
          );
          return true;

        case 'tags':
          await (db.update(db.tags)..where((t) => t.id.equals(localId))).write(
            TagsCompanion(
              name: d.Value((row['name'] ?? '').toString()),
              color: d.Value(row['color']?.toString()),
              sortOrder: d.Value((row['sort_order'] as num?)?.toInt() ?? 0),
            ),
          );
          return true;

        case 'budgets':
          final remoteLedgerId = row['ledger_id'];
          final remoteLedger = remoteLedgerId is int ? remoteLedgerId : int.tryParse(remoteLedgerId.toString());
          if (remoteLedger == null) return false;
          final localLedgerId = await _localIdByRemoteId('ledgers', remoteLedger);
          if (localLedgerId == null) return false;

          int? localCategoryId;
          final remoteCategoryId = row['category_id'];
          if (remoteCategoryId != null) {
            final remoteCat = remoteCategoryId is int ? remoteCategoryId : int.tryParse(remoteCategoryId.toString());
            if (remoteCat == null) return false;
            localCategoryId = await _localIdByRemoteId('categories', remoteCat);
            if (localCategoryId == null) return false;
          }

          await (db.update(db.budgets)..where((t) => t.id.equals(localId))).write(
            BudgetsCompanion(
              ledgerId: d.Value(localLedgerId),
              year: d.Value((row['year'] as num?)?.toInt() ?? DateTime.now().year),
              month: d.Value((row['month'] as num?)?.toInt() ?? DateTime.now().month),
              categoryId: d.Value(localCategoryId),
              amount: d.Value(((row['amount'] ?? 0) as num).toDouble()),
              enabled: d.Value((row['enabled'] as bool?) ?? true),
              prompt: d.Value((row['prompt'] as bool?) ?? false),
              promptDay: d.Value((row['prompt_day'] as num?)?.toInt()),
              ignored: d.Value(row['ignored'] as bool?),
              updatedAt: d.Value(DateTime.now()),
            ),
          );
          return true;

        case 'recurring_transactions':
          final remoteLedgerId = row['ledger_id'];
          final remoteLedger = remoteLedgerId is int ? remoteLedgerId : int.tryParse(remoteLedgerId.toString());
          if (remoteLedger == null) return false;
          final localLedgerId = await _localIdByRemoteId('ledgers', remoteLedger);
          if (localLedgerId == null) return false;

          int? localCategoryId;
          final remoteCategoryId = row['category_id'];
          if (remoteCategoryId != null) {
            final remoteCat = remoteCategoryId is int ? remoteCategoryId : int.tryParse(remoteCategoryId.toString());
            if (remoteCat == null) return false;
            localCategoryId = await _localIdByRemoteId('categories', remoteCat);
            if (localCategoryId == null) return false;
          }

          int? localAccountId;
          final remoteAccountId = row['account_id'];
          if (remoteAccountId != null) {
            final remoteAcc = remoteAccountId is int ? remoteAccountId : int.tryParse(remoteAccountId.toString());
            if (remoteAcc == null) return false;
            localAccountId = await _localIdByRemoteId('accounts', remoteAcc);
            if (localAccountId == null) return false;
          }

          int? localToAccountId;
          final remoteToAccountId = row['to_account_id'];
          if (remoteToAccountId != null) {
            final remoteAcc = remoteToAccountId is int ? remoteToAccountId : int.tryParse(remoteToAccountId.toString());
            if (remoteAcc == null) return false;
            localToAccountId = await _localIdByRemoteId('accounts', remoteAcc);
            if (localToAccountId == null) return false;
          }

          final startDate = DateTime.tryParse((row['start_date'] ?? '').toString()) ?? DateTime.now();
          final endRaw = row['end_date'];
          final endDate = endRaw == null ? null : DateTime.tryParse(endRaw.toString());
          final lastGenRaw = row['last_generated_date'];
          final lastGenerated = lastGenRaw == null ? null : DateTime.tryParse(lastGenRaw.toString());

          await (db.update(db.recurringTransactions)..where((t) => t.id.equals(localId))).write(
            RecurringTransactionsCompanion(
              ledgerId: d.Value(localLedgerId),
              type: d.Value((row['type'] ?? 'expense').toString()),
              amount: d.Value(((row['amount'] ?? 0) as num).toDouble()),
              categoryId: d.Value(localCategoryId),
              accountId: d.Value(localAccountId),
              toAccountId: d.Value(localToAccountId),
              note: d.Value(row['note']?.toString()),
              frequency: d.Value((row['frequency'] ?? 'monthly').toString()),
              interval: d.Value((row['interval'] as num?)?.toInt() ?? 1),
              dayOfMonth: d.Value((row['day_of_month'] as num?)?.toInt()),
              dayOfWeek: d.Value((row['day_of_week'] as num?)?.toInt()),
              monthOfYear: d.Value((row['month_of_year'] as num?)?.toInt()),
              startDate: d.Value(startDate),
              endDate: d.Value(endDate),
              lastGeneratedDate: d.Value(lastGenerated),
              enabled: d.Value((row['enabled'] as bool?) ?? true),
              updatedAt: d.Value(DateTime.now()),
            ),
          );
          return true;

        case 'transactions':
          final remoteLedgerId = row['ledger_id'];
          final remoteLedger = remoteLedgerId is int ? remoteLedgerId : int.tryParse(remoteLedgerId.toString());
          if (remoteLedger == null) return false;
          final localLedgerId = await _localIdByRemoteId('ledgers', remoteLedger);
          if (localLedgerId == null) return false;

          int? localCategoryId;
          final remoteCategoryId = row['category_id'];
          if (remoteCategoryId != null) {
            final remoteCat = remoteCategoryId is int ? remoteCategoryId : int.tryParse(remoteCategoryId.toString());
            if (remoteCat == null) return false;
            localCategoryId = await _localIdByRemoteId('categories', remoteCat);
            if (localCategoryId == null) return false;
          }

          int? localAccountId;
          final remoteAccountId = row['account_id'];
          if (remoteAccountId != null) {
            final remoteAcc = remoteAccountId is int ? remoteAccountId : int.tryParse(remoteAccountId.toString());
            if (remoteAcc == null) return false;
            localAccountId = await _localIdByRemoteId('accounts', remoteAcc);
            if (localAccountId == null) return false;
          }

          int? localToAccountId;
          final remoteToAccountId = row['to_account_id'];
          if (remoteToAccountId != null) {
            final remoteAcc = remoteToAccountId is int ? remoteToAccountId : int.tryParse(remoteToAccountId.toString());
            if (remoteAcc == null) return false;
            localToAccountId = await _localIdByRemoteId('accounts', remoteAcc);
            if (localToAccountId == null) return false;
          }

          int? localRecurringId;
          final remoteRecurringId = row['recurring_id'];
          if (remoteRecurringId != null) {
            final remoteRec = remoteRecurringId is int ? remoteRecurringId : int.tryParse(remoteRecurringId.toString());
            if (remoteRec == null) return false;
            localRecurringId = await _localIdByRemoteId('recurring_transactions', remoteRec);
            if (localRecurringId == null) return false;
          }

          final happenedAt = DateTime.tryParse((row['happened_at'] ?? '').toString()) ?? DateTime.now();

          await (db.update(db.transactions)..where((t) => t.id.equals(localId))).write(
            TransactionsCompanion(
              ledgerId: d.Value(localLedgerId),
              type: d.Value((row['type'] ?? 'expense').toString()),
              amount: d.Value(((row['amount'] ?? 0) as num).toDouble()),
              categoryId: d.Value(localCategoryId),
              accountId: d.Value(localAccountId),
              toAccountId: d.Value(localToAccountId),
              happenedAt: d.Value(happenedAt),
              note: d.Value(row['note']?.toString()),
              recurringId: d.Value(localRecurringId),
            ),
          );
          return true;

        case 'transaction_tags':
          final remoteTx = row['transaction_id'];
          final remoteTag = row['tag_id'];
          final txId = remoteTx is int ? remoteTx : int.tryParse(remoteTx.toString());
          final tagId = remoteTag is int ? remoteTag : int.tryParse(remoteTag.toString());
          if (txId == null || tagId == null) return false;

          final localTxId = await _localIdByRemoteId('transactions', txId);
          final localTagId = await _localIdByRemoteId('tags', tagId);
          if (localTxId == null || localTagId == null) return false;

          await (db.update(db.transactionTags)..where((t) => t.id.equals(localId))).write(
            TransactionTagsCompanion(
              transactionId: d.Value(localTxId),
              tagId: d.Value(localTagId),
            ),
          );
          return true;
      }
    } catch (e, st) {
      logger.error('InitialSync', '更新失败: $entity', e, st);
    }
    return false;
  }
}
