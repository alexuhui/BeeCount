/// 支出退款：入账平账，但不计入收入。
class RefundTx {
  static const typeName = 'refund';

  static bool isRefund(String type) => type == typeName;

  static bool isLinkedCredit(String type) =>
      isRefund(type) || ReimburseTx.isReimburse(type);

  /// 单行支出统计。关联退款/报销本身不产生负支出。
  /// 净支出必须结合原支出和全部关联记录计算。
  static double expenseDelta(String type, double amount) {
    if (type == 'expense') return amount;
    return 0;
  }

  static double roundMoney(double value) =>
      (value * 100).roundToDouble() / 100.0;

  static double netExpense({
    required double original,
    required double linkedCredits,
  }) {
    final net = roundMoney(original - linkedCredits);
    return net > 0 ? net : 0;
  }

  static double remaining({
    required double original,
    required double refunded,
  }) {
    return netExpense(original: original, linkedCredits: refunded);
  }
}

/// 支出报销：入账，但不计入收入。金额可以高于原支出。
class ReimburseTx {
  static const typeName = 'reimburse';

  static bool isReimburse(String type) => type == typeName;
}
