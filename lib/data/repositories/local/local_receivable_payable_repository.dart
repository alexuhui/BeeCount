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
    required int fromAccountId,
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
            fromAccountId: fromAccountId,
            note: d.Value(note),
            isReceived: d.Value(isReceived),
            receiveDate: d.Value(receiveDate),
            toAccountId: d.Value(toAccountId),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
          ));

      // 获取当前账本ID（从账户中获取）
      final fromAccount = await (db.select(db.accounts)..where((a) => a.id.equals(fromAccountId))).getSingle();
      final ledgerId = fromAccount.ledgerId;

      // 创建关联的“隐藏”交易：从借出账户转账到应收款账户
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

      // 如果创建时就是已收状态，则再创建一笔还款交易
      if (isReceived && toAccountId != null) {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: 'transfer',
              amount: amount,
              accountId: d.Value(accountId),
              toAccountId: d.Value(toAccountId),
              happenedAt: d.Value(receiveDate ?? now),
              note: d.Value('收回 $borrowerName 的借款'),
              excludeFromStats: const d.Value(true),
              receivableId: d.Value(id),
            ));
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

      // 获取原有的关联交易
      final oldTransactions = await (db.select(db.transactions)..where((t) => t.receivableId.equals(id))).get();

      // 如果金额、日期或账户发生变化，或者备注变化，简单起见我们重新生成交易
      // 但如果只是标记为已收，我们只添加新交易

      final isAmountChanged = amount != null && amount != receivable.amount;
      final isBorrowDateChanged = borrowDate != null && borrowDate != receivable.borrowDate;
      final isFromAccountChanged = fromAccountId != null && fromAccountId != receivable.fromAccountId;
      final isStatusChanged = isReceived != null && isReceived != receivable.isReceived;

      // 更新应收款记录
      await (db.update(db.receivables)..where((t) => t.id.equals(id))).write(
        ReceivablesCompanion(
          borrowerName: borrowerName != null ? d.Value(borrowerName) : d.Value.absent(),
          amount: amount != null ? d.Value(amount) : d.Value.absent(),
          borrowDate: borrowDate != null ? d.Value(borrowDate) : d.Value.absent(),
          note: note != null ? d.Value(note) : d.Value.absent(),
          fromAccountId: fromAccountId != null ? d.Value(fromAccountId) : d.Value.absent(),
          isReceived: isReceived != null ? d.Value(isReceived) : d.Value.absent(),
          receiveDate: receiveDate != null ? d.Value(receiveDate) : d.Value.absent(),
          toAccountId: toAccountId != null ? d.Value(toAccountId) : d.Value.absent(),
          updatedAt: d.Value(updatedAt ?? DateTime.now()),
        ),
      );

      final currentReceivable = await (db.select(db.receivables)..where((t) => t.id.equals(id))).getSingle();

      // 重新生成借款交易（第一笔关联交易）
      if (isAmountChanged || isBorrowDateChanged || isFromAccountChanged || borrowerName != null || note != null) {
        final borrowTx = oldTransactions.isEmpty ? null : oldTransactions.first;
        final fromAccId = fromAccountId ?? receivable.fromAccountId;
        final fromAccount = await (db.select(db.accounts)..where((a) => a.id.equals(fromAccId))).getSingle();

        if (borrowTx != null) {
          await (db.update(db.transactions)..where((t) => t.id.equals(borrowTx.id))).write(
            TransactionsCompanion(
              amount: d.Value(amount ?? receivable.amount),
              happenedAt: d.Value(borrowDate ?? receivable.borrowDate),
              accountId: d.Value(fromAccId),
              toAccountId: d.Value(receivable.accountId),
              note: d.Value('借出给 ${borrowerName ?? receivable.borrowerName}${note != null ? ": $note" : (receivable.note != null ? ": ${receivable.note}" : "")}'),
            ),
          );
        }
      }

      // 处理还款交易
      if (isStatusChanged) {
        if (currentReceivable.isReceived) {
          // 变为已收：创建还款交易
          final toAccId = toAccountId ?? currentReceivable.toAccountId;
          if (toAccId != null) {
            final fromAccount = await (db.select(db.accounts)..where((a) => a.id.equals(currentReceivable.fromAccountId))).getSingle();
            await db.into(db.transactions).insert(TransactionsCompanion.insert(
                  ledgerId: fromAccount.ledgerId,
                  type: 'transfer',
                  amount: currentReceivable.amount,
                  accountId: d.Value(currentReceivable.accountId),
                  toAccountId: d.Value(toAccId),
                  happenedAt: d.Value(receiveDate ?? currentReceivable.receiveDate ?? DateTime.now()),
                  note: d.Value('收回 ${currentReceivable.borrowerName} 的借款'),
                  excludeFromStats: const d.Value(true),
                  receivableId: d.Value(id),
                ));
          }
        } else {
          // 变为未收：删除已有的还款交易（通常是第二笔关联交易）
          if (oldTransactions.length > 1) {
            final receiveTx = oldTransactions.last;
            await (db.delete(db.transactions)..where((t) => t.id.equals(receiveTx.id))).go();
          }
        }
      } else if (currentReceivable.isReceived && (isAmountChanged || receiveDate != null || toAccountId != null)) {
        // 已经是已收状态，更新还款交易
        if (oldTransactions.length > 1) {
          final receiveTx = oldTransactions.last;
          await (db.update(db.transactions)..where((t) => t.id.equals(receiveTx.id))).write(
            TransactionsCompanion(
              amount: d.Value(currentReceivable.amount),
              happenedAt: d.Value(currentReceivable.receiveDate ?? DateTime.now()),
              toAccountId: d.Value(currentReceivable.toAccountId ?? 0),
            ),
          );
        }
      }

      logger.info('LocalReceivablePayableRepository', '更新应收款记录及其关联交易: id=$id');
    });
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
      sum += r.amount;
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
      if (r.isReceived) {
        received += r.amount;
      } else {
        pending += r.amount;
      }
    }
    
    return (pending: pending, total: total, received: received);
  }

  // ========== 应付款相关 ==========

  @override
  Future<int> createPayable({
    required int accountId,
    required String payeeName,
    required double amount,
    required DateTime payDate,
    String? note,
    required int toAccountId,
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
            toAccountId: toAccountId,
            note: d.Value(note),
            isPaid: d.Value(isPaid),
            paidDate: d.Value(paidDate),
            fromAccountId: d.Value(fromAccountId),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
          ));

      // 获取当前账本ID
      final toAccount = await (db.select(db.accounts)..where((a) => a.id.equals(toAccountId))).getSingle();
      final ledgerId = toAccount.ledgerId;

      // 创建关联的“隐藏”交易：从应付款账户转账到入账账户
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

      // 如果创建时就是已还状态
      if (isPaid && fromAccountId != null) {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: 'transfer',
              amount: amount,
              accountId: d.Value(fromAccountId),
              toAccountId: d.Value(accountId),
              happenedAt: d.Value(paidDate ?? now),
              note: d.Value('偿还 $payeeName 的借款'),
              excludeFromStats: const d.Value(true),
              payableId: d.Value(id),
            ));
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

      final oldTransactions = await (db.select(db.transactions)..where((t) => t.payableId.equals(id))).get();

      final isAmountChanged = amount != null && amount != payable.amount;
      final isPayDateChanged = payDate != null && payDate != payable.payDate;
      final isToAccountChanged = toAccountId != null && toAccountId != payable.toAccountId;
      final isStatusChanged = isPaid != null && isPaid != payable.isPaid;

      await (db.update(db.payables)..where((t) => t.id.equals(id))).write(
        PayablesCompanion(
          payeeName: payeeName != null ? d.Value(payeeName) : d.Value.absent(),
          amount: amount != null ? d.Value(amount) : d.Value.absent(),
          payDate: payDate != null ? d.Value(payDate) : d.Value.absent(),
          note: note != null ? d.Value(note) : d.Value.absent(),
          toAccountId: toAccountId != null ? d.Value(toAccountId) : d.Value.absent(),
          isPaid: isPaid != null ? d.Value(isPaid) : d.Value.absent(),
          paidDate: paidDate != null ? d.Value(paidDate) : d.Value.absent(),
          fromAccountId: fromAccountId != null ? d.Value(fromAccountId) : d.Value.absent(),
          updatedAt: d.Value(updatedAt ?? DateTime.now()),
        ),
      );

      final currentPayable = await (db.select(db.payables)..where((t) => t.id.equals(id))).getSingle();

      // 更新借入交易
      if (isAmountChanged || isPayDateChanged || isToAccountChanged || payeeName != null || note != null) {
        final borrowTx = oldTransactions.isEmpty ? null : oldTransactions.first;
        final toAccId = toAccountId ?? payable.toAccountId;

        if (borrowTx != null) {
          await (db.update(db.transactions)..where((t) => t.id.equals(borrowTx.id))).write(
            TransactionsCompanion(
              amount: d.Value(amount ?? payable.amount),
              happenedAt: d.Value(payDate ?? payable.payDate),
              accountId: d.Value(payable.accountId),
              toAccountId: d.Value(toAccId),
              note: d.Value('向 ${payeeName ?? payable.payeeName} 借入${note != null ? ": $note" : (payable.note != null ? ": ${payable.note}" : "")}'),
            ),
          );
        }
      }

      // 处理还款交易
      if (isStatusChanged) {
        if (currentPayable.isPaid) {
          final fromAccId = fromAccountId ?? currentPayable.fromAccountId;
          if (fromAccId != null) {
            final toAccount = await (db.select(db.accounts)..where((a) => a.id.equals(currentPayable.toAccountId))).getSingle();
            await db.into(db.transactions).insert(TransactionsCompanion.insert(
                  ledgerId: toAccount.ledgerId,
                  type: 'transfer',
                  amount: currentPayable.amount,
                  accountId: d.Value(fromAccId),
                  toAccountId: d.Value(currentPayable.accountId),
                  happenedAt: d.Value(paidDate ?? currentPayable.paidDate ?? DateTime.now()),
                  note: d.Value('偿还 ${currentPayable.payeeName} 的借款'),
                  excludeFromStats: const d.Value(true),
                  payableId: d.Value(id),
                ));
          }
        } else {
          if (oldTransactions.length > 1) {
            final paidTx = oldTransactions.last;
            await (db.delete(db.transactions)..where((t) => t.id.equals(paidTx.id))).go();
          }
        }
      } else if (currentPayable.isPaid && (isAmountChanged || paidDate != null || fromAccountId != null)) {
        if (oldTransactions.length > 1) {
          final paidTx = oldTransactions.last;
          await (db.update(db.transactions)..where((t) => t.id.equals(paidTx.id))).write(
            TransactionsCompanion(
              amount: d.Value(currentPayable.amount),
              happenedAt: d.Value(currentPayable.paidDate ?? DateTime.now()),
              accountId: d.Value(currentPayable.fromAccountId ?? 0),
            ),
          );
        }
      }

      logger.info('LocalReceivablePayableRepository', '更新应付款记录及其关联交易: id=$id');
    });
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
      sum += p.amount;
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
      if (p.isPaid) {
        paid += p.amount;
      } else {
        pending += p.amount;
      }
    }
    
    return (pending: pending, total: total, paid: paid);
  }
}
