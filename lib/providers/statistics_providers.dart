import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_providers.dart';
import 'ui_state_providers.dart';
import '../services/system/logger_service.dart';
import '../utils/invest_tx.dart';

// 统计：账本数量
final ledgerCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖全局统计刷新 tick，确保手动刷新或恢复后能重新计算
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.ledgerCount();
});

// 统计：某账本的记账天数与总笔数
final countsForLedgerProvider = FutureProvider.family
    .autoDispose<({int dayCount, int txCount}), int>((ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getCountsForLedger(ledgerId: ledgerId);
});

// 统计刷新 tick（全局）：每次 +1 触发统计相关 Provider 重新获取
final statsRefreshProvider = StateProvider<int>((ref) => 0);

// 统计：全应用的记账天数与总笔数（跨账本聚合）
final lastCountsAllProvider =
    StateProvider<({int dayCount, int txCount})?>((ref) => null);

final countsAllProvider =
    FutureProvider.autoDispose<({int dayCount, int txCount})>((ref) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发手动刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  final res = await repo.getCountsAll();
  // 写入最近一次成功值，供 UI 在刷新期间显示旧值
  ref.read(lastCountsAllProvider.notifier).state = res;
  return res;
});

// 统计：当前账本总余额
final currentBalanceProvider =
    FutureProvider.family.autoDispose<double, int>((ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());

  // 获取账户功能开启状态
  final accountFeatureEnabled = await ref.watch(accountFeatureEnabledProvider.future);

  final stats = await repo.getLedgerStats(
    ledgerId: ledgerId,
    accountFeatureEnabled: accountFeatureEnabled,
  );
  return stats.balance;
});

// 统计：月度汇总最近值（避免loading闪烁）
final lastMonthlyTotalsProvider = StateProvider.family<(double income, double expense)?, ({int ledgerId, DateTime month})>((ref, params) => null);

// 统计：月度汇总（收入、支出）
final monthlyTotalsProvider = FutureProvider.family
    .autoDispose<(double income, double expense), ({int ledgerId, DateTime month})>(
        (ref, params) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  final res = await repo.monthlyTotals(ledgerId: params.ledgerId, month: params.month);
  // 写入最近一次成功值，供 UI 在刷新期间显示旧值
  ref.read(lastMonthlyTotalsProvider(params).notifier).state = res;
  return res;
});

// 统计：单个账户统计（余额、消费、收入）
final accountStatsProvider = FutureProvider.family
    .autoDispose<({double balance, double expense, double income}), int>(
        (ref, accountId) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getAccountStats(accountId);
});

// 统计：所有账户统计（每个账户的余额、消费、收入）
// v1.15.0: 不再限制账本，获取所有账户
final allAccountStatsProvider = FutureProvider.autoDispose<Map<int, ({double balance, double expense, double income})>>(
        (ref) async {
  final repo = ref.watch(repositoryProvider);
  logger.info('AllAccountStats', '使用的 Repository 类型: ${repo.runtimeType}');
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  final stats = await repo.getAllAccountStats();
  logger.info('AllAccountStats', '获取到 ${stats.length} 个账户的统计数据');
  return stats;
});

// 统计：所有账户汇总统计（总余额、总支出、总收入）
// v1.15.0: 不再限制账本，获取所有账户
final allAccountsTotalStatsProvider = FutureProvider.autoDispose<({double totalBalance, double totalExpense, double totalIncome})>(
        (ref) async {
  final repo = ref.watch(repositoryProvider);
  logger.info('AllAccountsTotalStats', '使用的 Repository 类型: ${repo.runtimeType}');
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  final stats = await repo.getAllAccountsTotalStats();
  logger.info('AllAccountsTotalStats', '总余额: ${stats.totalBalance}, 总支出: ${stats.totalExpense}, 总收入: ${stats.totalIncome}');
  return stats;
});

final investmentPeriodStatsProvider = FutureProvider.family.autoDispose<
    InvestmentPeriodStats,
    ({int accountId, DateTime from, DateTime to})>((ref, args) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getInvestmentPeriodStats(
    accountId: args.accountId,
    from: args.from,
    to: args.to,
  );
});

final investmentAccountsSummaryProvider =
    FutureProvider.autoDispose<({double marketValue, double totalPnl})>(
        (ref) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  final accounts = await repo.getAllAccounts();
  final invest = accounts.where((a) => InvestTx.isInvestmentAccount(a.type));
  var marketValue = 0.0;
  var totalPnl = 0.0;
  final from = DateTime(1970, 1, 1);
  final to = DateTime.now().add(const Duration(days: 1));
  for (final a in invest) {
    final stats = await repo.getInvestmentPeriodStats(
      accountId: a.id,
      from: from,
      to: to,
    );
    marketValue += stats.closingValue;
    totalPnl += stats.totalPnl;
  }
  return (marketValue: marketValue, totalPnl: totalPnl);
});