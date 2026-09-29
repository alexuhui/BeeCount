/// 支出退款：入账平账，但不计入收入。
class RefundTx {
  static const typeName = 'refund';

  static bool isRefund(String type) => type == typeName;

  static double roundMoney(double value) => (value * 100).roundToDouble() / 100.0;

  static double remaining({
    required double original,
    required double refunded,
  }) {
    final left = roundMoney(original - refunded);
    return left < 0 ? 0 : left;
  }
}
