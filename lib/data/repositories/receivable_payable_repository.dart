import '../db.dart';

/// 应收款和应付款 Repository 接口
abstract class ReceivablePayableRepository {
  // ========== 应收款相关 ==========
  
  /// 创建应收款记录
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
  });

  /// 更新应收款记录
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
  });

  /// 删除应收款记录
  Future<void> deleteReceivable(int id);

  /// 获取指定账户的所有应收款记录
  Future<List<Receivable>> getReceivablesByAccountId(int accountId);

  /// 监听指定账户的应收款记录
  Stream<List<Receivable>> watchReceivablesByAccountId(int accountId);

  /// 获取应收款记录详情
  Future<Receivable?> getReceivableById(int id);

  /// 获取应收款账户的余额（未收款金额）
  Future<double> getReceivableBalance(int accountId);

  /// 获取应收款账户的统计信息（待收金额、总额、已收金额）
  Future<({double pending, double total, double received})> getReceivableStats(int accountId);

  // ========== 应付款相关 ==========

  /// 创建应付款记录
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
  });

  /// 更新应付款记录
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
  });

  /// 删除应付款记录
  Future<void> deletePayable(int id);

  /// 获取指定账户的所有应付款记录
  Future<List<Payable>> getPayablesByAccountId(int accountId);

  /// 监听指定账户的应付款记录
  Stream<List<Payable>> watchPayablesByAccountId(int accountId);

  /// 获取应付款记录详情
  Future<Payable?> getPayableById(int id);

  /// 获取应付款账户的余额（未还款金额）
  Future<double> getPayableBalance(int accountId);

  /// 获取应付款账户的统计信息（待付金额、总额、已付金额）
  Future<({double pending, double total, double paid})> getPayableStats(int accountId);

  // ========== 收款/还款记录相关 ==========

  /// 添加收款记录
  Future<int> addReceivablePayment({
    required int receivableId,
    required double amount,
    double interestAmount = 0.0,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  });

  /// 删除收款记录
  Future<void> deleteReceivablePayment(int id);

  /// 获取指定应收款的所有收款记录
  Future<List<ReceivablePayment>> getReceivablePayments(int receivableId);

  /// 监听指定应收款的所有收款记录
  Stream<List<ReceivablePayment>> watchReceivablePayments(int receivableId);

  /// 添加还款记录
  Future<int> addPayablePayment({
    required int payableId,
    required double amount,
    double interestAmount = 0.0,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  });

  /// 删除还款记录
  Future<void> deletePayablePayment(int id);

  /// 获取指定应付款的所有还款记录
  Future<List<PayablePayment>> getPayablePayments(int payableId);

  /// 监听指定应付款的所有还款记录
  Stream<List<PayablePayment>> watchPayablePayments(int payableId);
}
