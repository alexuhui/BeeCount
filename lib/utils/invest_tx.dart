import 'package:drift/drift.dart';

import '../data/db.dart';

/// 理财账户与盈亏流水常量。
class InvestTx {
  static const accountType = 'investment';
  static const gain = 'invest_gain';
  static const loss = 'invest_loss';
  static const eventMarkToMarket = 'mark_to_market';
  static const eventManual = 'manual';
  static const eventDividend = 'dividend';

  static const pnlTypes = [gain, loss];

  static bool isPnlType(String type) => type == gain || type == loss;

  static bool isInvestmentAccount(String type) => type == accountType;

  /// 首页/日历等日常流水可见条件：不排除统计，且不是理财盈亏。
  static Expression<bool> dailyVisible(Transactions t) =>
      t.excludeFromStats.equals(false) & t.type.isNotIn(pnlTypes);

  static double applyToBalance({
    required double balance,
    required String type,
    required double amount,
    required int accountId,
    int? txAccountId,
    int? txToAccountId,
  }) {
    if (txAccountId == accountId) {
      switch (type) {
        case 'income':
        case gain:
          return balance + amount;
        case 'expense':
        case loss:
        case 'transfer':
          return balance - amount;
      }
    } else if (txToAccountId == accountId && type == 'transfer') {
      return balance + amount;
    }
    return balance;
  }
}

class InvestmentPeriodStats {
  final double openingValue;
  final double closingValue;
  final double netTransferIn;
  final double periodPnl;
  final double totalPnl;
  final double periodGain;
  final double periodLoss;

  const InvestmentPeriodStats({
    required this.openingValue,
    required this.closingValue,
    required this.netTransferIn,
    required this.periodPnl,
    required this.totalPnl,
    required this.periodGain,
    required this.periodLoss,
  });
}
