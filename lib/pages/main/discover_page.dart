import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/budget_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../services/data/category_service.dart';
import '../../services/system/logger_service.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/website_urls.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/ledger_picker_sheet.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import '../account/accounts_page.dart';
import '../account/account_detail_page.dart' show receivableStatsProvider, payableStatsProvider;
import '../ai/ai_settings_page.dart';
import '../budget/budget_page.dart';
import '../settings/config_import_export_page.dart';
import '../automation/auto_billing_settings_page.dart';

/// 发现页
///
/// 包含预算管理和账户总览功能入口
class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          _DiscoverHeader(l10n: l10n),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaledSimple(context),
                vertical: 8.0.scaledSimple(context),
              ),
              children: [
                // 预算管理卡片
                const RepaintBoundary(child: _BudgetCard()),
                const SizedBox(height: 10),

                // 账户总览卡片
                const RepaintBoundary(child: _AccountsCard()),
                const SizedBox(height: 10),

                // 快捷记账入口
                // const _QuickActionsCard(),
                SizedBox(height: bottomPadding),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 发现页头部
class _DiscoverHeader extends StatelessWidget {
  final AppLocalizations l10n;

  const _DiscoverHeader({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return PrimaryHeader(
      title: l10n.discoverTitle,
      showBack: false,
      actions: [
        Consumer(
          builder: (context, ref, child) {
            final currentLedger = ref.watch(currentLedgerProvider);
            return currentLedger.when(
              data: (ledger) => GestureDetector(
                onTap: () => showLedgerPicker(context),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.0.scaled(context, ref),
                    vertical: 6.0.scaled(context, ref),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.book_outlined,
                        size: 14,
                        color: BeeTokens.textPrimary(context),
                      ),
                      SizedBox(width: 4.0.scaled(context, ref)),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 80),
                        child: Text(
                          ledger?.name ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 2.0.scaled(context, ref)),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: BeeTokens.textPrimary(context)
                            .withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );
          },
        ),
      ],
    );
  }
}

/// 预算卡片组件
class _BudgetCard extends StatelessWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BudgetPage()),
        );
      },
      child: SectionCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                _BudgetIcon(),
                SizedBox(width: 10.0.scaledSimple(context)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.discoverBudget,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context),
                        ),
                      ),
                      const _BudgetSubtitle(),
                    ],
                  ),
                ),
                // 月/年切换开关
                const _BudgetModeSwitch(),
              ],
            ),
            SizedBox(height: 12.0.scaledSimple(context)),
            // 预算内容区域
            const _BudgetCardContent(),
          ],
        ),
      ),
    );
  }
}

/// 预算图标
class _BudgetIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final primaryColor = ref.watch(primaryColorProvider);
        return Container(
          padding: EdgeInsets.all(8.0.scaledSimple(context)),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.pie_chart_rounded,
            color: primaryColor,
            size: 20,
          ),
        );
      },
    );
  }
}

/// 预算副标题 - 根据模式显示不同内容
class _BudgetSubtitle extends StatelessWidget {
  const _BudgetSubtitle();

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final isYearly = ref.watch(budgetViewModeProvider);
        final now = DateTime.now();
        
        return Text(
          isYearly 
              ? AppLocalizations.of(context).homeYear(now.year)
              : AppLocalizations.of(context).discoverBudgetSubtitle,
          style: TextStyle(
            fontSize: 12,
            color: BeeTokens.textTertiary(context),
          ),
        );
      },
    );
  }
}

