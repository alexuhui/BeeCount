import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
import '../../utils/invest_tx.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/amount_text.dart';
import 'account_detail_page.dart';
import 'account_edit_page.dart';

IconData accountIconForType(String type) {
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
    case 'investment':
      return Icons.show_chart;
    case 'receivable':
    case 'payable':
      return Icons.currency_exchange;
    case 'other':
      return Icons.account_balance_outlined;
    default:
      return Icons.account_balance_wallet_outlined;
  }
}

Color accountColorForType(String type, Color primaryColor) {
  switch (type) {
    case 'alipay':
      return const Color(0xFF1677FF);
    case 'wechat':
      return const Color(0xFF07C160);
    case 'investment':
      return const Color(0xFF2E7D32);
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
      return primaryColor;
  }
}

String accountTypeLabel(BuildContext context, String type) {
  final l10n = AppLocalizations.of(context);
  switch (type) {
    case 'cash':
      return l10n.accountTypeCash;
    case 'bank_card':
      return l10n.accountTypeBankCard;
    case 'credit_card':
      return l10n.accountTypeCreditCard;
    case 'alipay':
      return l10n.accountTypeAlipay;
    case 'wechat':
      return l10n.accountTypeWechat;
    case 'investment':
      return l10n.accountTypeInvestment;
    case 'receivable':
      return '应收款';
    case 'payable':
      return '应付款';
    case 'other':
      return l10n.accountTypeOther;
    default:
      return type;
  }
}

Future<void> openAddAccount(BuildContext context, WidgetRef ref) async {
  final ledgerId = ref.read(currentLedgerIdProvider);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => AccountEditPage(ledgerId: ledgerId),
    ),
  );
  ref.invalidate(allAccountStatsProvider);
  ref.invalidate(allAccountsTotalStatsProvider);
  ref.invalidate(accountsProvider);
  ref.invalidate(statsRefreshProvider);
}

Future<void> openEditAccount(
  BuildContext context,
  WidgetRef ref,
  db.Account account,
) async {
  final ledgerId = ref.read(currentLedgerIdProvider);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => AccountEditPage(
        account: account,
        ledgerId: ledgerId,
      ),
    ),
  );
  ref.invalidate(allAccountStatsProvider);
  ref.invalidate(allAccountsTotalStatsProvider);
  ref.invalidate(accountsProvider);
  ref.invalidate(statsRefreshProvider);
}

const _accountTypeOrder = [
  'cash',
  'bank_card',
  'credit_card',
  'alipay',
  'wechat',
  'investment',
  'receivable',
  'payable',
  'other',
];

int _typeSortIndex(String type) {
  final i = _accountTypeOrder.indexOf(type);
  return i < 0 ? 1000 : i;
}

