import '../data/repositories/budget_repository.dart';

/// Client-side budget overview from budgets + categories + per-category expense.
class BudgetOverviewCalc {
  static List<CategoryBudgetUsage> monthly({
    required Iterable<({int id, int? categoryId, double amount})> budgets,
    required Iterable<({int id, String name, String? icon, int? parentId})>
        categories,
    required Map<int, double> expenseByCategoryId,
  }) {
    final catById = {
      for (final c in categories) c.id: c,
    };
    final budgetMap = <int, ({int id, int? categoryId, double amount})>{};
    for (final b in budgets) {
      final categoryId = b.categoryId;
      if (categoryId == null) continue;
      budgetMap[categoryId] = b;
    }

    final categoryUsed = _rollUpExpenses(catById, expenseByCategoryId);
    final result = <CategoryBudgetUsage>[];

    for (final used in categoryUsed.entries) {
      final categoryId = used.key;
      final budget = budgetMap.remove(categoryId);
      final category = catById[categoryId];
      if (category == null) continue;
      result.add(CategoryBudgetUsage(
        budgetId: budget?.id ?? 0,
        categoryId: categoryId,
        categoryName: category.name,
        categoryIcon: category.icon,
        usage: BudgetUsage(used: used.value, budget: budget?.amount ?? 0),
      ));
    }

    for (final budget in budgetMap.values) {
      final categoryId = budget.categoryId;
      if (categoryId == null) continue;
      final category = catById[categoryId];
      if (category == null) continue;
      result.add(CategoryBudgetUsage(
        budgetId: budget.id,
        categoryId: categoryId,
        categoryName: category.name,
        categoryIcon: category.icon,
        usage: BudgetUsage(used: 0, budget: budget.amount),
      ));
    }

    result.sort((a, b) => b.usage.rate.compareTo(a.usage.rate));
    return result;
  }

  static List<CategoryBudgetUsage> yearly({
    required Iterable<({int id, int? categoryId, double amount})> budgets,
    required Iterable<({int id, String name, String? icon, int? parentId})>
        categories,
    required Map<int, double> expenseByCategoryId,
  }) {
    final catById = {
      for (final c in categories) c.id: c,
    };
    final budgetMap = <int, double>{};
    for (final b in budgets) {
      final categoryId = b.categoryId;
      if (categoryId == null) continue;
      budgetMap[categoryId] = (budgetMap[categoryId] ?? 0) + b.amount;
    }

    final categoryUsed = _rollUpExpenses(catById, expenseByCategoryId);
    final result = <CategoryBudgetUsage>[];

    for (final used in categoryUsed.entries) {
      final categoryId = used.key;
      final budgetAmount = budgetMap.remove(categoryId) ?? 0;
      final category = catById[categoryId];
      if (category == null) continue;
      result.add(CategoryBudgetUsage(
        budgetId: 0,
        categoryId: categoryId,
        categoryName: category.name,
        categoryIcon: category.icon,
        usage: BudgetUsage(used: used.value, budget: budgetAmount),
      ));
    }

    for (final entry in budgetMap.entries) {
      final category = catById[entry.key];
      if (category == null) continue;
      result.add(CategoryBudgetUsage(
        budgetId: 0,
        categoryId: entry.key,
        categoryName: category.name,
        categoryIcon: category.icon,
        usage: BudgetUsage(used: 0, budget: entry.value),
      ));
    }

    result.sort((a, b) => b.usage.rate.compareTo(a.usage.rate));
    return result;
  }

  static BudgetOverview overview({
    required List<CategoryBudgetUsage> categoryUsages,
    required int year,
    required int month,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    BudgetUsage totalUsage;
    if (categoryUsages.isNotEmpty) {
      var totalUsed = 0.0;
      var totalBudget = 0.0;
      for (final usage in categoryUsages) {
        totalUsed += usage.usage.used;
        totalBudget += usage.usage.budget;
      }
      totalUsage = BudgetUsage(used: totalUsed, budget: totalBudget);
    } else {
      totalUsage = BudgetUsage(used: 0, budget: 0);
    }

    final DateTime startDate;
    final DateTime endDate;
    if (month == 0) {
      startDate = clock.year == year ? clock : DateTime(year, 1, 1);
      endDate = DateTime(year + 1);
    } else {
      startDate = clock.year == year && clock.month == month
          ? clock
          : DateTime(year, month, 1);
      endDate = DateTime(year, month + 1);
    }
    final daysRemaining = endDate.difference(startDate).inDays;
    final remaining = totalUsage.remaining;
    final dailyAvailable =
        daysRemaining > 0 ? remaining / daysRemaining : 0.0;

    return BudgetOverview(
      totalBudget: totalUsage,
      categoryBudgets: categoryUsages,
      daysRemaining: daysRemaining > 0 ? daysRemaining : 0,
      dailyAvailable: dailyAvailable > 0 ? dailyAvailable : 0,
      year: year,
      month: month,
    );
  }

  static double usedForCategory({
    required int categoryId,
    required Iterable<({int id, int? parentId})> categories,
    required Map<int, double> expenseByCategoryId,
  }) {
    final parentById = {for (final c in categories) c.id: c.parentId};
    var used = 0.0;
    for (final e in expenseByCategoryId.entries) {
      if (e.key == categoryId) {
        used += e.value;
        continue;
      }
      final parent = parentById[e.key];
      if (parent != null && parent == categoryId) {
        used += e.value;
      }
    }
    return used;
  }

  static Map<int, double> _rollUpExpenses(
    Map<int, ({int id, String name, String? icon, int? parentId})> catById,
    Map<int, double> expenseByCategoryId,
  ) {
    final categoryUsed = <int, double>{};
    for (final e in expenseByCategoryId.entries) {
      final category = catById[e.key];
      if (category == null) continue;
      final parentId = category.parentId;
      final useId = parentId != null && parentId > 0 ? parentId : e.key;
      categoryUsed[useId] = (categoryUsed[useId] ?? 0) + e.value;
    }
    return categoryUsed;
  }
}