/// 预算模式切换开关
class _BudgetModeSwitch extends StatelessWidget {
  const _BudgetModeSwitch();

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final l10n = AppLocalizations.of(context);
        final isYearly = ref.watch(budgetViewModeProvider);
        final primaryColor = ref.watch(primaryColorProvider);
        
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: 4.0.scaledSimple(context),
          ),
          decoration: BoxDecoration(
            color: BeeTokens.isDark(context)
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeChip(context, ref, l10n.budgetMonthly, false, isYearly, primaryColor),
              _buildModeChip(context, ref, l10n.budgetYearly, true, isYearly, primaryColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeChip(
    BuildContext context,
    WidgetRef ref,
    String label,
    bool isYearlyMode,
    bool currentIsYearly,
    Color primaryColor,
  ) {
    final isSelected = isYearlyMode == currentIsYearly;
    return GestureDetector(
      onTap: () {
        ref.read(budgetViewModeProvider.notifier).state = isYearlyMode;
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 10.0.scaledSimple(context),
          vertical: 4.0.scaledSimple(context),
        ),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected
                ? Colors.white
                : BeeTokens.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

/// 预算内容区域 - 根据模式显示不同数据
class _BudgetCardContent extends StatelessWidget {
  const _BudgetCardContent();

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final l10n = AppLocalizations.of(context);
        final isYearly = ref.watch(budgetViewModeProvider);
        final primaryColor = ref.watch(primaryColorProvider);
        
        final overviewAsync = isYearly
            ? ref.watch(budgetOverviewForYearMonthProvider)
            : ref.watch(budgetOverviewProvider);

        return overviewAsync.when(
          data: (overview) {
            if (overview == null || overview.totalBudget == null) {
              return _buildEmptyState(context, l10n, primaryColor);
            }
            return _buildBudgetContent(context, ref, overview, l10n, primaryColor);
          },
          loading: () => _buildEmptyState(context, l10n, primaryColor),
          error: (_, __) => _buildEmptyState(context, l10n, primaryColor),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n, Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 20.0.scaledSimple(context)),
      child: Column(
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 36,
            color: primaryColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 8.0.scaledSimple(context)),
          Text(
            l10n.discoverBudgetEmpty,
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetContent(
    BuildContext context,
    WidgetRef ref,
    BudgetOverview overview,
    AppLocalizations l10n,
    Color primaryColor,
  ) {
    final budget = overview.totalBudget!;
    final rate = budget.budget > 0
        ? (budget.used / budget.budget).clamp(0.0, 1.0)
        : budget.used > 0
            ? 1.0
            : 0.0;
    final progressColor = _getProgressColor(context, rate);
    final hideAmounts = ref.watch(hideAmountsProvider);

    return Container(
      padding: EdgeInsets.all(12.0.scaledSimple(context)),
      decoration: BoxDecoration(
        color: BeeTokens.scaffoldBackground(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 显示当前年/月/日
          Text(
            '${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}',
            style: TextStyle(
              fontSize: 16,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          SizedBox(height: 12.0.scaledSimple(context)),
          // 金额和进度
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              hideAmounts
                  ? Text(
                      '¥****',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: BeeTokens.textPrimary(context),
                      ),
                    )
                  : Text(
                      '¥${budget.used.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: hideAmounts
                    ? Text(
                        ' / ****',
                        style: TextStyle(
                          fontSize: 13,
                          color: BeeTokens.textTertiary(context),
                        ),
                      )
                    : Text(
                        ' / ¥${budget.budget.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: BeeTokens.textTertiary(context),
                        ),
                      ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 8.0.scaledSimple(context),
                  vertical: 2.0.scaledSimple(context),
                ),
                decoration: BoxDecoration(
                  color: progressColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${(rate * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: progressColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.0.scaledSimple(context)),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate,
              backgroundColor: progressColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(progressColor),
              minHeight: 6,
            ),
          ),
          SizedBox(height: 6.0.scaledSimple(context)),
          // 剩余天数
          Text(
            l10n.budgetDaysRemaining(overview.daysRemaining),
            style: TextStyle(
              fontSize: 11,
              color: BeeTokens.textTertiary(context),
            ),
          ),
          // 分类预算（最多显示3个）
          if (overview.categoryBudgets.isNotEmpty) ...[
            SizedBox(height: 10.0.scaledSimple(context)),
            _buildCategoryBudgets(context, ref, overview.categoryBudgets, primaryColor),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryBudgets(
    BuildContext context,
    WidgetRef ref,
    List<CategoryBudgetUsage> categoryBudgets,
    Color primaryColor,
  ) {
    // 只显示前3个
    final displayBudgets = categoryBudgets.take(3).toList();

    return Column(
      children: [
        for (var i = 0; i < displayBudgets.length; i++) ...[
          if (i > 0) SizedBox(height: 6.0.scaledSimple(context)),
          _buildCategoryBudgetItem(context, ref, displayBudgets[i], primaryColor),
        ],
        if (categoryBudgets.length > 3) ...[
          SizedBox(height: 4.0.scaledSimple(context)),
          Text(
            '+${categoryBudgets.length - 3}',
            style: TextStyle(
              fontSize: 11,
              color: BeeTokens.textTertiary(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryBudgetItem(
    BuildContext context,
    WidgetRef ref,
    CategoryBudgetUsage usage,
    Color primaryColor,
  ) {
    final rate = usage.usage.budget > 0
        ? (usage.usage.used / usage.usage.budget).clamp(0.0, 1.0)
        : usage.usage.used > 0
            ? 1.0
            : 0.0;
    final color = _getProgressColor(context, rate);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Container(
          width: 24.0.scaledSimple(context),
          height: 24.0.scaledSimple(context),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            CategoryService.getCategoryIcon(usage.categoryIcon),
            size: 14.0.scaledSimple(context),
            color: primaryColor,
          ),
        ),
        SizedBox(width: 8.0.scaledSimple(context)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    usage.categoryName,
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  // 没有设置预算，但有支出
                  if (usage.usage.budget <= 0 && usage.usage.used > 0)
                    Text(
                      l10n.budgetEmptyHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.error(context),
                      ),
                    ),
                  hideAmounts
                      ? Text(
                          '****',
                          style: TextStyle(
                            fontSize: 11,
                            color: BeeTokens.textSecondary(context),
                          ),
                        )
                      : Text(
                          '¥${usage.usage.used.toStringAsFixed(0)}/${usage.usage.budget.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: BeeTokens.textSecondary(context),
                          ),
                        ),
                ],
              ),
              SizedBox(height: 3.0.scaledSimple(context)),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: rate,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getProgressColor(BuildContext context, double rate) {
    if (rate >= 1.0) return BeeTokens.error(context);
    if (rate >= 0.9) return BeeTokens.error(context);
    if (rate >= 0.7) return BeeTokens.warning(context);
    return BeeTokens.success(context);
  }
}

/// 账户总览卡片组件
class _AccountsCard extends StatelessWidget {
  const _AccountsCard();

  IconData _getIconForType(String type) {
    switch (type) {
      case 'cash':
        return Icons.payments_outlined;
      case 'bank_card':
        return Icons.credit_card;
      case 'credit_card':
        return Icons.credit_score;
      case 'alipay':
        return Icons.currency_yuan;
      case 'wechat':
        return Icons.chat;
      case 'receivable':
        return Icons.currency_exchange;
      case 'payable':
        return Icons.currency_exchange;
      case 'other':
        return Icons.account_balance_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'alipay':
        return const Color(0xFF1677FF);
      case 'wechat':
        return const Color(0xFF07C160);
      case 'cash':
        return Colors.orange;
      case 'bank_card':
        return const Color(0xFF1890FF);
      case 'credit_card':
        return Colors.purple;
      case 'receivable':
        return Colors.teal;
      case 'payable':
        return Colors.deepOrange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountsPage()),
        );
      },
      child: SectionCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                _AccountsIcon(),
                SizedBox(width: 10.0.scaledSimple(context)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.discoverAccounts,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context),
                        ),
                      ),
                      Text(
                        l10n.accountsManageDesc,
                        style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: BeeTokens.iconTertiary(context),
                  size: 20,
                ),
              ],
            ),
            SizedBox(height: 12.0.scaledSimple(context)),
            // 账户内容区域
            const _AccountsCardContent(),
          ],
        ),
      ),
    );
  }
}

/// 账户图标
class _AccountsIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final primaryColor = ref.watch(primaryColorProvider);
        return Container(
          padding: EdgeInsets.all(8.0.scaledSimple(context)),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.account_balance_wallet_rounded,
            color: primaryColor,
            size: 20,
          ),
        );
      },
    );
  }
}

