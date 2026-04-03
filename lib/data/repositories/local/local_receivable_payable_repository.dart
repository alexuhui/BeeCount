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
    final now = DateTime.now();
    final id = await db.into(db.receivables).insert(ReceivablesCompanion.insert(
      accountId: accountId,
      borrowerName: borrowerName,
      amount: amount,
      borrowDate: borrowDate,
      fromAccountId: d.Value(fromAccountId),
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
          ..where((t) => t.accountId.equals(accountId)))
        .get();
    
    double sum = 0.0;
    for (final r in receivables) {
      // 获取该应收款的已付款金额
      final paidAmount = await getReceivablePaidAmount(r.id);
      // 未收金额 = 总金额 - 已付款金额
      final pendingAmount = r.amount - paidAmount;
      if (pendingAmount > 0) {
        sum += pendingAmount;
      }
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
      // 获取该应收款的已付款金额
      final paidAmount = await getReceivablePaidAmount(r.id);
      received += paidAmount;
      final pendingAmount = r.amount - paidAmount;
      if (pendingAmount > 0) {
        pending += pendingAmount;
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
    int? toAccountId,
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
      toAccountId: d.Value(toAccountId),
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
          ..where((t) => t.accountId.equals(accountId)))
        .get();
    
    double sum = 0.0;
    for (final p in payables) {
      // 获取该应付款的已付款金额
      final paidAmount = await getPayablePaidAmount(p.id);
      // 未付金额 = 总金额 - 已付款金额
      final pendingAmount = p.amount - paidAmount;
      if (pendingAmount > 0) {
        sum += pendingAmount;
      }
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
      // 获取该应付款的已付款金额
      final paidAmount = await getPayablePaidAmount(p.id);
      paid += paidAmount;
      final pendingAmount = p.amount - paidAmount;
      if (pendingAmount > 0) {
        pending += pendingAmount;
      }
    }
    
    return (pending: pending, total: total, paid: paid);
  }

  // ========== 应收款分批付款相关 ==========

  @override
  Future<int> createReceivablePayment({
    required int receivableId,
    required double amount,
    required DateTime paymentDate,
    int? accountId,
    String? note,
  }) async {
    final now = DateTime.now();
    final id = await db.into(db.receivablePayments).insert(ReceivablePaymentsCompanion.insert(
      receivableId: receivableId,
      amount: amount,
      paymentDate: paymentDate,
      accountId: d.Value(accountId),
      note: d.Value(note),
      createdAt: d.Value(now),
      updatedAt: d.Value(now),
    ));
    
    logger.info('LocalReceivablePayableRepository', '创建应收款付款记录: id=$id, receivableId=$receivableId, amount=$amount');
    
    // 检查是否已全部付款
    final paidAmount = await getReceivablePaidAmount(receivableId);
    final receivable = await getReceivableById(receivableId);
    if (receivable != null && paidAmount >= receivable.amount) {
      await updateReceivable(
        id: receivableId,
        isReceived: true,
        receiveDate: paymentDate,
        toAccountId: accountId,
      );
    }
    
    return id;
  }

  @override
  Future<void> updateReceivablePayment({
    required int id,
    double? amount,
    DateTime? paymentDate,
    int? accountId,
    String? note,
  }) async {
    final payment = await (db.select(db.receivablePayments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (payment == null) {
      throw Exception('应收款付款记录不存在: $id');
    }

    await (db.update(db.receivablePayments)..where((t) => t.id.equals(id))).write(
      ReceivablePaymentsCompanion(
        amount: amount != null ? d.Value(amount) : d.Value.absent(),
        paymentDate: paymentDate != null ? d.Value(paymentDate) : d.Value.absent(),
        accountId: accountId != null ? d.Value(accountId) : d.Value.absent(),
        note: note != null ? d.Value(note) : d.Value.absent(),
        updatedAt: d.Value(DateTime.now()),
      ),
    );

    logger.info('LocalReceivablePayableRepository', '更新应收款付款记录: id=$id');

    // 重新检查是否已全部付款
    final paidAmount = await getReceivablePaidAmount(payment.receivableId);
    final receivable = await getReceivableById(payment.receivableId);
    if (receivable != null) {
      if (paidAmount >= receivable.amount) {
        await updateReceivable(
          id: payment.receivableId,
          isReceived: true,
          receiveDate: paymentDate ?? payment.paymentDate,
          toAccountId: accountId ?? payment.accountId,
        );
      } else {
        await updateReceivable(
          id: payment.receivableId,
          isReceived: false,
          receiveDate: null,
          toAccountId: null,
        );
      }
    }
  }

  @override
  Future<void> deleteReceivablePayment(int id) async {
    final payment = await (db.select(db.receivablePayments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (payment == null) {
      throw Exception('应收款付款记录不存在: $id');
    }

    await (db.delete(db.receivablePayments)..where((t) => t.id.equals(id))).go();
    logger.info('LocalReceivablePayableRepository', '删除应收款付款记录: id=$id');

    // 重新检查是否已全部付款
    final paidAmount = await getReceivablePaidAmount(payment.receivableId);
    final receivable = await getReceivableById(payment.receivableId);
    if (receivable != null) {
      if (paidAmount >= receivable.amount) {
        await updateReceivable(
          id: payment.receivableId,
          isReceived: true,
          receiveDate: payment.paymentDate,
          toAccountId: payment.accountId,
        );
      } else {
        await updateReceivable(
          id: payment.receivableId,
          isReceived: false,
          receiveDate: null,
          toAccountId: null,
        );
      }
    }
  }

  @override
  Future<List<ReceivablePayment>> getReceivablePayments(int receivableId) async {
    return await (db.select(db.receivablePayments)
          ..where((t) => t.receivableId.equals(receivableId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.paymentDate)]))
        .get();
  }

  @override
  Stream<List<ReceivablePayment>> watchReceivablePayments(int receivableId) {
    return (db.select(db.receivablePayments)
          ..where((t) => t.receivableId.equals(receivableId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.paymentDate)]))
        .watch();
  }

  @override
  Future<double> getReceivablePaidAmount(int receivableId) async {
    final payments = await (db.select(db.receivablePayments)
          ..where((t) => t.receivableId.equals(receivableId)))
        .get();
    
    double sum = 0.0;
    for (final p in payments) {
      sum += p.amount;
    }
    return sum;
  }

  // ========== 应付款分批付款相关 ==========

  @override
  Future<int> createPayablePayment({
    required int payableId,
    required double amount,
    required DateTime paymentDate,
    int? accountId,
    String? note,
  }) async {
    final now = DateTime.now();
    final id = await db.into(db.payablePayments).insert(PayablePaymentsCompanion.insert(
      payableId: payableId,
      amount: amount,
      paymentDate: paymentDate,
      accountId: d.Value(accountId),
      note: d.Value(note),
      createdAt: d.Value(now),
      updatedAt: d.Value(now),
    ));
    
    logger.info('LocalReceivablePayableRepository', '创建应付款付款记录: id=$id, payableId=$payableId, amount=$amount');
    
    // 检查是否已全部付款
    final paidAmount = await getPayablePaidAmount(payableId);
    final payable = await getPayableById(payableId);
    if (payable != null && paidAmount >= payable.amount) {
      await updatePayable(
        id: payableId,
        isPaid: true,
        paidDate: paymentDate,
        fromAccountId: accountId,
      );
    }
    
    return id;
  }

  @override
  Future<void> updatePayablePayment({
    required int id,
    double? amount,
    DateTime? paymentDate,
    int? accountId,
    String? note,
  }) async {
    final payment = await (db.select(db.payablePayments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (payment == null) {
      throw Exception('应付款付款记录不存在: $id');
    }

    await (db.update(db.payablePayments)..where((t) => t.id.equals(id))).write(
      PayablePaymentsCompanion(
        amount: amount != null ? d.Value(amount) : d.Value.absent(),
        paymentDate: paymentDate != null ? d.Value(paymentDate) : d.Value.absent(),
        accountId: accountId != null ? d.Value(accountId) : d.Value.absent(),
        note: note != null ? d.Value(note) : d.Value.absent(),
        updatedAt: d.Value(DateTime.now()),
      ),
    );

    logger.info('LocalReceivablePayableRepository', '更新应付款付款记录: id=$id');

    // 重新检查是否已全部付款
    final paidAmount = await getPayablePaidAmount(payment.payableId);
    final payable = await getPayableById(payment.payableId);
    if (payable != null) {
      if (paidAmount >= payable.amount) {
        await updatePayable(
          id: payment.payableId,
          isPaid: true,
          paidDate: paymentDate ?? payment.paymentDate,
          fromAccountId: accountId ?? payment.accountId,
        );
      } else {
        await updatePayable(
          id: payment.payableId,
          isPaid: false,
          paidDate: null,
          fromAccountId: null,
        );
      }
    }
  }

  @override
  Future<void> deletePayablePayment(int id) async {
    final payment = await (db.select(db.payablePayments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (payment == null) {
      throw Exception('应付款付款记录不存在: $id');
    }

    await (db.delete(db.payablePayments)..where((t) => t.id.equals(id))).go();
    logger.info('LocalReceivablePayableRepository', '删除应付款付款记录: id=$id');

    // 重新检查是否已全部付款
    final paidAmount = await getPayablePaidAmount(payment.payableId);
    final payable = await getPayableById(payment.payableId);
    if (payable != null) {
      if (paidAmount >= payable.amount) {
        await updatePayable(
          id: payment.payableId,
          isPaid: true,
          paidDate: payment.paymentDate,
          fromAccountId: payment.accountId,
        );
      } else {
        await updatePayable(
          id: payment.payableId,
          isPaid: false,
          paidDate: null,
          fromAccountId: null,
        );
      }
    }
  }

  @override
  Future<List<PayablePayment>> getPayablePayments(int payableId) async {
    return await (db.select(db.payablePayments)
          ..where((t) => t.payableId.equals(payableId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.paymentDate)]))
        .get();
  }

  @override
  Stream<List<PayablePayment>> watchPayablePayments(int payableId) {
    return (db.select(db.payablePayments)
          ..where((t) => t.payableId.equals(payableId))
          ..orderBy([(t) => d.OrderingTerm.desc(t.paymentDate)]))
        .watch();
  }

  @override
  Future<double> getPayablePaidAmount(int payableId) async {
    final payments = await (db.select(db.payablePayments)
          ..where((t) => t.payableId.equals(payableId)))
        .get();
    
    double sum = 0.0;
    for (final p in payments) {
      sum += p.amount;
    }
    return sum;
  }
}
