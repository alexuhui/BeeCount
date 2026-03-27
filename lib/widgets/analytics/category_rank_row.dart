import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../styles/tokens.dart';
import '../../widgets/category_icon.dart';
import '../biz/biz.dart';
import '../../utils/category_utils.dart';
import '../../providers.dart';
import '../../pages/transaction/category_detail_page.dart';
import '../../l10n/app_localizations.dart';
import '../../data/db.dart' as db;

class CategoryRankRow extends ConsumerStatefulWidget {
  final int? categoryId; // 分类ID
  final db.Category? category; // 分类对象（用于显示图标）
  final String name;
  final double value;
  final double? budget; // 预算金额（可选）
  final double percent; // 0..1 (相对于总金额的真实占比)
  final Color color;
  final DateTime start; // 统计开始时间
  final DateTime end; // 统计结束时间
  final String scope; // 周期范围
  final DateTime selMonth; // 选中的月份

  const CategoryRankRow({
    super.key,
    this.categoryId,
    this.category,
    required this.name,
    required this.value,
    this.budget,
    required this.percent,
    required this.color,
    required this.start,
    required this.end,
    required this.scope,
    required this.selMonth,
  });

  @override
  ConsumerState<CategoryRankRow> createState() => _CategoryRankRowState();
}

class _CategoryRankRowState extends ConsumerState<CategoryRankRow> {
  bool _expanded = false;
  List<({int id, db.Category category, String name, double total, double percent})>? _subCategories;
  bool _hasCheckedSubCategories = false;

  @override
  void didUpdateWidget(CategoryRankRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当一级分类的金额或占比发生变化时，重置二级分类缓存
    if (oldWidget.value != widget.value || oldWidget.percent != widget.percent) {
      _hasCheckedSubCategories = false;
      _subCategories = null;
      // 如果当前是展开状态，重新加载数据
      if (_expanded) {
        _loadSubCategories();
      }
    }
  }


  Future<void> _loadSubCategories() async {
    if (widget.categoryId == null) return;

    final repo = ref.read(repositoryProvider);
    final ledger = await ref.read(currentLedgerProvider.future);
    if (ledger == null) return;
    final ledgerId = ledger.id;

    // 获取二级分类列表
    final subCats = await repo.getSubCategories(widget.categoryId!);

    if (subCats.isEmpty) {
      setState(() {
        _hasCheckedSubCategories = true;
        _subCategories = [];
      });
      return;
    }

    // 计算总金额（用于计算真实占比）
    double totalAmount = widget.value; // 一级分类总金额作为基准

    // 计算每个二级分类的统计数据
    final subCatData = <({int id, db.Category category, String name, double total, double percent})>[];

    for (final subCat in subCats) {
      // 获取该二级分类在指定时间范围内的交易总额
      final transactions = await repo.getTransactionsByCategory(subCat.id);

      // 筛选时间范围并计算总额
      double total = 0.0;
      for (final tx in transactions) {
        if (tx.happenedAt.isAfter(widget.start.subtract(const Duration(seconds: 1))) &&
            tx.happenedAt.isBefore(widget.end.add(const Duration(days: 1))) &&
            tx.ledgerId == ledgerId) {
          total += tx.amount;
        }
      }

      if (total > 0) {
        // 计算真实占比（相对于整体总额，而非一级分类）
        final percent = widget.percent * (total / totalAmount);
        subCatData.add((
          id: subCat.id,
          category: subCat,
          name: subCat.name,
          total: total,
          percent: percent,
        ));
      }
    }

    // 按金额降序排列
    subCatData.sort((a, b) => b.total.compareTo(a.total));

    setState(() {
      _hasCheckedSubCategories = true;
      _subCategories = subCatData;
    });
  }

  void _handleTap(int? categoryId, String categoryName) {
    if (categoryId == null) return;

    // 生成周期标签
    String? periodLabel;
    if (widget.scope != 'all') {
      periodLabel = _currentPeriodLabel(widget.scope, widget.selMonth, context);
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryDetailPage(
          categoryId: categoryId,
          categoryName: categoryName,
          startDate: widget.scope != 'all' ? widget.start : null,
          endDate: widget.scope != 'all' ? widget.end : null,
          periodLabel: periodLabel,
        ),
      ),
    );
  }

  String _currentPeriodLabel(String scope, DateTime selMonth, BuildContext context) {
    switch (scope) {
      case 'year':
        return '${selMonth.year}';
      case 'all':
        return AppLocalizations.of(context).analyticsAllYears;
      default:
        return '${selMonth.year}.${selMonth.month.toString().padLeft(2, '0')}';
    }
  }

  void _handleTopLevelTap() async {
    // 首次点击时检查是否有子分类
    if (!_hasCheckedSubCategories) {
      await _loadSubCategories();
    }

    // 有子分类：展开/折叠
    if (_subCategories != null && _subCategories!.isNotEmpty) {
      setState(() {
        _expanded = !_expanded;
      });
    } else {
      // 无子分类：打开详情页
      _handleTap(widget.categoryId, widget.name);
    }
  }

  Widget _buildCategoryRow({
    required int? categoryId,
    required db.Category? category,
    required String name,
    required double value,
    double? budget,
    required double percent,
    required bool isTopLevel,
  }) {
    final iconWidget = CategoryIconWidget(
      category: category,
      categoryName: name,
      size: isTopLevel ? 20 : 18,
      color: widget.color,
    );

    String formatAmount(double amount) {
      if (amount == amount.truncate()) {
        return amount.toInt().toString();
      }
      final str = amount.toStringAsFixed(2);
      if (str.endsWith('0')) {
        return str.substring(0, str.length - 1);
      }
      return str;
    }

    String displayText;
    if (budget != null && budget > 0) {
      displayText = '${formatAmount(value)}/${formatAmount(budget)}';
    } else {
      displayText = formatAmount(value);
    }

    return InkWell(
      onTap: isTopLevel
          ? _handleTopLevelTap
          : () => _handleTap(categoryId, name),
      splashColor: isTopLevel ? Colors.transparent : null,
      highlightColor: isTopLevel ? Colors.transparent : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: isTopLevel ? 0 : 16.0,
          top: isTopLevel ? 10.0 : 8.0,
          bottom: isTopLevel ? 10.0 : 8.0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: isTopLevel ? 44 : 38,
              height: isTopLevel ? 44 : 38,
              decoration: BoxDecoration(
                color: isTopLevel
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                    : widget.color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: iconWidget,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          CategoryUtils.getDisplayName(name, context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: isTopLevel ? 14 : 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        displayText,
                        style: TextStyle(fontSize: isTopLevel ? 14 : 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${(percent * 100).toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: BeeTokens.textTertiary(context),
                          fontSize: isTopLevel ? 12 : 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(
                          height: isTopLevel ? 6 : 5,
                          color: widget.color.withValues(alpha: 0.15),
                        ),
                        FractionallySizedBox(
                          widthFactor: percent.clamp(0, 1),
                          child: Container(
                            height: isTopLevel ? 6 : 5,
                            color: widget.color.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoryRow(
          categoryId: widget.categoryId,
          category: widget.category,
          name: widget.name,
          value: widget.value,
          budget: widget.budget,
          percent: widget.percent,
          isTopLevel: true,
        ),
        if (_expanded && _subCategories != null && _subCategories!.isNotEmpty)
          ...(_subCategories!.map((subCat) {
            return _buildCategoryRow(
              categoryId: subCat.id,
              category: subCat.category,
              name: subCat.name,
              value: subCat.total,
              percent: subCat.percent,
              isTopLevel: false,
            );
          }).toList()),
      ],
    );
  }
}
