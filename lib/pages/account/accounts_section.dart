import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/currencies.dart';
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
  ref.invalidate(statsRefreshProvider);
}

/// 账户主体：默认收支账户、净资产、可展开账户列表
class AccountsBody extends ConsumerStatefulWidget {
  const AccountsBody({super.key});

  @override
  ConsumerState<AccountsBody> createState() => _AccountsBodyState();
}

class _AccountsBodyState extends ConsumerState<AccountsBody> {
  int? _expandedAccountId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final totalStatsAsync = ref.watch(allAccountsTotalStatsProvider);
    final allStatsAsync = ref.watch(allAccountStatsProvider);
    final primaryColor = ref.watch(primaryColorProvider);

    return accountsAsync.when(
      data: (accounts) {
        if (accounts.isEmpty) {
          return _EmptyAccounts(
            primaryColor: primaryColor,
            onAdd: () => openAddAccount(context, ref),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DefaultAccountSelector(
              accounts: accounts,
              primaryColor: primaryColor,
              type: 'expense',
            ),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: BeeTokens.divider(context),
            ),
            _DefaultAccountSelector(
              accounts: accounts,
              primaryColor: primaryColor,
              type: 'income',
            ),
            Divider(
              height: 1,
              color: BeeTokens.divider(context),
            ),
            totalStatsAsync.when(
              data: (stats) => Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16.0.scaled(context, ref),
                  vertical: 12.0.scaled(context, ref),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCell(
                        label: l10n.accountTotalBalance,
                        value: stats.totalBalance,
                        color: stats.totalBalance >= 0
                            ? BeeTokens.textPrimary(context)
                            : Colors.red,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40.0.scaled(context, ref),
                      color: BeeTokens.border(context),
                    ),
                    Expanded(
                      child: _StatCell(
                        label: l10n.accountTotalIncome,
                        value: stats.totalIncome,
                        color: BeeTokens.incomeColor(context, ref),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40.0.scaled(context, ref),
                      color: BeeTokens.border(context),
                    ),
                    Expanded(
                      child: _StatCell(
                        label: l10n.accountTotalExpense,
                        value: stats.totalExpense,
                        color: BeeTokens.expenseColor(context, ref),
                      ),
                    ),
                  ],
                ),
              ),
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
            ...accounts.map((account) {
              final stats = allStatsAsync.asData?.value[account.id];
              final balance = stats?.balance ?? account.initialBalance;
              final expanded = _expandedAccountId == account.id;
              return Padding(
                padding: EdgeInsets.only(
                  left: 8.0.scaled(context, ref),
                  right: 8.0.scaled(context, ref),
                  bottom: 10.0.scaled(context, ref),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? _ExpandedAccountCard(
                          account: account,
                          primaryColor: primaryColor,
                          stats: stats,
                          onCollapse: () =>
                              setState(() => _expandedAccountId = null),
                          onEdit: () => openEditAccount(context, ref, account),
                        )
                      : _CompactAccountBar(
                          account: account,
                          balance: balance,
                          primaryColor: primaryColor,
                          onExpand: () =>
                              setState(() => _expandedAccountId = account.id),
                        ),
                ),
              );
            }),
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
          textAlign: TextAlign.center,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeColor = accountColorForType(account.type, primaryColor);
    final receivableStatsAsync =
        isReceivableAccount ? ref.watch(receivableStatsProvider(account.id)) : null;
    final payableStatsAsync =
        isPayableAccount ? ref.watch(payableStatsProvider(account.id)) : null;

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

class _DefaultAccountSelector extends ConsumerWidget {
  final List<db.Account> accounts;
  final Color primaryColor;
  final String type;

  const _DefaultAccountSelector({
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
