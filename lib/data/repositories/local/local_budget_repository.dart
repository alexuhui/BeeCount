import 'package:drift/drift.dart' as d;

import '../../../services/system/logger_service.dart';
import '../../db.dart';
import '../budget_repository.dart';

/// 本地预算Repository实现
/// 基于 Drift 数据库实现
class LocalBudgetRepository implements BudgetRepository {
  final BeeDatabase db;

  LocalBudgetRepository(this.db);

  // ============================================
  // 基础 CRUD 操作
  // ============================================

  @override
  Future<int> createBudget({
    required int ledgerId,
    required int year,
    required int month,
    int? categoryId,
    required double amount,
    required bool prompt,
    int? promptDay,
    bool? ignored,
  }) async {
    return await db.into(db.budgets).insert(
      BudgetsCompanion.insert(
        ledgerId: ledgerId,
        year: year,
        month: month,
        categoryId: d.Value(categoryId),
        amount: amount,
        prompt: d.Value(prompt),
        promptDay: d.Value(promptDay),
        ignored: d.Value(ignored),
      ),
    );
  }

  @override
  Future<void> updateBudget(
    int id, {
    double? amount,
    bool? enabled,
  }) async {
    await (db.update(db.budgets)..where((b) => b.id.equals(id))).write(
      BudgetsCompanion(
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        enabled: enabled != null ? d.Value(enabled) : const d.Value.absent(),
        updatedAt: d.Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteBudget(int id) async {
    // 先获取预算信息，判断是否为总预算
    final budget = await (db.select(db.budgets)
          ..where((b) => b.id.equals(id)))
        .getSingleOrNull();

    if (budget == null) return;

    // 删除单个分类预算
    await (db.delete(db.budgets)..where((b) => b.id.equals(id))).go();
  }

  @override
  Future<Budget?> getTotalBudget(int ledgerId) async {
    // 使用 .get() 获取所有分类的预算，再归结为总预算
    final budgets = await (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId) & b.enabled.equals(true))
          ..orderBy([(b) => d.OrderingTerm(expression: b.createdAt)]))
        .get();
    // 计算总预算
    double totalBudget = 0;
    Budget? firstBudget;
    for (final budget in budgets) {
      totalBudget += budget.amount;
      firstBudget ??= budget;
    }

    DateTime now = DateTime.now();
    return Budget(
      id: 0,
      ledgerId: ledgerId,
      year: firstBudget?.year ?? now.year,
      month: firstBudget?.month ?? now.month,
      categoryId: null,
      amount: totalBudget,
      enabled: true,
      createdAt: now, // 这个字段对于总预算没有意义，设为当前时间
      updatedAt: now, // 这个字段对于总预算没有意义，设为当前时间
      prompt: false,  // 总预算不需要提示
      promptDay: null, // 总预算不需要提示日期
      ignored: false,
    );
  }

  @override
  Future<List<Budget>> getCategoryBudgets(int ledgerId) async {
    return await (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId) & b.enabled.equals(true)))
        .get();
  }

  @override
  Future<List<Budget>> getCategoryBudgetsByMonth(int ledgerId, int year, int month) async {
    return await (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId) & b.year.equals(year) & b.month.equals(month) & b.enabled.equals(true)))
        .get();
  }



  @override
  Future<Budget?> getBudgetByCategory(int ledgerId, int categoryId) async {
    return await (db.select(db.budgets)
          ..where((b) =>
              b.ledgerId.equals(ledgerId) &
              b.categoryId.equals(categoryId) &
              b.enabled.equals(true)))
        .getSingleOrNull();
  }

  @override
  Future<List<Budget>> getAllBudgets(int ledgerId) async {
    return await (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId))
          ..orderBy([
            (b) => d.OrderingTerm(expression: b.createdAt),
          ]))
        .get();
  }

  @override
  Future<List<Budget>> getAllBudgetsForExport() async {
    return await (db.select(db.budgets)
          ..orderBy([
            (b) => d.OrderingTerm(expression: b.ledgerId),
            (b) => d.OrderingTerm(expression: b.createdAt),
          ]))
        .get();
  }

  // ============================================
  // 预算统计
  // ============================================

  @override
  Future<BudgetUsage> getBudgetUsage(int budgetId, DateTime date) async {
    final budget = await (db.select(db.budgets)
          ..where((b) => b.id.equals(budgetId)))
        .getSingleOrNull();

    if (budget == null) {
      return BudgetUsage(used: 0, budget: 0);
    }

    // 计算月份日期范围
    DateTime startDate = DateTime(date.year, date.month);
    DateTime endDate = DateTime(date.year, date.month + 1);

    // 查询该周期内的支出
    double used = 0;
    // 分类预算：统计该分类支出（包含子分类）
    final result = await db.customSelect(
      '''
      SELECT COALESCE(SUM(t.amount), 0) as total
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      WHERE t.ledger_id = ?
        AND t.type = 'expense'
        AND t.happened_at >= ?
        AND t.happened_at < ?
        AND (t.category_id = ? OR c.parent_id = ?)
      ''',
      variables: [
        d.Variable.withInt(budget.ledgerId),
        d.Variable.withDateTime(startDate),
        d.Variable.withDateTime(endDate),
        d.Variable.withInt(budget.categoryId!),
        d.Variable.withInt(budget.categoryId!),
      ],
      readsFrom: {db.transactions, db.categories},
    ).getSingle();
    used = _parseDouble(result.data['total']);
    
    return BudgetUsage(used: used, budget: budget.amount);
  }

  @override
  Future<BudgetOverview> getBudgetOverview(int ledgerId, DateTime date) async {
    // 获取总预算
    // final totalBudget = await getTotalBudget(ledgerId);
    BudgetUsage? totalUsage;

    // if (totalBudget != null) {
    //   totalUsage = await getBudgetUsage(totalBudget.id, month);
    // }

    // 获取分类预算使用情况
    final categoryUsages = await getCategoryBudgetUsagesAll(ledgerId, date);
    if(categoryUsages.isNotEmpty){
      double totalUsed = 0;
      double totalBudget = 0;
      for(final categoryUsage in categoryUsages){
        totalUsed += categoryUsage.usage.used;
        totalBudget += categoryUsage.usage.budget;
        // logger.info('local_budget_repository', 'name: ${categoryUsage.categoryName} categoryUsage.usage.used: ${categoryUsage.usage.used}  categoryUsage.usage.budget: ${categoryUsage.usage.budget}');
      }
      totalUsage = BudgetUsage(used: totalUsed, budget: totalBudget);
    }else{
      totalUsage = BudgetUsage(used: 0, budget: 0);
    }
    
    // logger.info('local_budget_repository', 'totalUsage.used: ${totalUsage?.used}  totalUsage.budget: ${totalUsage?.budget}');

    DateTime now = DateTime.now();
    DateTime startDate = now.year == date.year && now.month == date.month ? now: DateTime(date.year, date.month, 1);
    DateTime endDate = DateTime(date.year, date.month + 1);
    final daysRemaining = endDate.difference(startDate).inDays;

    // 计算日均可用
    final remaining = totalUsage?.remaining ?? 0;
    final dailyAvailable = daysRemaining > 0 ? remaining / daysRemaining : 0.0;

    return BudgetOverview(
      totalBudget: totalUsage,
      categoryBudgets: categoryUsages,
      daysRemaining: daysRemaining > 0 ? daysRemaining : 0,
      dailyAvailable: dailyAvailable > 0 ? dailyAvailable : 0,
      year: date.year,
      month: date.month,
    );
  }

  @override
  Future<List<CategoryBudgetUsage>> getCategoryBudgetUsages(
    int ledgerId,
    DateTime date,
  ) async {
    final budgets = await getCategoryBudgetsByMonth(ledgerId, date.year, date.month);
    final result = <CategoryBudgetUsage>[];

    for (final budget in budgets) {
      if (budget.categoryId == null) continue;

      // 获取分类信息
      final category = await (db.select(db.categories)
            ..where((c) => c.id.equals(budget.categoryId!)))
          .getSingleOrNull();

      if (category == null) continue;

      // 获取使用情况
      final usage = await getBudgetUsage(budget.id, date);

      result.add(CategoryBudgetUsage(
        budgetId: budget.id,
        categoryId: category.id,
        categoryName: category.name,
        categoryIcon: category.icon,
        usage: usage,
      ));
    }

    // 按使用率降序排列
    result.sort((a, b) => b.usage.rate.compareTo(a.usage.rate));

    return result;
  }

  // ============================================
  // 监听
  // ============================================

  @override
  Stream<List<Budget>> watchBudgets(int ledgerId) {
    return (db.select(db.budgets)
          ..where((b) => b.ledgerId.equals(ledgerId))
          ..orderBy([
            (b) => d.OrderingTerm(expression: b.createdAt),
          ]))
        .watch();
  }

  @override
  Future<List<CategoryBudgetUsage>> getCategoryBudgetUsagesAll(
    int ledgerId,
    DateTime date,
  ) async {
    // 计算月份日期范围
    DateTime startDate = DateTime(date.year, date.month);
    DateTime endDate = DateTime(date.year, date.month + 1);

    // 获取所有分类预算
    final budgets = await getCategoryBudgetsByMonth(ledgerId, date.year, date.month);
    final budgetMap = {for (final b in budgets) b.categoryId!: b};

     // 查询所有分类在该周期内的支出（按分类分组）
    final results = await db.customSelect(
      '''
    SELECT 
      t.category_id AS category_id,
      COALESCE(SUM(t.amount), 0) AS total_expense
    FROM transactions t
    WHERE t.ledger_id = ?
      AND t.type = 'expense'
      AND t.happened_at >= ?
      AND t.happened_at < ?
      AND t.category_id IS NOT NULL  -- 排除未分类的交易
    GROUP BY t.category_id
    ''',
      variables: [
        d.Variable.withInt(ledgerId),
        d.Variable.withDateTime(startDate),
        d.Variable.withDateTime(endDate),
      ],
      readsFrom: {db.transactions},
    ).get();

    // 组装支出结果
    final categoryUsages = <CategoryBudgetUsage>[];
    final categoryUsed = <int, double>{};
    final categoryMap = <int, Category>{};
    for (final row in results) {
      final categoryId = row.data['category_id'] as int;
      final totalExpense = _parseDouble(row.data['total_expense']);

      // 获取分类信息
      final category = await (db.select(db.categories)
            ..where((c) => c.id.equals(categoryId)))
          .getSingleOrNull();
      if (category == null) continue;
      categoryMap[categoryId] = category;

      final parentId = category.parentId;
      // 如果有父分类，归类到父分类
      final useId = parentId != null && parentId > 0 ? parentId : categoryId;
      if(categoryUsed.containsKey(useId)){
        double used = categoryUsed[useId]!;
        categoryUsed[useId] = used + totalExpense;
      }else{
        categoryUsed[useId] = totalExpense;
      }
    }

    // 添加支出项
    for(final used in categoryUsed.entries){
      final categoryId = used.key;
      final expense = used.value;
      // 预算
      final budget = budgetMap[categoryId];
      budgetMap.remove(categoryId);

      late Category? category;
      if( categoryMap.containsKey(categoryId)){
        category = categoryMap[categoryId];
      }else{
        category = await (db.select(db.categories)
            ..where((c) => c.id.equals(categoryId)))
          .getSingleOrNull();
      }

      if(category == null) continue;

      categoryUsages.add(CategoryBudgetUsage(
        budgetId: budget?.id ?? 0, // 无预算时为0
        categoryId: categoryId,
        categoryName: category.name,
        categoryIcon: category.icon,
        usage: BudgetUsage(used: expense, budget: budget?.amount ?? 0.0),
      ));
    }

    // 添加未支出的预算
    for(final budget in budgetMap.values){
      final categoryId = budget.categoryId!;
      // 获取分类信息
      final category = await (db.select(db.categories)
            ..where((c) => c.id.equals(categoryId)))
          .getSingleOrNull();
      if(category == null) continue;
      
      categoryUsages.add(CategoryBudgetUsage(
        budgetId: budget.id,
        categoryId: categoryId,
        categoryName: category.name,
        categoryIcon: category.icon,
        usage: BudgetUsage(used: 0.0, budget: budget.amount),
      ));
    }

    // 按使用率降序排列
    categoryUsages.sort((a, b) => b.usage.rate.compareTo(a.usage.rate));

    return categoryUsages;
  }

  // ============================================
  // 辅助方法
  // ============================================

  double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return 0.0;
  }
}
