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
    
    logger.info('LocalReceivablePayableRepository', '创建应收款记录: id=$id, borrowerName=$borrowerName, amount=$amount');
    
    return id;
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
    final receivable = await (db.select(db.receivables)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (receivable == null) {
      throw Exception('应收款记录不存在: $id');
    }

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

    logger.info('LocalReceivablePayableRepository', '更新应收款记录: id=$id');
  }

  @override
  Future<void> deleteReceivable(int id) async {
    await (db.delete(db.receivables)..where((t) => t.id.equals(id))).go();
    logger.info('LocalReceivablePayableRepository', '删除应收款记录: id=$id');
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
    
    logger.info('LocalReceivablePayableRepository', '创建应付款记录: id=$id, payeeName=$payeeName, amount=$amount');
    
    return id;
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

    logger.info('LocalReceivablePayableRepository', '更新应付款记录: id=$id');
  }

  @override
  Future<void> deletePayable(int id) async {
    await (db.delete(db.payables)..where((t) => t.id.equals(id))).go();
    logger.info('LocalReceivablePayableRepository', '删除应付款记录: id=$id');
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
}