List<MapEntry<String, List<db.Account>>> groupAccountsByType(
    List<db.Account> accounts) {
  final map = <String, List<db.Account>>{};
  for (final account in accounts) {
    map.putIfAbsent(account.type, () => []).add(account);
  }
  final keys = map.keys.toList()
    ..sort((a, b) {
      final cmp = _typeSortIndex(a).compareTo(_typeSortIndex(b));
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  return [for (final k in keys) MapEntry(k, map[k]!)];
}
class AccountsBody extends ConsumerStatefulWidget {
  const AccountsBody({super.key});

  @override
  ConsumerState<AccountsBody> createState() => _AccountsBodyState();
}

class _AccountsBodyState extends ConsumerState<AccountsBody> {
  int? _expandedAccountId;
  final Set<String> _expandedTypeGroups = {};

  List<Widget> _accountTiles(
    List<db.Account> accounts,
    Map<int, ({double balance, double expense, double income})>? allStats,
    Color primaryColor,
  ) {
    return [
      for (final account in accounts)
        Padding(
          padding: EdgeInsets.only(
            left: 8.0.scaled(context, ref),
            right: 8.0.scaled(context, ref),
            bottom: 10.0.scaled(context, ref),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expandedAccountId == account.id
                ? _ExpandedAccountCard(
                    account: account,
                    primaryColor: primaryColor,
                    stats: allStats?[account.id],
                    onCollapse: () =>
                        setState(() => _expandedAccountId = null),
                    onEdit: () => openEditAccount(context, ref, account),
                  )
                : _CompactAccountBar(
                    account: account,
                    balance: allStats?[account.id]?.balance ??
                        account.initialBalance,
                    primaryColor: primaryColor,
                    onExpand: () =>
                        setState(() => _expandedAccountId = account.id),
                  ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final totalStatsAsync = ref.watch(allAccountsTotalStatsProvider);
    final allStatsAsync = ref.watch(allAccountStatsProvider);
    final primaryColor = ref.watch(primaryColorProvider);
    final groupByType =
        ref.watch(accountsGroupByTypeProvider).valueOrNull ?? false;

    return accountsAsync.when(
      data: (accounts) {
        if (accounts.isEmpty) {
          return _EmptyAccounts(
            primaryColor: primaryColor,
            onAdd: () => openAddAccount(context, ref),
          );
        }

        final hasInvest =
            accounts.any((a) => InvestTx.isInvestmentAccount(a.type));
        final investSum = hasInvest
            ? ref.watch(investmentAccountsSummaryProvider).asData?.value
            : null;
        final allStats = allStatsAsync.asData?.value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            totalStatsAsync.when(
              data: (stats) {
                final items = <({
                  String label,
                  double value,
                  Color color
                })>[
                  (
                    label: l10n.accountTotalBalance,
                    value: stats.totalBalance,
                    color: stats.totalBalance >= 0
                        ? BeeTokens.textPrimary(context)
                        : Colors.red,
                  ),
                  (
                    label: l10n.accountTotalIncome,
                    value: stats.totalIncome,
                    color: BeeTokens.incomeColor(context, ref),
                  ),
                  (
                    label: l10n.accountTotalExpense,
                    value: stats.totalExpense,
                    color: BeeTokens.expenseColor(context, ref),
                  ),
                  if (investSum != null) ...[
                    (
                      label: l10n.investSummaryTitle,
                      value: investSum.marketValue,
                      color: BeeTokens.textPrimary(context),
                    ),
                    (
                      label: l10n.investTotalPnl,
                      value: investSum.totalPnl,
                      color: investSum.totalPnl >= 0
                          ? BeeTokens.incomeColor(context, ref)
                          : BeeTokens.expenseColor(context, ref),
                    ),
                  ],
                ];
                return _StatsGrid(items: items);
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
            SizedBox(height: 8.0.scaled(context, ref)),
            if (groupByType)
              ...groupAccountsByType(accounts).expand((entry) {
                final type = entry.key;
                final group = entry.value;
                final expanded = _expandedTypeGroups.contains(type);
                final total = group.fold<double>(
                  0,
                  (sum, a) =>
                      sum + (allStats?[a.id]?.balance ?? a.initialBalance),
                );
                return [
                  Padding(
                    padding: EdgeInsets.only(
                      left: 8.0.scaled(context, ref),
                      right: 8.0.scaled(context, ref),
                      bottom: 8.0.scaled(context, ref),
                    ),
                    child: _TypeGroupHeader(
                      type: type,
                      count: group.length,
                      totalBalance: total,
                      expanded: expanded,
                      onToggle: () {
                        setState(() {
                          if (expanded) {
                            _expandedTypeGroups.remove(type);
                          } else {
                            _expandedTypeGroups.add(type);
                          }
                        });
                      },
                    ),
                  ),
                  if (expanded)
                    ..._accountTiles(group, allStats, primaryColor),
                ];
              })
            else
              ..._accountTiles(accounts, allStats, primaryColor),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('${l10n.commonError}: $err'),
      ),
    );
  }
}

class _StatsGrid extends ConsumerWidget {
  final List<({String label, double value, Color color})> items;

  const _StatsGrid({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 3) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i + 3 < items.length ? 12.0.scaled(context, ref) : 0,
          ),
          child: Row(
            children: [
              for (var j = 0; j < 3; j++)
                Expanded(
                  child: j + i < items.length
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: _StatCell(
                            label: items[i + j].label,
                            value: items[i + j].value,
                            color: items[i + j].color,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16.0.scaled(context, ref),
        vertical: 12.0.scaled(context, ref),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

class _TypeGroupHeader extends ConsumerWidget {
  final String type;
  final int count;
  final double totalBalance;
  final bool expanded;
  final VoidCallback onToggle;

  const _TypeGroupHeader({
    required this.type,
    required this.count,
    required this.totalBalance,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final typeColor = accountColorForType(type, primaryColor);
    return Material(
      color: BeeTokens.surface(context),
      borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12.0.scaled(context, ref),
            vertical: 10.0.scaled(context, ref),
          ),
          child: Row(
            children: [
              Icon(accountIconForType(type), color: typeColor, size: 20),
              SizedBox(width: 8.0.scaled(context, ref)),
              Expanded(
                child: Text(
                  '${accountTypeLabel(context, type)} ($count)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
              ),
              AmountText(
                value: totalBalance,
                signed: false,
                showCurrency: false,
                useCompactFormat: ref.watch(compactAmountProvider),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: BeeTokens.iconSecondary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  final Color primaryColor;
  final VoidCallback onAdd;

  const _EmptyAccounts({
    required this.primaryColor,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          SizedBox(height: 12.0.scaledSimple(context)),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(AppLocalizations.of(context).accountAddButton),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends ConsumerWidget {
  final String label;
  final double value;
  final Color color;

  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AmountText(
          value: value,
          signed: false,
          showCurrency: false,
          useCompactFormat: ref.watch(compactAmountProvider),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: 4.0.scaled(context, ref)),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: BeeTokens.textSecondary(context),
          ),
          textAlign: TextAlign.left,
        ),
      ],
    );
  }
}

class _CompactAccountBar extends ConsumerWidget {
  final db.Account account;
  final double balance;
  final Color primaryColor;
  final VoidCallback onExpand;

  const _CompactAccountBar({
    required this.account,
    required this.balance,
    required this.primaryColor,
    required this.onExpand,
  });

  bool get isReceivableAccount => account.type == 'receivable';
  bool get isPayableAccount => account.type == 'payable';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useCompact = ref.watch(compactAmountProvider);
    final typeColor = accountColorForType(account.type, primaryColor);

    if (isReceivableAccount) {
      final statsAsync = ref.watch(receivableStatsProvider(account.id));
      return statsAsync.when(
        data: (stats) => _bar(context, ref, typeColor, useCompact,
            label: '待收', value: stats.pending),
        loading: () => _bar(context, ref, typeColor, useCompact,
            label: '待收', value: 0, isLoading: true),
        error: (_, __) => _bar(context, ref, typeColor, useCompact,
            label: '待收', value: 0),
      );
    }

    if (isPayableAccount) {
      final statsAsync = ref.watch(payableStatsProvider(account.id));
      return statsAsync.when(
        data: (stats) => _bar(context, ref, typeColor, useCompact,
            label: '待付', value: stats.pending),
        loading: () => _bar(context, ref, typeColor, useCompact,
            label: '待付', value: 0, isLoading: true),
        error: (_, __) => _bar(context, ref, typeColor, useCompact,
            label: '待付', value: 0),
      );
    }

    return _bar(context, ref, typeColor, useCompact,
        label: null, value: balance);
  }

  Widget _bar(
    BuildContext context,
    WidgetRef ref,
    Color typeColor,
    bool useCompact, {
    String? label,
    required double value,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
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
            children: [
              Icon(
                accountIconForType(account.type),
                size: 16.0.scaled(context, ref),
                color: Colors.white.withValues(alpha: 0.9),
              ),
              SizedBox(width: 10.0.scaled(context, ref)),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
              ),
              SizedBox(width: 8.0.scaled(context, ref)),
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
        ),
      ),
    );
  }
}

class _ExpandedAccountCard extends ConsumerWidget {
  final db.Account account;
  final Color primaryColor;
  final ({double balance, double expense, double income})? stats;
  final VoidCallback onCollapse;
  final VoidCallback onEdit;

  const _ExpandedAccountCard({
    required this.account,
    required this.primaryColor,
    this.stats,
    required this.onCollapse,
    required this.onEdit,
  });

  bool get isReceivableAccount => account.type == 'receivable';
  bool get isPayableAccount => account.type == 'payable';
  bool get isInvestmentAccount => InvestTx.isInvestmentAccount(account.type);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeColor = accountColorForType(account.type, primaryColor);
    final receivableStatsAsync =
        isReceivableAccount ? ref.watch(receivableStatsProvider(account.id)) : null;
    final payableStatsAsync =
        isPayableAccount ? ref.watch(payableStatsProvider(account.id)) : null;
    final investStatsAsync = isInvestmentAccount
        ? ref.watch(investmentPeriodStatsProvider((
            accountId: account.id,
            from: DateTime(1970, 1, 1),
            to: DateTime.now().add(const Duration(days: 1)),
          )))
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCollapse,
        borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                typeColor,
                typeColor.withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
            boxShadow: [
              BoxShadow(
                color: typeColor.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
            child: Stack(
              children: [
                Positioned(
                  right: -20,
                  top: -20,
                  child: Container(
                    width: 100.0.scaled(context, ref),
                    height: 100.0.scaled(context, ref),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                Positioned(
                  right: 40,
                  bottom: -30,
                  child: Container(
                    width: 120.0.scaled(context, ref),
                    height: 120.0.scaled(context, ref),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16.0.scaled(context, ref)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40.0.scaled(context, ref),
                            height: 40.0.scaled(context, ref),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              accountIconForType(account.type),
                              color: Colors.white,
                              size: 20.0.scaled(context, ref),
                            ),
                          ),
                          SizedBox(width: 12.0.scaled(context, ref)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        account.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 8.0.scaled(context, ref)),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6.0.scaled(context, ref),
                                        vertical: 2.0.scaled(context, ref),
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(
                                            4.0.scaled(context, ref)),
                                      ),
                                      child: Text(
                                        getCurrencyName(
                                            account.currency, context),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 2.0.scaled(context, ref)),
                                Text(
                                  accountTypeLabel(context, account.type),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 12.0.scaled(context, ref)),
                          Material(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AccountDetailPage(account: account),
                                  ),
                                );
                              },
                              child: Padding(
                                padding:
                                    EdgeInsets.all(8.0.scaled(context, ref)),
                                child: Icon(
                                  Icons.receipt_long,
                                  color: Colors.white,
                                  size: 16.0.scaled(context, ref),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8.0.scaled(context, ref)),
                          Material(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onEdit,
                              child: Padding(
                                padding:
                                    EdgeInsets.all(8.0.scaled(context, ref)),
                                child: Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 16.0.scaled(context, ref),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16.0.scaled(context, ref)),
                      if (isReceivableAccount)
                        _ReceivableStatsRow(
                          account: account,
                          statsAsync: receivableStatsAsync,
                        )
                      else if (isPayableAccount)
                        _PayableStatsRow(
                          account: account,
                          statsAsync: payableStatsAsync,
                        )
                      else if (isInvestmentAccount && investStatsAsync != null)
                        investStatsAsync.when(
                          data: (s) => Row(
                            children: [
                              Expanded(
                                child: _CardStatItem(
                                  label: AppLocalizations.of(context)
                                      .investMarketValue,
                                  value: s.closingValue,
                                  currencyCode: account.currency,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 30.0.scaled(context, ref),
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              Expanded(
                                child: _CardStatItem(
                                  label: AppLocalizations.of(context)
                                      .investTotalPnl,
                                  value: s.totalPnl,
                                  currencyCode: account.currency,
                                ),
                              ),
                            ],
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        )
                      else if (stats != null)
                        Row(
                          children: [
                            Expanded(
                              child: _CardStatItem(
                                label: AppLocalizations.of(context)
                                    .accountBalance,
                                value: stats!.balance,
                                currencyCode: account.currency,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 30.0.scaled(context, ref),
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            Expanded(
                              child: _CardStatItem(
                                label: AppLocalizations.of(context).homeIncome,
                                value: stats!.income,
                                currencyCode: account.currency,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 30.0.scaled(context, ref),
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            Expanded(
                              child: _CardStatItem(
                                label: AppLocalizations.of(context).homeExpense,
                                value: stats!.expense,
                                currencyCode: account.currency,
                              ),
                            ),
                          ],
                        )
                      else
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: 8.0.scaled(context, ref)),
                            child: const CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardStatItem extends ConsumerWidget {
  final String label;
  final double value;
  final String currencyCode;

  const _CardStatItem({
    required this.label,
    required this.value,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        AmountText(
          value: value,
          signed: false,
          showCurrency: false,
          useCompactFormat: ref.watch(compactAmountProvider),
          currencyCode: currencyCode,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 2.0.scaled(context, ref)),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ReceivableStatsRow extends ConsumerWidget {
  final db.Account account;
  final AsyncValue<({double pending, double total, double received})>? statsAsync;

  const _ReceivableStatsRow({
    required this.account,
    required this.statsAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (statsAsync == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 2,
          ),
        ),
      );
    }

    return statsAsync!.when(
      data: (stats) => Row(
        children: [
          Expanded(
            child: _CardStatItem(
              label: '待收',
              value: stats.pending,
              currencyCode: account.currency,
            ),
          ),
          Container(
            width: 1,
            height: 30.0.scaled(context, ref),
            color: Colors.white.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _CardStatItem(
              label: '总额',
              value: stats.total,
              currencyCode: account.currency,
            ),
          ),
          Container(
            width: 1,
            height: 30.0.scaled(context, ref),
            color: Colors.white.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _CardStatItem(
              label: '已收',
              value: stats.received,
              currencyCode: account.currency,
            ),
          ),
        ],
      ),
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 2,
          ),
        ),
      ),
      error: (_, __) => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text('-', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

class _PayableStatsRow extends ConsumerWidget {
  final db.Account account;
  final AsyncValue<({double pending, double total, double paid})>? statsAsync;

  const _PayableStatsRow({
    required this.account,
    required this.statsAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (statsAsync == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 2,
          ),
        ),
      );
    }

    return statsAsync!.when(
      data: (stats) => Row(
        children: [
          Expanded(
            child: _CardStatItem(
              label: '待付',
              value: stats.pending,
              currencyCode: account.currency,
            ),
          ),
          Container(
            width: 1,
            height: 30.0.scaled(context, ref),
            color: Colors.white.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _CardStatItem(
              label: '总额',
              value: stats.total,
              currencyCode: account.currency,
            ),
          ),
          Container(
            width: 1,
            height: 30.0.scaled(context, ref),
            color: Colors.white.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _CardStatItem(
              label: '已付',
              value: stats.paid,
              currencyCode: account.currency,
            ),
          ),
        ],
      ),
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 2,
          ),
        ),
      ),
      error: (_, __) => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text('-', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

class DefaultAccountSelector extends ConsumerWidget {
  final List<db.Account> accounts;
  final Color primaryColor;
  final String type;

  const DefaultAccountSelector({
    super.key,
    required this.accounts,
    required this.primaryColor,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isIncome = type == 'income';
    final defaultAccountIdAsync = isIncome
        ? ref.watch(defaultIncomeAccountIdProvider)
        : ref.watch(defaultExpenseAccountIdProvider);

    return defaultAccountIdAsync.when(
      data: (defaultAccountId) {
        db.Account? defaultAccount;
        if (defaultAccountId != null) {
          defaultAccount =
              accounts.where((a) => a.id == defaultAccountId).firstOrNull;
        }

        final title = isIncome
            ? l10n.accountDefaultIncomeTitle
            : l10n.accountDefaultExpenseTitle;
        final description = isIncome
            ? l10n.accountDefaultIncomeDescription
            : l10n.accountDefaultExpenseDescription;

        return ListTile(
          dense: true,
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          subtitle: Text(
            defaultAccount != null
                ? l10n.accountDefaultSet(defaultAccount.name)
                : description,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                defaultAccount?.name ?? l10n.accountDefaultNone,
                style: TextStyle(
                  color: BeeTokens.textSecondary(context),
                  fontSize: 14,
                ),
              ),
              SizedBox(width: 4.0.scaled(context, ref)),
              Icon(
                Icons.chevron_right,
                color: BeeTokens.iconTertiary(context),
              ),
            ],
          ),
          onTap: () =>
              _showAccountPicker(context, ref, accounts, defaultAccountId),
        );
      },
      loading: () => ListTile(
        dense: true,
        title: Text(isIncome
            ? l10n.accountDefaultIncomeTitle
            : l10n.accountDefaultExpenseTitle),
        trailing: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showAccountPicker(
    BuildContext context,
    WidgetRef ref,
    List<db.Account> accounts,
    int? currentDefaultId,
  ) {
    final l10n = AppLocalizations.of(context);
    final isIncome = type == 'income';
    final title = isIncome
        ? l10n.accountDefaultIncomeTitle
        : l10n.accountDefaultExpenseTitle;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BeeTokens.surfaceElevated(context),
        title: Text(
          title,
          style: TextStyle(color: BeeTokens.textPrimary(context)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAccountOption(
                context,
                ref,
                title: l10n.accountDefaultNone,
                icon: Icons.block,
                iconColor: BeeTokens.iconSecondary(context),
                isSelected: currentDefaultId == null,
                onTap: () async {
                  if (isIncome) {
                    await ref
                        .read(defaultAccountSetterProvider)
                        .setDefaultIncomeAccountId(null);
                    ref.invalidate(defaultIncomeAccountIdProvider);
                  } else {
                    await ref
                        .read(defaultAccountSetterProvider)
                        .setDefaultExpenseAccountId(null);
                    ref.invalidate(defaultExpenseAccountIdProvider);
                  }
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              ...accounts.map((account) {
                final isSelected = account.id == currentDefaultId;
                return _buildAccountOption(
                  context,
                  ref,
                  title: account.name,
                  subtitle: getCurrencyName(account.currency, context),
                  icon: accountIconForType(account.type),
                  iconColor: accountColorForType(account.type, primaryColor),
                  isSelected: isSelected,
                  onTap: () async {
                    if (isIncome) {
                      await ref
                          .read(defaultAccountSetterProvider)
                          .setDefaultIncomeAccountId(account.id);
                      ref.invalidate(defaultIncomeAccountIdProvider);
                    } else {
                      await ref
                          .read(defaultAccountSetterProvider)
                          .setDefaultExpenseAccountId(account.id);
                      ref.invalidate(defaultExpenseAccountIdProvider);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountOption(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    String? subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? primaryColor : BeeTokens.textPrimary(context),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: BeeTokens.textTertiary(context),
              ),
            )
          : null,
      trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
      onTap: onTap,
    );
  }
}
