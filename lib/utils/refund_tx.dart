/// 支出退款：入账平账，但不计入收入。
class RefundTx {
  static const typeName = 'refund';

  static bool isRefund(String type) => type == typeName;

  static bool isLinkedCredit(String type) =>
      isRefund(type) || ReimburseTx.isReimburse(type);

  static double roundMoney(double value) => (value * 100).roundToDouble() / 100.0;

  static double remaining({
    required double original,
    required double refunded,
  }) {
    final left = roundMoney(original - refunded);
    return left < 0 ? 0 : left;
  }
}

/// 支出报销：入账，但不计入收入。金额可以高于原支出。
class ReimburseTx {
  static const typeName = 'reimburse';

  static bool isReimburse(String type) => type == typeName;
}
