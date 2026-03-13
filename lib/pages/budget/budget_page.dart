
import 'package:beecount/services/system/logger_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/budget_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/budget_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'budget_edit_page.dart';
import 'widgets/budget_progress_bar.dart';
import 'widgets/category_budget_tile.dart';

/// 预算管理页面
class BudgetPage extends ConsumerWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overviewAsync = ref.watch(budgetOverviewForYearMonthProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.budgetTitle,
            showBack: true,
            compact: true,
            actions: [
              IconButton(
                onPressed: () => _addBudget(context, overviewAsync.value),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Expanded(
            child: overviewAsync.when(
              data: (overview) => _buildContent(context, ref, overview),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, BudgetOverview? overview) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        // 总预算概览卡片（固定在顶部）
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16.0.scaled(context, ref),
            vertical: 8.0.scaled(context, ref),
          ),
          child: _buildTotalBudgetCard(context, ref, overview!, l10n),
        ),

        SizedBox(height: 12.0.scaled(context, ref)),

        // 分类预算列表（可滚动）
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: 16.0.scaled(context, ref),
            ),
            children: [
              overview.categoryBudgets.isNotEmpty
                  ?
                  // 有预算就显示记录
                  _buildCategoryBudgetsCard(
                      context, ref, overview.categoryBudgets, l10n, overview)
                  // 没有预算就显示提示
                  : Center(
                      child: TextButton(
                        onPressed: () => _addBudget(context, overview),
                        child: Text(l10n.budgetEmptyHint),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );



    // if (overview == null || overview.totalBudget == null) {
    //   return _buildEmptyState(context, ref, l10n);
    // }

    // return ListView(
    //   padding: EdgeInsets.symmetric(
    //     horizontal: 12.0.scaled(context, ref),
    //     vertical: 8.0.scaled(context, ref),
    //   ),
    //   children: [
    //     // 总预算概览卡片
    //     _buildTotalBudgetCard(context, ref, overview, l10n),
    //     SizedBox(height: 12.0.scaled(context, ref)),
    //     // 分类预算列表
    //     if (overview.categoryBudgets.isNotEmpty)
    //       _buildCategoryBudgetsCard(
    //           context, ref, overview.categoryBudgets, l10n),
    //   ],
    // );
  }

  // Widget _buildEmptyState(
  //     BuildContext context, WidgetRef ref, AppLocalizations l10n) {
  //   return Center(
  //     child: Column(
  //       mainAxisAlignment: MainAxisAlignment.center,
  //       children: [
  //         Icon(
  //           Icons.account_balance_wallet_outlined,
  //           size: 64,
  //           color: BeeTokens.textTertiary(context),
  //         ),
  //         const SizedBox(height: 16),
  //         Text(
  //           l10n.budgetEmptyHint,
  //           style: TextStyle(
  //             fontSize: 16,
  //             color: BeeTokens.textSecondary(context),
  //           ),
  //         ),
  //         const SizedBox(height: 24),
  //         ElevatedButton.icon(
  //           onPressed: () => _addBudget(context),
  //           icon: Icon(Icons.add, color: BeeTokens.buttonPrimaryText(context)),
  //           label: Text(l10n.budgetAddTotal),
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: BeeTokens.buttonPrimary(context),
  //             foregroundColor: BeeTokens.buttonPrimaryText(context),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildTotalBudgetCard(
    BuildContext context,
    WidgetRef ref,
    BudgetOverview overview,
    AppLocalizations l10n,
  ) {

    logger.info('BudgetPage', 'overview.totalBudget: ${overview.totalBudget}');

    final budget = overview.totalBudget!;

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildYearMonthSelector(context, ref),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.configIncludeBudgets,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.0.scaled(context, ref)),
          // 进度条
          BudgetProgressBar(
            used: budget.used,
            budget: budget.budget,
            showLabel: false,
            height: 12,
          ),
          SizedBox(height: 12.0.scaled(context, ref)),
          // 金额信息
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.budgetUsed,
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  Text(
                    '¥${budget.used.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.budgetRemaining,
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  Text(
                    '¥${budget.remaining.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: budget.remaining >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.0.scaled(context, ref)),
          // 日均可用
          Container(
            padding: EdgeInsets.all(12.0.scaled(context, ref)),
            decoration: BoxDecoration(
              color: BeeTokens.isDark(context)
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.budgetDaysRemaining(overview.daysRemaining),
                  style: TextStyle(
                    fontSize: 14,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
                Text(
                  l10n.budgetDailyAvailable(
                      overview.dailyAvailable.toStringAsFixed(0)),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBudgetsCard(
    BuildContext context,
    WidgetRef ref,
    List<CategoryBudgetUsage> categoryBudgets,
    AppLocalizations l10n,
    BudgetOverview? overview,
  ) {
    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.budgetCategoryBudgets,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
              TextButton(
                onPressed: () => _addBudget(context, overview),
                child: Text(l10n.commonAdd),
              ),
            ],
          ),
          ...categoryBudgets.map(
            (usage) => CategoryBudgetTile(
              usage: usage,
              onTap: () => _editCategoryBudget(context, ref, usage),
            ),
          ),
        ],
      ),
    );
  }

  void _addBudget(BuildContext context, BudgetOverview? overview) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BudgetEditPage(
          year: overview?.year ?? DateTime.now().year,
          month: overview?.month ?? DateTime.now().month,
        ),
      ),
    );
  }

  void _editCategoryBudget(
    BuildContext context,
    WidgetRef ref,
    CategoryBudgetUsage usage,
  ) async {
    final allBudgets = await ref.read(allBudgetsProvider.future);
    final budget = allBudgets.where((b) => b.id == usage.budgetId).firstOrNull;
    if (budget != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BudgetEditPage(
            year: budget.year,
            month: budget.month,
            budget: budget,
          ),
        ),
      );
    }
  }

  /// 年份选择器，默认显示当前年份
  Widget _buildYearMonthSelector(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final yearMonthAsync = ref.watch(selectedBudgetYearMonthProvider);
    final now = DateTime.now();
    final maxYear = 5;
    final isMinYear = yearMonthAsync.year <= now.year;
    final isMaxYear = yearMonthAsync.year >= now.year + maxYear - 1;
    final isMinMonth = yearMonthAsync.month == 1;
    final isMaxMonth = yearMonthAsync.month == 12;
    return Column(children: [
      Row(children: [
        // 固定高度
        GestureDetector(
          onTap: () {
            if (!isMinYear) {
              ref.read(selectedBudgetYearMonthProvider.notifier).state =
                  DateTime(yearMonthAsync.year - 1, yearMonthAsync.month);
            }
          },
          child: Icon(
            Icons.chevron_left,
            color: isMinYear
                ? BeeTokens.iconTertiary(context)
                : BeeTokens.iconPrimary(context),
            size: 40,
          ),
        ),
        Expanded(
            child: DropdownButtonFormField<int>(
          initialValue: yearMonthAsync.year,
          decoration: InputDecoration(
            labelText: l10n.selectYear,
            border: OutlineInputBorder(),
          ),
          items: List.generate(maxYear, (index) {
            final year = DateTime.now().year + index;
            return DropdownMenuItem(
              value: year,
              child: Text(l10n.homeYear(year)),
            );
          }),
          onChanged: (value) => ref
              .read(selectedBudgetYearMonthProvider.notifier)
              .state = DateTime(value!, yearMonthAsync.month),
        )),
        GestureDetector(
          onTap: () {
            if (!isMaxYear) {
              ref.read(selectedBudgetYearMonthProvider.notifier).state =
                  DateTime(yearMonthAsync.year + 1, yearMonthAsync.month);
            }
          },
          child: Icon(
            Icons.chevron_right,
            color: isMaxYear
                ? BeeTokens.iconTertiary(context)
                : BeeTokens.iconPrimary(context),
            size: 40,
          ),
        ),
      ]),

      // 两个下拉框之间的间距
      const SizedBox(height: 16.0),
      Row(children: [
        GestureDetector(
          onTap: () {
            if (!isMinMonth) {
              ref.read(selectedBudgetYearMonthProvider.notifier).state =
                  DateTime(yearMonthAsync.year, yearMonthAsync.month - 1);
            }
          },
          child: Icon(
            Icons.chevron_left,
            color: isMinMonth
                ? BeeTokens.iconTertiary(context)
                : BeeTokens.iconPrimary(context),
            size: 40,
          ),
        ),
        Expanded(
            child: DropdownButtonFormField<int>(
          initialValue: yearMonthAsync.month,
          decoration: InputDecoration(
            labelText: l10n.selectMonth,
            border: OutlineInputBorder(),
          ),
          items: List.generate(12, (index) {
            final month = index + 1;
            return DropdownMenuItem(
              value: month,
              child: Text(l10n.homeMonth(month.toString())),
            );
          }),
          onChanged: (value) => ref
              .read(selectedBudgetYearMonthProvider.notifier)
              .state = DateTime(yearMonthAsync.year, value!),
        )),
        GestureDetector(
          onTap: () {
            if (!isMaxMonth) {
              ref.read(selectedBudgetYearMonthProvider.notifier).state =
                  DateTime(yearMonthAsync.year, yearMonthAsync.month + 1);
            }
          },
          child: Icon(
            Icons.chevron_right,
            color: isMaxMonth
                ? BeeTokens.iconTertiary(context)
                : BeeTokens.iconPrimary(context),
            size: 40,
          ),
        ),
      ]),
    ]);
  }
}
