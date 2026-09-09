import 'package:beecount/utils/budget_overview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ({int id, String name, String? icon, int? parentId}) cat(
    int id,
    String name, {
    int? parentId,
  }) =>
      (id: id, name: name, icon: null, parentId: parentId);

  ({int id, int? categoryId, double amount}) budget(
    int id,
    int categoryId,
    double amount,
  ) =>
      (id: id, categoryId: categoryId, amount: amount);

  test('budget with no spending still appears when category exists', () {
    final usages = BudgetOverviewCalc.monthly(
      budgets: [budget(1, 10, 500)],
      categories: [cat(10, 'Food')],
      expenseByCategoryId: const {},
    );
    expect(usages, hasLength(1));
    expect(usages.first.categoryName, 'Food');
    expect(usages.first.usage.budget, 500);
    expect(usages.first.usage.used, 0);
  });

  test('budget is omitted when category is missing', () {
    final usages = BudgetOverviewCalc.monthly(
      budgets: [budget(1, 10, 500)],
      categories: const [],
      expenseByCategoryId: const {10: 20},
    );
    expect(usages, isEmpty);
  });

  test('child expenses roll up to parent category', () {
    final usages = BudgetOverviewCalc.monthly(
      budgets: [budget(1, 10, 800)],
      categories: [
        cat(10, 'Food'),
        cat(11, 'Lunch', parentId: 10),
      ],
      expenseByCategoryId: const {11: 120},
    );
    expect(usages, hasLength(1));
    expect(usages.first.categoryId, 10);
    expect(usages.first.usage.used, 120);
    expect(usages.first.usage.budget, 800);
  });

  test('yearly overview sums monthly budgets for the same category', () {
    final usages = BudgetOverviewCalc.yearly(
      budgets: [
        budget(1, 10, 100),
        budget(2, 10, 150),
      ],
      categories: [cat(10, 'Food')],
      expenseByCategoryId: const {10: 40},
    );
    expect(usages, hasLength(1));
    expect(usages.first.usage.budget, 250);
    expect(usages.first.usage.used, 40);
  });

  test('overview total is the sum of category budgets', () {
    final usages = BudgetOverviewCalc.monthly(
      budgets: [budget(1, 10, 500), budget(2, 20, 200)],
      categories: [cat(10, 'Food'), cat(20, 'Traffic')],
      expenseByCategoryId: const {10: 50},
    );
    final overview = BudgetOverviewCalc.overview(
      categoryUsages: usages,
      year: 2026,
      month: 9,
      now: DateTime(2026, 9, 1),
    );
    expect(overview.totalBudget?.budget, 700);
    expect(overview.totalBudget?.used, 50);
    expect(overview.categoryBudgets, hasLength(2));
  });
}
