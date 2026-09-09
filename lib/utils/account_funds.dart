/// 可用资金：现金类 + 信用卡（带符号）− 应付未付本金。不含理财、应收、其他。
class AccountFunds {
  static const liquidTypes = {
    'cash',
    'bank_card',
    'wechat',
    'alipay',
    'credit_card',
  };

  static bool isLiquidType(String type) => liquidTypes.contains(type);

  static double available({
    required Iterable<({String type, double balance})> accounts,
    required double outstandingPayable,
  }) {
    var sum = 0.0;
    for (final account in accounts) {
      if (isLiquidType(account.type)) {
        sum += account.balance;
      }
    }
    return sum - outstandingPayable;
  }
}
