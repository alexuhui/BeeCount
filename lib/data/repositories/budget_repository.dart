import '../db.dart';

/// 预算使用情况
class BudgetUsage {
  final double used;      // 已用金额
  final double budget;    // 预算金额
  final double remaining; // 剩余金额
  final double rate;      // 使用率 (0-1)

  BudgetUsage({
    required this.used,
    required this.budget,
  }) : remaining = budget - used,
       rate = budget > 0 ? (used / budget).clamp(0.0, double.infinity) : 0;

  /// 状态：normal, warning, danger, exceeded
  String get status {
    if (rate >= 1.0) return 'exceeded';
    if (rate >= 0.9) return 'danger';
    if (rate >= 0.7) return 'warning';
    return 'normal';
  }
}

/// 预算概览
class BudgetOverview {
  final BudgetUsage? totalBudget;
  final List<CategoryBudgetUsage> categoryBudgets;
  final int daysRemaining;
  final double dailyAvailable;

  const BudgetOverview({
    required this.totalBudget,
    this.categoryBudgets = const [],
    required this.daysRemaining,
    required this.dailyAvailable,
  });
}

/// 分类预算使用情况
class CategoryBudgetUsage {
  final int budgetId;
  final int categoryId;
  final String categoryName;
  final String? categoryIcon;
  final BudgetUsage usage;

  const CategoryBudgetUsage({
    required this.budgetId,
    required this.categoryId,
    required this.categoryName,
    this.categoryIcon,
    required this.usage,
  });
}

/// 预算仓库接口
abstract class BudgetRepository {
  // ============ 预算 CRUD ============

  /// 创建预算
  Future<int> createBudget({
    required int ledgerId,
    int? categoryId,
    required double amount,
    // String period = 'monthly',
    // int startDay = 1,
    required int year,
    required int month,
    /// 是否到期提示支付
    required bool prompt,
    /// 提示支付时间（天）
    int? promptDay,
    /// 是否月度固定支出
    required bool isMonthlyFixedExpense,
  });

  /// 更新预算
  Future<void> updateBudget(
    int id, {
    double? amount,
    bool? enabled,
    int? year,
    int? month,
    /// 是否到期提示支付
    bool? prompt,
    /// 提示支付时间（天）
    int? promptDay,
  });

  /// 删除预算
  Future<void> deleteBudget(int id);

  /// 获取账本的总预算
  Future<Budget?> getAllBudget(int ledgerId);

  /// 获取账本的所有分类预算
  Future<List<Budget>> getCategoryBudgets(int ledgerId);

  /// 获取指定月份的预算
  Future<Budget?> getBudgetByMonth(int ledgerId, int year, int month);
  /// 获取指定月份的提示预算
  Future<Budget?> getPromptBudgetByMonth(int ledgerId, int year, int month);
  /// 获取指定年份的月度固定支出预算
  Future<Budget?> getMonthlyFixedExpenseBudget(int ledgerId, int year);

  /// 获取指定分类的预算
  Future<Budget?> getBudgetByCategory(int ledgerId, int categoryId);

  /// 获取账本的所有预算
  Future<List<Budget>> getAllBudgets(int ledgerId);

  /// 获取所有账本的所有预算（用于导出）
  Future<List<Budget>> getAllBudgetsForExport();

  // ============ 预算统计 ============

  /// 获取预算使用情况
  Future<BudgetUsage> getBudgetUsage(int budgetId, DateTime month);

  /// 获取账本当月预算概览
  Future<BudgetOverview> getBudgetOverview(int ledgerId, DateTime month);

  /// 批量获取分类预算使用情况
  Future<List<CategoryBudgetUsage>> getCategoryBudgetUsages(
    int ledgerId,
    DateTime month,
  );

  // ============ 监听 ============

  /// 监听预算变化
  Stream<List<Budget>> watchBudgets(int ledgerId);
}
