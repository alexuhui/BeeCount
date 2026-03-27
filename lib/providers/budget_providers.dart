import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/repositories/budget_repository.dart';
import '../providers.dart';

/// 预算刷新触发器
final budgetRefreshProvider = StateProvider<int>((ref) => 0);

/// 预算视图模式：月度/年度
final budgetViewModeProvider = StateProvider<bool>((ref) => false); // false=月度, true=年度

/// 当前账本的总预算
final totalBudgetProvider = FutureProvider<Budget?>((ref) async {
  ref.watch(budgetRefreshProvider);

  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  return repo.getTotalBudget(ledgerId);
});

/// 当前账本的所有预算
final allBudgetsProvider = FutureProvider<List<Budget>>((ref) async {
  ref.watch(budgetRefreshProvider);

  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  return repo.getAllBudgets(ledgerId);
});

/// 当前账本的预算概览
final budgetOverviewProvider = FutureProvider<BudgetOverview?>((ref) async {
  ref.watch(budgetRefreshProvider);

  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);
  final now = DateTime.now();

  return repo.getBudgetOverview(ledgerId, now);
});

/// 当前管理的预算年月刷新触发器
final selectedBudgetYearMonthProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// 当前账本的指定年月的预算概览
final budgetOverviewForYearMonthProvider = FutureProvider<BudgetOverview?>((ref) async {
  final dateTime = ref.watch(selectedBudgetYearMonthProvider);
  final isYearly = ref.watch(budgetViewModeProvider);
  ref.watch(budgetRefreshProvider);

  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  if (isYearly) {
    return repo.getYearlyBudgetOverview(ledgerId, dateTime.year);
  } else {
    return repo.getBudgetOverview(ledgerId, dateTime);
  }
});

/// 分类预算列表
final categoryBudgetsProvider = FutureProvider<List<CategoryBudgetUsage>>((ref) async {
  ref.watch(budgetRefreshProvider);

  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);
  final now = DateTime.now();

  return repo.getCategoryBudgetUsages(ledgerId, now);
});

/// 监听预算变化
final budgetsStreamProvider = StreamProvider<List<Budget>>((ref) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  return repo.watchBudgets(ledgerId);
});

/// 指定分类的预算使用情况
final categoryBudgetUsageProvider = FutureProvider.family<CategoryBudgetUsage?, int>((ref, categoryId) async {
  ref.watch(budgetRefreshProvider);

  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  final budget = await repo.getBudgetByCategory(ledgerId, categoryId);
  if (budget == null) return null;

  final now = DateTime.now();
  final usage = await repo.getBudgetUsage(budget.id, now);

  // 获取分类信息
  final categories = await repo.getAllCategories();
  final category = categories.where((c) => c.id == categoryId).firstOrNull;
  if (category == null) return null;

  return CategoryBudgetUsage(
    budgetId: budget.id,
    categoryId: categoryId,
    categoryName: category.name,
    categoryIcon: category.icon,
    usage: usage,
  );
});
