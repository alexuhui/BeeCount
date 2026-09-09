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
import '../../widgets/biz/ledger_picker_sheet.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import '../account/accounts_section.dart';
import '../account/account_settings_page.dart';
import '../ai/ai_settings_page.dart';
import '../budget/budget_page.dart';
import '../settings/config_import_export_page.dart';
import '../automation/auto_billing_settings_page.dart';

enum _DiscoverSection { accounts, budget }

/// 发现页
///
/// 包含预算管理和账户功能
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  _DiscoverSection _section = _DiscoverSection.accounts;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          _DiscoverHeader(
            section: _section,
            onSectionChanged: (value) => setState(() => _section = value),
          ),
          Expanded(
            child: IndexedStack(
              index: _section == _DiscoverSection.accounts ? 0 : 1,
              children: [
                ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.0.scaledSimple(context),
                    vertical: 8.0.scaledSimple(context),
                  ),
                  children: [
                    const RepaintBoundary(child: _AccountsCard()),
                    SizedBox(height: bottomPadding),
                  ],
                ),
                ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.0.scaledSimple(context),
                    vertical: 8.0.scaledSimple(context),
                  ),
                  children: [
                    const RepaintBoundary(child: _BudgetCard()),
                    SizedBox(height: bottomPadding),
                  ],
                ),
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
  final _DiscoverSection section;
  final ValueChanged<_DiscoverSection> onSectionChanged;

  const _DiscoverHeader({
    required this.section,
    required this.onSectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PrimaryHeader(
      title: '',
      showBack: false,
      showTitleSection: false,
      content: Row(
        children: [
          Expanded(
            child: _DiscoverSectionSwitcher(
              selected: section,
              onChanged: onSectionChanged,
            ),
          ),
          const SizedBox(width: 8),
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
      ),
    );
  }
}

/// 账户 / 预算切换。预算按钮底部叠一条无数字的进度缩略。
class _DiscoverSectionSwitcher extends ConsumerWidget {
  final _DiscoverSection selected;
  final ValueChanged<_DiscoverSection> onChanged;

  const _DiscoverSectionSwitcher({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = BeeTokens.isDark(context);
    final selectedBg =
        isDark ? BeeTokens.primary(context) : Colors.black;
    const height = 40.0;

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: BeeTokens.surfaceCapsule(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: _sectionTab(
              context: context,
              label: l10n.discoverAccounts,
              selected: selected == _DiscoverSection.accounts,
              selectedBg: selectedBg,
              onTap: () => onChanged(_DiscoverSection.accounts),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _budgetTab(
              context: context,
              ref: ref,
              label: l10n.discoverBudgetTab,
              selected: selected == _DiscoverSection.budget,
              selectedBg: selectedBg,
              onTap: () => onChanged(_DiscoverSection.budget),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTab({
    required BuildContext context,
    required String label,
    required bool selected,
    required Color selectedBg,
    required VoidCallback onTap,
  }) {
    final fg = selected ? Colors.white : BeeTokens.textPrimary(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }

  Widget _budgetTab({
    required BuildContext context,
    required WidgetRef ref,
    required String label,
    required bool selected,
    required Color selectedBg,
    required VoidCallback onTap,
  }) {
    final overview = ref.watch(budgetOverviewProvider).valueOrNull;
    final budget = overview?.totalBudget;
    double? rate;
    Color? color;
    if (budget != null && (budget.budget > 0 || budget.used > 0)) {
      rate = budget.budget > 0
          ? (budget.used / budget.budget).clamp(0.0, 1.0)
          : budget.used > 0
              ? 1.0
              : 0.0;
      color = _budgetProgressColor(context, rate);
    }

    final fg = selected ? Colors.white : BeeTokens.textPrimary(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            if (rate != null && color != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: rate,
                    backgroundColor:
                        color.withValues(alpha: selected ? 0.28 : 0.18),
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _budgetProgressColor(BuildContext context, double rate) {
    if (rate >= 0.9) return BeeTokens.error(context);
    if (rate >= 0.7) return BeeTokens.warning(context);
    return BeeTokens.success(context);
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
            final total = overview?.totalBudget;
            if (overview == null ||
                total == null ||
                (total.budget <= 0 && overview.categoryBudgets.isEmpty)) {
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

/// 账户卡片：默认账户、净资产、可展开列表
class _AccountsCard extends ConsumerWidget {
  const _AccountsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              IconButton(
                onPressed: () {
                  openAccountSettings(context);
                },
                tooltip: l10n.commonSettings,
                icon: Icon(
                  Icons.settings_outlined,
                  color: BeeTokens.iconSecondary(context),
                ),
              ),
              IconButton(
                onPressed: () => openAddAccount(context, ref),
                tooltip: l10n.accountAddTooltip,
                icon: Icon(
                  Icons.add,
                  color: BeeTokens.iconSecondary(context),
                ),
              ),
            ],
          ),
          const AccountsBody(),
        ],
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
