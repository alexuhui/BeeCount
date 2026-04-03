import 'package:beecount/data/repositories/repositories.dart';
import 'package:beecount/data/db.dart';

class ReceivablePayableCategoryHelper {
  // 借还款相关的分类名称
  static const String borrowCategoryName = '借款';
  static const String repayBorrowCategoryName = '还借款';
  static const String lendCategoryName = '借出';
  static const String receiveLendCategoryName = '收回借款';

  // 借还款相关的分类图标
  static const String borrowCategoryIcon = 'account-arrow-down';
  static const String repayBorrowCategoryIcon = 'account-arrow-up';
  static const String lendCategoryIcon = 'arrow-down-circle';
  static const String receiveLendCategoryIcon = 'arrow-up-circle';

  /// 获取或创建借款分类
  static Future<Category> getOrCreateBorrowCategory(BaseRepository repo) async {
    return await _getOrCreateCategory(repo, borrowCategoryName, 'expense', borrowCategoryIcon);
  }

  /// 获取或创建还借款分类
  static Future<Category> getOrCreateRepayBorrowCategory(BaseRepository repo) async {
    return await _getOrCreateCategory(repo, repayBorrowCategoryName, 'expense', repayBorrowCategoryIcon);
  }

  /// 获取或创建借出分类
  static Future<Category> getOrCreateLendCategory(BaseRepository repo) async {
    return await _getOrCreateCategory(repo, lendCategoryName, 'expense', lendCategoryIcon);
  }

  /// 获取或创建收回借款分类
  static Future<Category> getOrCreateReceiveLendCategory(BaseRepository repo) async {
    return await _getOrCreateCategory(repo, receiveLendCategoryName, 'income', receiveLendCategoryIcon);
  }

  /// 获取或创建分类
  static Future<Category> _getOrCreateCategory(
    BaseRepository repo,
    String name,
    String kind,
    String icon,
  ) async {
    // 先尝试获取分类
    final categories = await repo.getTopLevelCategories(kind);
    final existingCategory = categories.firstWhere(
      (c) => c.name == name,
      orElse: () => Category(
        id: -1,
        name: name,
        kind: kind,
        icon: icon,
        parentId: null,
        sortOrder: 0,
        level: 1,
        iconType: 'material',
        customIconPath: null,
        communityIconId: null,
      ),
    );

    // 如果分类不存在，创建它
    if (existingCategory.id == -1) {
      final categoryId = await repo.createCategory(
        name: name,
        kind: kind,
        icon: icon,
      );
      return Category(
        id: categoryId,
        name: name,
        kind: kind,
        icon: icon,
        parentId: null,
        sortOrder: 0,
        level: 1,
        iconType: 'material',
        customIconPath: null,
        communityIconId: null,
      );
    }

    return existingCategory;
  }
}