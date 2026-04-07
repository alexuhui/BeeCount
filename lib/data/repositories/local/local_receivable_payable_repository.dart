import 'dart:async';

import 'package:drift/drift.dart' as d;

import '../../../services/system/logger_service.dart';
import '../../db.dart';
import '../receivable_payable_repository.dart';

/// 应收款和应付款本地数据库实现
class LocalReceivablePayableRepository implements ReceivablePayableRepository {
  final BeeDatabase db;

  LocalReceivablePayableRepository(this.db);

  // ========== 应收款相关 ==========

  @override
  Future<int> createReceivable({
    required int accountId,
    required String borrowerName,
    required double amount,
    required DateTime borrowDate,
    String? note,
    int? fromAccountId,
    bool isReceived = false,
    DateTime? receiveDate,
    int? toAccountId,
  }) async {
    return db.transaction(() async {
      final now = DateTime.now();
      final id = await db.into(db.receivables).insert(ReceivablesCompanion.insert(
            accountId: accountId,
            borrowerName: borrowerName,
            amount: amount,
            borrowDate: borrowDate,
            fromAccountId: fromAccountId != null ? d.Value(fromAccountId) : const d.Value.absent(),
            note: d.Value(note),
            isReceived: d.Value(isReceived),
            receiveDate: d.Value(receiveDate),
            toAccountId: d.Value(toAccountId),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
          ));

      if (fromAccountId != null) {
        final fromAccount = await (db.select(db.accounts)..where((a) => a.id.equals(fromAccountId))).getSingle();
        final ledgerId = fromAccount.ledgerId;

        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: 'transfer',
              amount: amount,
              accountId: d.Value(fromAccountId),
              toAccountId: d.Value(accountId),
              happenedAt: d.Value(borrowDate),
              note: d.Value('借出给 $borrowerName${note != null ? ": $note" : ""}'),
              excludeFromStats: const d.Value(true),
              receivableId: d.Value(id),
            ));
      }

      if (isReceived && toAccountId != null) {
        await addReceivablePayment(
          receivableId: id,
          amount: amount,
          happenedAt: receiveDate ?? now,
          accountId: toAccountId,
          note: '初始全额收款',
        );
      }

      logger.info('LocalReceivablePayableRepository',
          '创建应收款记录并关联交易: id=$id, borrowerName=$borrowerName, amount=$amount');

      return id;
    });
  }

  @override
  Future<void> updateReceivable({
    required int id,
    String? borrowerName,
    double? amount,
    DateTime? borrowDate,
    String? note,
    int? fromAccountId,
    bool applyFromAccountId = false,
    bool? isReceived,
    DateTime? receiveDate,
    int? toAccountId,
    DateTime? updatedAt,
  }) async {
    await db.transaction(() async {
      final receivable = await (db.select(db.receivables)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (receivable == null) {
        throw Exception('应收款记录不存在: $id');
      }

      final isStatusChanged = isReceived != null && isReceived != receivable.isReceived;

      await (db.update(db.receivables)..where((t) => t.id.equals(id))).write(
        ReceivablesCompanion(
          borrowerName: borrowerName != null ? d.Value(borrowerName) : d.Value.absent(),
          amount: amount != null ? d.Value(amount) : d.Value.absent(),
          borrowDate: borrowDate != null ? d.Value(borrowDate) : d.Value.absent(),
          note: note != null ? d.Value(note) : d.Value.absent(),
          fromAccountId: applyFromAccountId ? d.Value(fromAccountId) : d.Value.absent(),
          isReceived: isReceived != null ? d.Value(isReceived) : d.Value.absent(),
          receiveDate: receiveDate != null ? d.Value(receiveDate) : d.Value.absent(),
          toAccountId: toAccountId != null ? d.Value(toAccountId) : d.Value.absent(),
          updatedAt: d.Value(updatedAt ?? DateTime.now()),
        ),
      );

      final currentReceivable = await (db.select(db.receivables)..where((t) => t.id.equals(id))).getSingle();

      await _syncReceivableBorrowHiddenTransfer(currentReceivable);

      if (isStatusChanged) {
        if (currentReceivable.isReceived) {
          final allPayments = await (db.select(db.receivablePayments)..where((p) => p.receivableId.equals(id))).get();
          final totalPaid = allPayments.fold<double>(0, (sum, p) => sum + p.amount);
          final remaining = currentReceivable.amount - totalPaid;

          if (remaining > 0) {
            await addReceivablePayment(
              receivableId: id,
              amount: remaining,
              happenedAt: receiveDate ?? currentReceivable.receiveDate ?? DateTime.now(),
              accountId: toAccountId ?? currentReceivable.toAccountId,
              note: '手动标记为已收',
            );
          }
        }
      }

      logger.info('LocalReceivablePayableRepository', '更新应收款记录及其关联交易: id=$id');
    });
  }

  /// 同步「借出」隐藏转账：有借款账户时创建/更新，无则删除。
  Future<void> _syncReceivableBorrowHiddenTransfer(Receivable r) async {
    final borrowTx = await _findReceivableBorrowTransfer(r.id);

    if (r.fromAccountId == null) {
      if (borrowTx != null) {
        await (db.delete(db.transactions)..where((t) => t.id.equals(borrowTx.id))).go();
      }
      return;
    }

    final fromAccount = await (db.select(db.accounts)..where((a) => a.id.equals(r.fromAccountId!))).getSingle();
    final ledgerId = fromAccount.ledgerId;
    final noteText =
        '借出给 ${r.borrowerName}${r.note != null && r.note!.isNotEmpty ? ": ${r.note}" : ""}';

    if (borrowTx != null) {
      await (db.update(db.transactions)..where((t) => t.id.equals(borrowTx.id))).write(
            TransactionsCompanion(
              ledgerId: d.Value(ledgerId),
              amount: d.Value(r.amount),
              happenedAt: d.Value(r.borrowDate),
              accountId: d.Value(r.fromAccountId!),
              toAccountId: d.Value(r.accountId),
              note: d.Value(noteText),
            ),
          );
    } else {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'transfer',
            amount: r.amount,
            accountId: d.Value(r.fromAccountId!),
            toAccountId: d.Value(r.accountId),
            happenedAt: d.Value(r.borrowDate),
            note: d.Value(noteText),
            excludeFromStats: const d.Value(true),
            receivableId: d.Value(r.id),
          ));
    }
  }

  Future<Transaction?> _findReceivableBorrowTransfer(int receivableId) async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.receivableId.equals(receivableId) &
              t.receivablePaymentId.isNull() &
              t.type.equals('transfer')))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> deleteReceivable(int id) async {
    await db.transaction(() async {
      // 先删除关联交易
      await (db.delete(db.transactions)..where((t) => t.receivableId.equals(id))).go();
      // 再删除记录
      await (db.delete(db.receivables)..where((t) => t.id.equals(id))).go();
      logger.info('LocalReceivablePayableRepository', '删除应收款记录及其关联交易: id=$id');
    });
  }

  @override
  Future<List<Receivable>> getReceivablesByAccountId(int accountId) async {
    return await (db.select(db.receivables)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.borrowDate)]))
        .get();
  }

  @override
  Stream<List<Receivable>> watchReceivablesByAccountId(int accountId) {
    return (db.select(db.receivables)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.borrowDate)]))
        .watch();
  }

  @override
  Future<Receivable?> getReceivableById(int id) async {
    return await (db.select(db.receivables)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  @override
  Future<double> getReceivableBalance(int accountId) async {
    final receivables = await (db.select(db.receivables)
          ..where((t) => t.accountId.equals(accountId) & t.isReceived.equals(false)))
        .get();

    double sum = 0.0;
    for (final r in receivables) {
      final payments = await (db.select(db.receivablePayments)
            ..where((p) => p.receivableId.equals(r.id)))
          .get();
      final paidAmount = payments.fold<double>(0, (s, p) => s + p.amount);
      sum += (r.amount - paidAmount);
    }
    return sum;
  }

  @override
  Future<({double pending, double total, double received})> getReceivableStats(int accountId) async {
    final receivables = await (db.select(db.receivables)
          ..where((t) => t.accountId.equals(accountId)))
        .get();

    double pending = 0.0;
    double total = 0.0;
    double received = 0.0;

    for (final r in receivables) {
      total += r.amount;
      final payments = await (db.select(db.receivablePayments)
            ..where((p) => p.receivableId.equals(r.id)))
          .get();
      final paidAmount = payments.fold<double>(0, (s, p) => s + p.amount);

      received += paidAmount;
      if (!r.isReceived) {
        pending += (r.amount - paidAmount);
      }
    }

    return (pending: pending, total: total, received: received);
  }

  @override
  Future<Map<int, double>> getReceivableOutstandingMapForAccount(int accountId) async {
    final rows = await db.customSelect(
      '''
      SELECT r.id AS rid, r.amount AS amt, COALESCE(SUM(p.amount), 0) AS paid
      FROM receivables r
      LEFT JOIN receivable_payments p ON p.receivable_id = r.id
      WHERE r.account_id = ?
      GROUP BY r.id, r.amount
      ''',
      variables: [d.Variable.withInt(accountId)],
      readsFrom: {db.receivables, db.receivablePayments},
    ).get();

    final map = <int, double>{};
    for (final row in rows) {
      final id = row.data['rid'] as int;
      final amt = (row.data['amt'] as num).toDouble();
      final paid = (row.data['paid'] as num).toDouble();
      final remaining = amt - paid;
      map[id] = remaining > 0 ? remaining : 0.0;
    }
    return map;
  }

  @override
  Stream<Map<int, double>> watchReceivableOutstandingMapForAccount(int accountId) {
    return Stream<Map<int, double>>.multi((controller) {
      Future<void> emit() async {
        try {
          final m = await getReceivableOutstandingMapForAccount(accountId);
          if (!controller.isClosed) controller.add(m);
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      }

      emit();
      final sub1 = (db.select(db.receivables)..where((t) => t.accountId.equals(accountId)))
          .watch()
          .listen((_) => emit());
      final sub2 = db.select(db.receivablePayments).watch().listen((_) => emit());
      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
      };
    });
  }

  // ========== 应付款相关 ==========

  @override
  Future<int> createPayable({
    required int accountId,
    required String payeeName,
    required double amount,
    required DateTime payDate,
    String? note,
    int? toAccountId,
    bool isPaid = false,
    DateTime? paidDate,
    int? fromAccountId,
  }) async {
    return db.transaction(() async {
      final now = DateTime.now();
      final id = await db.into(db.payables).insert(PayablesCompanion.insert(
            accountId: accountId,
            payeeName: payeeName,
            amount: amount,
            payDate: payDate,
            toAccountId: toAccountId != null ? d.Value(toAccountId) : const d.Value.absent(),
            note: d.Value(note),
            isPaid: d.Value(isPaid),
            paidDate: d.Value(paidDate),
            fromAccountId: d.Value(fromAccountId),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
          ));

      if (toAccountId != null) {
        final toAccount = await (db.select(db.accounts)..where((a) => a.id.equals(toAccountId))).getSingle();
        final ledgerId = toAccount.ledgerId;

        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: 'transfer',
              amount: amount,
              accountId: d.Value(accountId),
              toAccountId: d.Value(toAccountId),
              happenedAt: d.Value(payDate),
              note: d.Value('向 $payeeName 借入${note != null ? ": $note" : ""}'),
              excludeFromStats: const d.Value(true),
              payableId: d.Value(id),
            ));
      }

      if (isPaid && fromAccountId != null) {
        await addPayablePayment(
          payableId: id,
          amount: amount,
          happenedAt: paidDate ?? now,
          accountId: fromAccountId,
          note: '初始全额还款',
        );
      }

      logger.info('LocalReceivablePayableRepository',
          '创建应付款记录并关联交易: id=$id, payeeName=$payeeName, amount=$amount');

      return id;
    });
  }

  @override
  Future<void> updatePayable({
    required int id,
    String? payeeName,
    double? amount,
    DateTime? payDate,
    String? note,
    int? toAccountId,
    bool applyToAccountId = false,
    bool? isPaid,
    DateTime? paidDate,
    int? fromAccountId,
    DateTime? updatedAt,
  }) async {
    await db.transaction(() async {
      final payable = await (db.select(db.payables)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (payable == null) {
        throw Exception('应付款记录不存在: $id');
      }

      final isStatusChanged = isPaid != null && isPaid != payable.isPaid;

      await (db.update(db.payables)..where((t) => t.id.equals(id))).write(
        PayablesCompanion(
          payeeName: payeeName != null ? d.Value(payeeName) : d.Value.absent(),
          amount: amount != null ? d.Value(amount) : d.Value.absent(),
          payDate: payDate != null ? d.Value(payDate) : d.Value.absent(),
          note: note != null ? d.Value(note) : d.Value.absent(),
          toAccountId: applyToAccountId ? d.Value(toAccountId) : d.Value.absent(),
          isPaid: isPaid != null ? d.Value(isPaid) : d.Value.absent(),
          paidDate: paidDate != null ? d.Value(paidDate) : d.Value.absent(),
          fromAccountId: fromAccountId != null ? d.Value(fromAccountId) : d.Value.absent(),
          updatedAt: d.Value(updatedAt ?? DateTime.now()),
        ),
      );

      final currentPayable = await (db.select(db.payables)..where((t) => t.id.equals(id))).getSingle();

      await _syncPayableBorrowHiddenTransfer(currentPayable);

      if (isStatusChanged) {
        if (currentPayable.isPaid) {
          final allPayments = await (db.select(db.payablePayments)..where((p) => p.payableId.equals(id))).get();
          final totalPaid = allPayments.fold<double>(0, (sum, p) => sum + p.amount);
          final remaining = currentPayable.amount - totalPaid;

          if (remaining > 0) {
            await addPayablePayment(
              payableId: id,
              amount: remaining,
              happenedAt: paidDate ?? currentPayable.paidDate ?? DateTime.now(),
              accountId: fromAccountId ?? currentPayable.fromAccountId,
              note: '手动标记为已还',
            );
          }
        }
      }

      logger.info('LocalReceivablePayableRepository', '更新应付款记录及其关联交易: id=$id');
    });
  }

  /// 同步「借入」隐藏转账：有入账账户时创建/更新，无则删除。
  Future<void> _syncPayableBorrowHiddenTransfer(Payable p) async {
    final borrowTx = await _findPayableBorrowTransfer(p.id);

    if (p.toAccountId == null) {
      if (borrowTx != null) {
        await (db.delete(db.transactions)..where((t) => t.id.equals(borrowTx.id))).go();
      }
      return;
    }

    final toAccount = await (db.select(db.accounts)..where((a) => a.id.equals(p.toAccountId!))).getSingle();
    final ledgerId = toAccount.ledgerId;
    final noteText =
        '向 ${p.payeeName} 借入${p.note != null && p.note!.isNotEmpty ? ": ${p.note}" : ""}';

    if (borrowTx != null) {
      await (db.update(db.transactions)..where((t) => t.id.equals(borrowTx.id))).write(
            TransactionsCompanion(
              ledgerId: d.Value(ledgerId),
              amount: d.Value(p.amount),
              happenedAt: d.Value(p.payDate),
              accountId: d.Value(p.accountId),
              toAccountId: d.Value(p.toAccountId!),
              note: d.Value(noteText),
            ),
          );
    } else {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'transfer',
            amount: p.amount,
            accountId: d.Value(p.accountId),
            toAccountId: d.Value(p.toAccountId!),
            happenedAt: d.Value(p.payDate),
            note: d.Value(noteText),
            excludeFromStats: const d.Value(true),
            payableId: d.Value(p.id),
          ));
    }
  }

  Future<Transaction?> _findPayableBorrowTransfer(int payableId) async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.payableId.equals(payableId) &
              t.payablePaymentId.isNull() &
              t.type.equals('transfer')))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> deletePayable(int id) async {
    await db.transaction(() async {
      await (db.delete(db.transactions)..where((t) => t.payableId.equals(id))).go();
      await (db.delete(db.payables)..where((t) => t.id.equals(id))).go();
      logger.info('LocalReceivablePayableRepository', '删除应付款记录及其关联交易: id=$id');
    });
  }

  @override
  Future<List<Payable>> getPayablesByAccountId(int accountId) async {
    return await (db.select(db.payables)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.payDate)]))
        .get();
  }

  @override
  Stream<List<Payable>> watchPayablesByAccountId(int accountId) {
    return (db.select(db.payables)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.payDate)]))
        .watch();
  }

  @override
  Future<Payable?> getPayableById(int id) async {
    return await (db.select(db.payables)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  @override
  Future<double> getPayableBalance(int accountId) async {
    final payables = await (db.select(db.payables)
          ..where((t) => t.accountId.equals(accountId) & t.isPaid.equals(false)))
        .get();

    double sum = 0.0;
    for (final p in payables) {
      final payments = await (db.select(db.payablePayments)
            ..where((pp) => pp.payableId.equals(p.id)))
          .get();
      final paidAmount = payments.fold<double>(0, (s, pp) => s + pp.amount);
      sum += (p.amount - paidAmount);
    }
    return sum;
  }

  @override
  Future<({double pending, double total, double paid})> getPayableStats(int accountId) async {
    final payables = await (db.select(db.payables)
          ..where((t) => t.accountId.equals(accountId)))
        .get();

    double pending = 0.0;
    double total = 0.0;
    double paid = 0.0;

    for (final p in payables) {
      total += p.amount;
      final payments = await (db.select(db.payablePayments)
            ..where((pp) => pp.payableId.equals(p.id)))
          .get();
      final paidAmount = payments.fold<double>(0, (s, pp) => s + pp.amount);

      paid += paidAmount;
      if (!p.isPaid) {
        pending += (p.amount - paidAmount);
      }
    }

    return (pending: pending, total: total, paid: paid);
  }

  @override
  Future<Map<int, double>> getPayableOutstandingMapForAccount(int accountId) async {
    final rows = await db.customSelect(
      '''
      SELECT p.id AS pid, p.amount AS amt, COALESCE(SUM(pp.amount), 0) AS paid
      FROM payables p
      LEFT JOIN payable_payments pp ON pp.payable_id = p.id
      WHERE p.account_id = ?
      GROUP BY p.id, p.amount
      ''',
      variables: [d.Variable.withInt(accountId)],
      readsFrom: {db.payables, db.payablePayments},
    ).get();

    final map = <int, double>{};
    for (final row in rows) {
      final id = row.data['pid'] as int;
      final amt = (row.data['amt'] as num).toDouble();
      final paid = (row.data['paid'] as num).toDouble();
      final remaining = amt - paid;
      map[id] = remaining > 0 ? remaining : 0.0;
    }
    return map;
  }

  @override
  Stream<Map<int, double>> watchPayableOutstandingMapForAccount(int accountId) {
    return Stream<Map<int, double>>.multi((controller) {
      Future<void> emit() async {
        try {
          final m = await getPayableOutstandingMapForAccount(accountId);
          if (!controller.isClosed) controller.add(m);
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      }

      emit();
      final sub1 = (db.select(db.payables)..where((t) => t.accountId.equals(accountId)))
          .watch()
          .listen((_) => emit());
      final sub2 = db.select(db.payablePayments).watch().listen((_) => emit());
      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
      };
    });
  }

  // ========== 收款/还款记录相关 ==========

  @override
  Future<int> addReceivablePayment({
    required int receivableId,
    required double amount,
    double interestAmount = 0.0,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  }) async {
    return db.transaction(() async {
      final receivable = await (db.select(db.receivables)..where((t) => t.id.equals(receivableId))).getSingle();

      final paymentId = await db.into(db.receivablePayments).insert(ReceivablePaymentsCompanion.insert(
            receivableId: receivableId,
            amount: amount,
            interestAmount: d.Value(interestAmount),
            happenedAt: happenedAt,
            accountId: d.Value(accountId),
            note: d.Value(note),
            createdAt: d.Value(DateTime.now()),
          ));

      // 如果提供了账户，则创建对应的隐藏交易
      if (accountId != null) {
        final account = await (db.select(db.accounts)..where((a) => a.id.equals(accountId))).getSingle();
        final ledgerId = account.ledgerId;

        // 1. 本金回收交易（转账：从应收账户到目标账户）
        if (amount > 0) {
          await db.into(db.transactions).insert(TransactionsCompanion.insert(
                ledgerId: ledgerId,
                type: 'transfer',
                amount: amount,
                accountId: d.Value(receivable.accountId),
                toAccountId: d.Value(accountId),
                happenedAt: d.Value(happenedAt),
                note: d.Value('收回 ${receivable.borrowerName} 的借款${note != null ? ": $note" : ""}'),
                excludeFromStats: const d.Value(true),
                receivableId: d.Value(receivableId),
                receivablePaymentId: d.Value(paymentId),
              ));
        }

        // 2. 利息收入交易（收入：到目标账户）
        if (interestAmount > 0) {
          await db.into(db.transactions).insert(TransactionsCompanion.insert(
                ledgerId: ledgerId,
                type: 'income',
                amount: interestAmount,
                accountId: d.Value(accountId),
                happenedAt: d.Value(happenedAt),
                note: d.Value('来自 ${receivable.borrowerName} 的借款利息${note != null ? ": $note" : ""}'),
                excludeFromStats: const d.Value(true),
                receivableId: d.Value(receivableId),
                receivablePaymentId: d.Value(paymentId),
              ));
        }
      }

      // 检查是否已全额收款
      final allPayments = await (db.select(db.receivablePayments)..where((p) => p.receivableId.equals(receivableId))).get();
      final totalPaid = allPayments.fold<double>(0, (sum, p) => sum + p.amount);

      if (totalPaid >= receivable.amount) {
        await (db.update(db.receivables)..where((t) => t.id.equals(receivableId))).write(ReceivablesCompanion(
          isReceived: const d.Value(true),
          receiveDate: d.Value(happenedAt),
          updatedAt: d.Value(DateTime.now()),
        ));
      }

      return paymentId;
    });
  }

  @override
  Future<void> deleteReceivablePayment(int id) async {
    await db.transaction(() async {
      final payment = await (db.select(db.receivablePayments)..where((p) => p.id.equals(id))).getSingle();
      final receivableId = payment.receivableId;

      // 删除关联的交易
      await (db.delete(db.transactions)..where((t) => t.receivablePaymentId.equals(id))).go();
      
      await (db.delete(db.receivablePayments)..where((p) => p.id.equals(id))).go();
      
      // 更新 receivable 的状态
      final receivable = await (db.select(db.receivables)..where((t) => t.id.equals(receivableId))).getSingle();
      final allPayments = await (db.select(db.receivablePayments)..where((p) => p.receivableId.equals(receivableId))).get();
      final totalPaid = allPayments.fold<double>(0, (sum, p) => sum + p.amount);
      
      if (totalPaid < receivable.amount) {
        await (db.update(db.receivables)..where((t) => t.id.equals(receivableId))).write(ReceivablesCompanion(
          isReceived: const d.Value(false),
          receiveDate: const d.Value(null),
          updatedAt: d.Value(DateTime.now()),
        ));
      }
    });
  }

  @override
  Future<List<ReceivablePayment>> getReceivablePayments(int receivableId) async {
    return await (db.select(db.receivablePayments)
          ..where((p) => p.receivableId.equals(receivableId))
          ..orderBy([(p) => d.OrderingTerm.desc(p.happenedAt)]))
        .get();
  }

  @override
  Stream<List<ReceivablePayment>> watchReceivablePayments(int receivableId) {
    return (db.select(db.receivablePayments)
          ..where((p) => p.receivableId.equals(receivableId))
          ..orderBy([(p) => d.OrderingTerm.desc(p.happenedAt)]))
        .watch();
  }

  @override
  Future<int> addPayablePayment({
    required int payableId,
    required double amount,
    double interestAmount = 0.0,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  }) async {
    return db.transaction(() async {
      final payable = await (db.select(db.payables)..where((t) => t.id.equals(payableId))).getSingle();

      final paymentId = await db.into(db.payablePayments).insert(PayablePaymentsCompanion.insert(
            payableId: payableId,
            amount: amount,
            interestAmount: d.Value(interestAmount),
            happenedAt: happenedAt,
            accountId: d.Value(accountId),
            note: d.Value(note),
            createdAt: d.Value(DateTime.now()),
          ));

      if (accountId != null) {
        final account = await (db.select(db.accounts)..where((a) => a.id.equals(accountId))).getSingle();
        final ledgerId = account.ledgerId;

        // 1. 本金偿还交易（转账：从目标账户到应付账户）
        if (amount > 0) {
          await db.into(db.transactions).insert(TransactionsCompanion.insert(
                ledgerId: ledgerId,
                type: 'transfer',
                amount: amount,
                accountId: d.Value(accountId),
                toAccountId: d.Value(payable.accountId),
                happenedAt: d.Value(happenedAt),
                note: d.Value('偿还 ${payable.payeeName} 的借款${note != null ? ": $note" : ""}'),
                excludeFromStats: const d.Value(true),
                payableId: d.Value(payableId),
                payablePaymentId: d.Value(paymentId),
              ));
        }

        // 2. 利息支出交易（支出：从目标账户扣款）
        if (interestAmount > 0) {
          await db.into(db.transactions).insert(TransactionsCompanion.insert(
                ledgerId: ledgerId,
                type: 'expense',
                amount: interestAmount,
                accountId: d.Value(accountId),
                happenedAt: d.Value(happenedAt),
                note: d.Value('支付给 ${payable.payeeName} 的借款利息${note != null ? ": $note" : ""}'),
                excludeFromStats: const d.Value(true),
                payableId: d.Value(payableId),
                payablePaymentId: d.Value(paymentId),
              ));
        }
      }

      // 检查是否已全额还款
      final allPayments = await (db.select(db.payablePayments)..where((p) => p.payableId.equals(payableId))).get();
      final totalPaid = allPayments.fold<double>(0, (sum, p) => sum + p.amount);

      if (totalPaid >= payable.amount) {
        await (db.update(db.payables)..where((t) => t.id.equals(payableId))).write(PayablesCompanion(
          isPaid: const d.Value(true),
          paidDate: d.Value(happenedAt),
          updatedAt: d.Value(DateTime.now()),
        ));
      }

      return paymentId;
    });
  }

  @override
  Future<void> deletePayablePayment(int id) async {
    await db.transaction(() async {
      final payment = await (db.select(db.payablePayments)..where((p) => p.id.equals(id))).getSingle();
      final payableId = payment.payableId;

      // 删除关联的交易
      await (db.delete(db.transactions)..where((t) => t.payablePaymentId.equals(id))).go();

      await (db.delete(db.payablePayments)..where((p) => p.id.equals(id))).go();

      // 更新 payable 的状态
      final payable = await (db.select(db.payables)..where((t) => t.id.equals(payableId))).getSingle();
      final allPayments = await (db.select(db.payablePayments)..where((p) => p.payableId.equals(payableId))).get();
      final totalPaid = allPayments.fold<double>(0, (sum, p) => sum + p.amount);

      if (totalPaid < payable.amount) {
        await (db.update(db.payables)..where((t) => t.id.equals(payableId))).write(PayablesCompanion(
          isPaid: const d.Value(false),
          paidDate: const d.Value(null),
          updatedAt: d.Value(DateTime.now()),
        ));
      }
    });
  }

  @override
  Future<List<PayablePayment>> getPayablePayments(int payableId) async {
    return await (db.select(db.payablePayments)
          ..where((p) => p.payableId.equals(payableId))
          ..orderBy([(p) => d.OrderingTerm.desc(p.happenedAt)]))
        .get();
  }

  @override
  Stream<List<PayablePayment>> watchPayablePayments(int payableId) {
    return (db.select(db.payablePayments)
          ..where((p) => p.payableId.equals(payableId))
          ..orderBy([(p) => d.OrderingTerm.desc(p.happenedAt)]))
        .watch();
  }
}