/// 账户内容区域
class _AccountsCardContent extends StatelessWidget {
  const _AccountsCardContent();

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final accountsAsync = ref.watch(allAccountsStreamProvider);
        final totalStatsAsync = ref.watch(allAccountsTotalStatsProvider);
        final allStatsAsync = ref.watch(allAccountStatsProvider);
        final primaryColor = ref.watch(primaryColorProvider);

        return accountsAsync.when(
          data: (accounts) {
            if (accounts.isEmpty) {
              return _buildEmptyState(context, primaryColor);
            }
            return totalStatsAsync.when(
              data: (totalStats) => allStatsAsync.when(
                data: (accountStats) => _buildAccountsContent(
                  context,
                  ref,
                  accounts,
                  totalStats,
                  accountStats,
                  primaryColor,
                ),
                loading: () => _buildLoadingState(context),
                error: (_, __) => _buildEmptyState(context, primaryColor),
              ),
              loading: () => _buildLoadingState(context),
              error: (_, __) => _buildEmptyState(context, primaryColor),
            );
          },
          loading: () => _buildLoadingState(context),
          error: (_, __) => _buildEmptyState(context, primaryColor),
        );
      },
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 20.0.scaledSimple(context)),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 20.0.scaledSimple(context)),
      child: Column(
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 36,
            color: primaryColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 8.0.scaledSimple(context)),
          Text(
            AppLocalizations.of(context).discoverAccountsEmpty,
            style: TextStyle(
              fontSize: 13,
              color: BeeTokens.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsContent(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> accounts,
    ({double totalBalance, double totalExpense, double totalIncome}) totalStats,
    Map<int, ({double balance, double expense, double income})> accountStats,
    Color primaryColor,
  ) {
    final useCompact = ref.watch(compactAmountProvider);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 总余额区域
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 12.0.scaledSimple(context),
            vertical: 8.0.scaledSimple(context),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.discoverAccountsTotal,
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  SizedBox(height: 2.0.scaledSimple(context)),
                  AmountText(
                    value: totalStats.totalBalance,
                    signed: false,
                    showCurrency: true,
                    useCompactFormat: useCompact,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: totalStats.totalBalance >= 0
                          ? BeeTokens.textPrimary(context)
                          : Colors.red,
                    ),
                  ),
                ],
              ),
              Text(
                l10n.discoverAccountsCount(accounts.length),
                style: TextStyle(
                  fontSize: 11,
                  color: BeeTokens.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.0.scaledSimple(context)),
        // 账户卡片纵向布局
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8.0.scaledSimple(context)),
          child: Column(
            children: accounts.asMap().entries.map((entry) {
              final index = entry.key;
              final account = entry.value;
              final stats = accountStats[account.id];
              final balance = stats?.balance ?? account.initialBalance ?? 0.0;
              return Padding(
                padding: EdgeInsets.only(bottom: 10.0.scaledSimple(context)),
                child: _AccountCardItem(
                  account: account,
                  balance: balance,
                  primaryColor: primaryColor,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// 账户卡片项 - 支持普通账户和应收/应付账户
class _AccountCardItem extends ConsumerWidget {
  final dynamic account;
  final double balance;
  final Color primaryColor;

  const _AccountCardItem({
    required this.account,
    required this.balance,
    required this.primaryColor,
  });

  bool get isReceivableAccount => account.type == 'receivable';
  bool get isPayableAccount => account.type == 'payable';
  bool get isSpecialAccount => isReceivableAccount || isPayableAccount;

  IconData _getIconForType(String type) {
    switch (type) {
      case 'cash':
        return Icons.payments_outlined;
      case 'bank_card':
        return Icons.credit_card;
      case 'credit_card':
        return Icons.credit_score;
      case 'alipay':
        return Icons.currency_yuan;
      case 'wechat':
        return Icons.chat;
      case 'receivable':
        return Icons.currency_exchange;
      case 'payable':
        return Icons.currency_exchange;
      case 'other':
        return Icons.account_balance_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'alipay':
        return const Color(0xFF1677FF);
      case 'wechat':
        return const Color(0xFF07C160);
      case 'cash':
        return Colors.orange;
      case 'bank_card':
        return const Color(0xFF1890FF);
      case 'credit_card':
        return Colors.purple;
      case 'receivable':
        return Colors.teal;
      case 'payable':
        return Colors.deepOrange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useCompact = ref.watch(compactAmountProvider);
    final typeColor = _getColorForType(account.type);

    if (isReceivableAccount) {
      final statsAsync = ref.watch(receivableStatsProvider(account.id));
      return statsAsync.when(
        data: (stats) => _buildCard(context, ref, typeColor, useCompact, 
          label: '待收', value: stats.pending),
        loading: () => _buildCard(context, ref, typeColor, useCompact, 
          label: '待收', value: 0, isLoading: true),
        error: (_, __) => _buildCard(context, ref, typeColor, useCompact, 
          label: '待收', value: 0),
      );
    }

    if (isPayableAccount) {
      final statsAsync = ref.watch(payableStatsProvider(account.id));
      return statsAsync.when(
        data: (stats) => _buildCard(context, ref, typeColor, useCompact, 
          label: '待付', value: stats.pending),
        loading: () => _buildCard(context, ref, typeColor, useCompact, 
          label: '待付', value: 0, isLoading: true),
        error: (_, __) => _buildCard(context, ref, typeColor, useCompact, 
          label: '待付', value: 0),
      );
    }

    return _buildCard(context, ref, typeColor, useCompact, 
      label: null, value: balance);
  }

  Widget _buildCard(
    BuildContext context, 
    WidgetRef ref, 
    Color typeColor, 
    bool useCompact, {
    String? label,
    required double value,
    bool isLoading = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.0.scaled(context, ref)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            typeColor,
            typeColor.withValues(alpha: 0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: typeColor.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 账户名和图标
          Row(
            children: [
              Icon(
                _getIconForType(account.type),
                size: 16.0.scaled(context, ref),
                color: Colors.white.withValues(alpha: 0.9),
              ),
              SizedBox(width: 10.0.scaled(context, ref)),
              Text(
                account.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (label != null) ...[
                SizedBox(width: 6.0.scaled(context, ref)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6.0.scaled(context, ref),
                    vertical: 2.0.scaled(context, ref),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // 金额
          if (isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else
            AmountText(
              value: value,
              signed: false,
              showCurrency: true,
              useCompactFormat: useCompact,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

/// 快捷入口卡片
class _QuickActionsCard extends ConsumerWidget {
  final Color primaryColor;

  const _QuickActionsCard({required this.primaryColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 常用功能标题
          Text(
            l10n.discoverCommonFeatures,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: BeeTokens.textPrimary(context),
            ),
          ),
          SizedBox(height: 12.0.scaled(context, ref)),
          // 常用功能：AI设置、使用帮助、配置管理、自动记账
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  context,
                  ref,
                  icon: Icons.psychology_outlined,
                  label: l10n.discoverAISettings,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AISettingsPage()),
                  ),
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  context,
                  ref,
                  icon: Icons.help_outline,
                  label: l10n.discoverHelp,
                  onTap: () async {
                    final locale = Localizations.localeOf(context);
                    final uri = Uri.parse(WebsiteUrls.docs(locale));
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  context,
                  ref,
                  icon: Icons.settings_backup_restore,
                  label: l10n.discoverConfigManagement,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ConfigImportExportPage()),
                  ),
                ),
              ),
              Expanded(
                child: _buildActionButton(
                  context,
                  ref,
                  icon: Icons.auto_fix_high,
                  label: l10n.discoverAutoBilling,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AutoBillingSettingsPage()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48.0.scaled(context, ref),
            height: 48.0.scaled(context, ref),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 24.0.scaled(context, ref),
              color: primaryColor,
            ),
          ),
          SizedBox(height: 6.0.scaled(context, ref)),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: BeeTokens.textSecondary(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
