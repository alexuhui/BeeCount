import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../providers.dart';
import '../../providers/theme_providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../services/data/category_service.dart';
import '../../widgets/category_icon.dart';
import '../receivable_payable/receivable_edit_page.dart';
import '../receivable_payable/payable_edit_page.dart';
import '../transaction/transaction_editor_page.dart';

/// 账户详情页面
/// 显示账户的统计信息和相关交易
class AccountDetailPage extends ConsumerWidget {
  final db.Account account;

  const AccountDetailPage({
    super.key,
    required this.account,
  });

  bool get isReceivableAccount => account.type == 'receivable';
  bool get isPayableAccount => account.type == 'payable';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: account.name,
            subtitle: _getTypeLabel(context, account.type),
            showBack: true,
          ),
          Expanded(
            child: isReceivableAccount
                ? _ReceivableAccountContent(account: account)
                : isPayableAccount
                    ? _PayableAccountContent(account: account)
                    : _NormalAccountContent(account: account),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomButton(context, ref, primaryColor),
    );
  }

  Widget? _buildBottomButton(BuildContext context, WidgetRef ref, Color primaryColor) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(16.0.scaled(context, ref)),
        child: SizedBox(
          width: double.infinity,
          height: 48.0.scaled(context, ref),
          child: ElevatedButton.icon(
            onPressed: () => _onAddRecord(context, ref),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              '记录一笔',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onAddRecord(BuildContext context, WidgetRef ref) async {
    if (isReceivableAccount) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReceivableEditPage(account: account),
        ),
      );
    } else if (isPayableAccount) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PayableEditPage(account: account),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransactionEditorPage(
            initialKind: 'expense',
            initialAccountId: account.id,
          ),
        ),
      );
    }
  }

  String _getTypeLabel(BuildContext context, String type) {
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
}

/// 普通账户内容
class _NormalAccountContent extends ConsumerWidget {
  final db.Account account;

  const _NormalAccountContent({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final statsAsync = ref.watch(accountStatsProvider(account.id));
    final transactionsAsync = ref.watch(accountTransactionsProvider(account.id));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';
    final categoriesAsync = ref.watch(categoriesProvider);

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: 0,
        vertical: 16.0.scaled(context, ref),
      ),
      children: [
        SectionCard(
          child: statsAsync.when(
            data: (stats) => Padding(
              padding: EdgeInsets.all(12.0.scaled(context, ref)),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCell(
                      label: l10n.accountBalance,
                      value: stats.balance,
                      currencyCode: currencyCode,
                      color: stats.balance >= 0
                          ? BeeTokens.textPrimary(context)
                          : BeeTokens.error(context),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40.0.scaled(context, ref),
                    color: BeeTokens.border(context),
                  ),
                  Expanded(
                    child: _StatCell(
                      label: l10n.homeIncome,
                      value: stats.income,
                      currencyCode: currencyCode,
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
                      label: l10n.homeExpense,
                      value: stats.expense,
                      currencyCode: currencyCode,
                      color: BeeTokens.expenseColor(context, ref),
                    ),
                  ),
                ],
              ),
            ),
            loading: () => Center(
              child: Padding(
                padding: EdgeInsets.all(24.0.scaled(context, ref)),
                child: const CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: Text(
                '${l10n.commonError}: $err',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
        SizedBox(height: 8.0.scaled(context, ref)),
        SectionCard(
          child: transactionsAsync.when(
            data: (transactions) {
              if (transactions.isEmpty) {
                return Padding(
                  padding: EdgeInsets.all(32.0.scaled(context, ref)),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48.0.scaled(context, ref),
                          color: BeeTokens.textTertiary(context),
                        ),
                        SizedBox(height: 8.0.scaled(context, ref)),
                        Text(
                          l10n.accountNoTransactions,
                          style: TextStyle(
                            fontSize: 14,
                            color: BeeTokens.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.all(12.0.scaled(context, ref)),
                    child: Text(
                      l10n.accountTransactionHistory,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
                  ),
                  ...transactions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tx = entry.value;

                    return Column(
                      children: [
                        if (index > 0) BeeTokens.cardDivider(context),
                        _TransactionTile(
                          transaction: tx,
                          currencyCode: currencyCode,
                          primaryColor: primaryColor,
                          ledgers: ref.watch(ledgersStreamProvider).asData?.value ?? [],
                          categories: categoriesAsync.asData?.value ?? [],
                          currentAccountId: account.id,
                          onTap: () => _editTransaction(context, ref, tx),
                        ),
                      ],
                    );
                  }),
                ],
              );
            },
            loading: () => Center(
              child: Padding(
                padding: EdgeInsets.all(24.0.scaled(context, ref)),
                child: const CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: Text(
                '${l10n.commonError}: $err',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editTransaction(
      BuildContext context, WidgetRef ref, db.Transaction tx) async {
    final categoryAsync = tx.categoryId != null
        ? await ref.read(categoriesProvider.future)
        : null;
    final category = categoryAsync?.cast<db.Category?>().firstWhere(
          (c) => c?.id == tx.categoryId,
          orElse: () => null,
        );

    if (!context.mounted) return;
    await TransactionEditUtils.editTransaction(context, ref, tx, category);

    ref.invalidate(accountStatsProvider(account.id));
    ref.invalidate(accountTransactionsProvider(account.id));
  }
}

/// 应收款账户内容
class _ReceivableAccountContent extends ConsumerStatefulWidget {
  final db.Account account;

  const _ReceivableAccountContent({required this.account});

  @override
  ConsumerState<_ReceivableAccountContent> createState() => _ReceivableAccountContentState();
}

class _ReceivableAccountContentState extends ConsumerState<_ReceivableAccountContent> {
  String _filter = 'all'; // all, received, pending
  Map<String, bool> _expandedBorrowers = {}; // 借款人展开状态
  Map<int, double> _receivablePaidAmounts = {}; // 应收款已付款金额缓存

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final receivablesAsync = ref.watch(receivablesByAccountProvider(widget.account.id));
    final balanceAsync = ref.watch(receivableBalanceProvider(widget.account.id));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';
    final repo = ref.watch(repositoryProvider);

    // 加载所有应收款的已付款金额
    receivablesAsync.whenData((receivables) async {
      for (final r in receivables) {
        if (!_receivablePaidAmounts.containsKey(r.id)) {
          final paidAmount = await repo.getReceivablePaidAmount(r.id);
          if (mounted) {
            setState(() {
              _receivablePaidAmounts[r.id] = paidAmount;
            });
          }
        }
      }
    });

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: 0,
        vertical: 16.0.scaled(context, ref),
      ),
      children: [
        SectionCard(
          child: Padding(
            padding: EdgeInsets.all(16.0.scaled(context, ref)),
            child: Column(
              children: [
                Text(
                  '未收金额',
                  style: TextStyle(
                    fontSize: 14,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
                SizedBox(height: 8.0.scaled(context, ref)),
                balanceAsync.when(
                  data: (balance) => AmountText(
                    value: balance,
                    signed: false,
                    showCurrency: true,
                    currencyCode: currencyCode,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (_, __) => const Text('-'),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 8.0.scaled(context, ref)),
        SectionCard(
          child: receivablesAsync.when(
            data: (receivables) {
              // 过滤应收款
              final filteredReceivables = receivables.where((r) {
                if (_filter == 'all') return true;
                if (_filter == 'received') return r.isReceived;
                if (_filter == 'pending') return !r.isReceived;
                return true;
              }).toList();

              // 按借款人分组
              final groupedByBorrower = <String, List<db.Receivable>>{};
              for (final r in filteredReceivables) {
                final borrowerName = r.borrowerName;
                if (!groupedByBorrower.containsKey(borrowerName)) {
                  groupedByBorrower[borrowerName] = [];
                }
                groupedByBorrower[borrowerName]!.add(r);
              }

              // 按借款人名称排序
              final sortedBorrowers = groupedByBorrower.keys.toList()..sort();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 过滤开关 - 始终显示
                  Padding(
                    padding: EdgeInsets.all(12.0.scaled(context, ref)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '应收款记录',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
                        ),
                        Row(
                          children: [
                            _buildFilterChip(context, '全部', 'all'),
                            SizedBox(width: 8.0.scaled(context, ref)),
                            _buildFilterChip(context, '已收', 'received'),
                            SizedBox(width: 8.0.scaled(context, ref)),
                            _buildFilterChip(context, '未收', 'pending'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 记录列表或空状态
                  if (filteredReceivables.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(32.0.scaled(context, ref)),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48.0.scaled(context, ref),
                              color: BeeTokens.textTertiary(context),
                            ),
                            SizedBox(height: 8.0.scaled(context, ref)),
                            Text(
                              _filter == 'all' ? '暂无应收款记录' : 
                              _filter == 'received' ? '暂无已收款记录' : '暂无未收款记录',
                              style: TextStyle(
                                fontSize: 14,
                                color: BeeTokens.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...sortedBorrowers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final borrowerName = entry.value;
                    final borrowerReceivables = groupedByBorrower[borrowerName]!;
                    final isExpanded = _expandedBorrowers[borrowerName] ?? true;

                    // 计算该借款人的总金额和待收金额
                    double totalAmount = 0;
                    double pendingAmount = 0;
                    for (final r in borrowerReceivables) {
                      totalAmount += r.amount;
                      if (!r.isReceived) {
                        // 获取该应收款的已付款金额
                        final paidAmount = _receivablePaidAmounts[r.id] ?? 0.0;
                        pendingAmount += (r.amount - paidAmount);
                      }
                    }

                    return Column(
                      children: [
                        if (index > 0) BeeTokens.cardDivider(context),
                        // 借款人分组头部
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _expandedBorrowers[borrowerName] = !isExpanded;
                            });
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.0.scaled(context, ref),
                              vertical: 12.0.scaled(context, ref),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: BeeTokens.primary(context).withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                    size: 20,
                                    color: BeeTokens.primary(context),
                                  ),
                                ),
                                SizedBox(width: 12.0.scaled(context, ref)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        borrowerName,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: BeeTokens.textPrimary(context),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                                        child: Text(
                                          '共 ${borrowerReceivables.length} 笔，未收 ${pendingAmount.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: BeeTokens.textSecondary(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                AmountText(
                                  value: totalAmount,
                                  signed: false,
                                  showCurrency: false,
                                  currencyCode: currencyCode,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 展开的应收款列表
                        if (isExpanded)
                          ...borrowerReceivables.asMap().entries.map((receivableEntry) {
                            final receivableIndex = receivableEntry.key;
                            final r = receivableEntry.value;

                            return Column(
                              children: [
                                BeeTokens.cardDivider(context),
                                Padding(
                                  padding: EdgeInsets.only(left: 44.0.scaled(context, ref)),
                                  child: _ReceivableTile(
                                    receivable: r,
                                    currencyCode: currencyCode,
                                    onTap: () => _editReceivable(context, ref, r),
                                  ),
                                ),
                              ],
                            );
                          }),
                      ],
                    );
                  }),
                ],
              );
            },
            loading: () => Center(
              child: Padding(
                padding: EdgeInsets.all(24.0.scaled(context, ref)),
                child: const CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: Text(
                '${l10n.commonError}: $err',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filter = value;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12.0.scaled(context, ref),
          vertical: 4.0.scaled(context, ref),
        ),
        decoration: BoxDecoration(
          color: isSelected ? BeeTokens.primary(context) : BeeTokens.surfaceSecondary(context),
          borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : BeeTokens.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Future<void> _editReceivable(
      BuildContext context, WidgetRef ref, db.Receivable r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReceivableEditPage(account: widget.account, receivable: r),
      ),
    );
    ref.invalidate(receivablesByAccountProvider(widget.account.id));
    ref.invalidate(receivableBalanceProvider(widget.account.id));
  }
}

/// 应付款账户内容
class _PayableAccountContent extends ConsumerStatefulWidget {
  final db.Account account;

  const _PayableAccountContent({required this.account});

  @override
  ConsumerState<_PayableAccountContent> createState() => _PayableAccountContentState();
}

class _PayableAccountContentState extends ConsumerState<_PayableAccountContent> {
  String _filter = 'all'; // all, paid, pending
  Map<String, bool> _expandedPayees = {}; // 收款人展开状态
  Map<int, double> _payablePaidAmounts = {}; // 应付款已付款金额缓存

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final payablesAsync = ref.watch(payablesByAccountProvider(widget.account.id));
    final balanceAsync = ref.watch(payableBalanceProvider(widget.account.id));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';
    final repo = ref.watch(repositoryProvider);

    // 加载所有应付款的已付款金额
    payablesAsync.whenData((payables) async {
      for (final p in payables) {
        if (!_payablePaidAmounts.containsKey(p.id)) {
          final paidAmount = await repo.getPayablePaidAmount(p.id);
          if (mounted) {
            setState(() {
              _payablePaidAmounts[p.id] = paidAmount;
            });
          }
        }
      }
    });

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: 0,
        vertical: 16.0.scaled(context, ref),
      ),
      children: [
        SectionCard(
          child: Padding(
            padding: EdgeInsets.all(16.0.scaled(context, ref)),
            child: Column(
              children: [
                Text(
                  '未付金额',
                  style: TextStyle(
                    fontSize: 14,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
                SizedBox(height: 8.0.scaled(context, ref)),
                balanceAsync.when(
                  data: (balance) => AmountText(
                    value: balance,
                    signed: false,
                    showCurrency: true,
                    currencyCode: currencyCode,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (_, __) => const Text('-'),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 8.0.scaled(context, ref)),
        SectionCard(
          child: payablesAsync.when(
            data: (payables) {
              // 过滤应付款
              final filteredPayables = payables.where((p) {
                if (_filter == 'all') return true;
                if (_filter == 'paid') return p.isPaid;
                if (_filter == 'pending') return !p.isPaid;
                return true;
              }).toList();

              // 按收款人分组
              final groupedByPayee = <String, List<db.Payable>>{};
              for (final p in filteredPayables) {
                final payeeName = p.payeeName;
                if (!groupedByPayee.containsKey(payeeName)) {
                  groupedByPayee[payeeName] = [];
                }
                groupedByPayee[payeeName]!.add(p);
              }

              // 按收款人名称排序
              final sortedPayees = groupedByPayee.keys.toList()..sort();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 过滤开关 - 始终显示
                  Padding(
                    padding: EdgeInsets.all(12.0.scaled(context, ref)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '应付款记录',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
                        ),
                        Row(
                          children: [
                            _buildFilterChip(context, '全部', 'all'),
                            SizedBox(width: 8.0.scaled(context, ref)),
                            _buildFilterChip(context, '已付', 'paid'),
                            SizedBox(width: 8.0.scaled(context, ref)),
                            _buildFilterChip(context, '未付', 'pending'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 记录列表或空状态
                  if (filteredPayables.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(32.0.scaled(context, ref)),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48.0.scaled(context, ref),
                              color: BeeTokens.textTertiary(context),
                            ),
                            SizedBox(height: 8.0.scaled(context, ref)),
                            Text(
                              _filter == 'all' ? '暂无应付款记录' : 
                              _filter == 'paid' ? '暂无已付款记录' : '暂无未付款记录',
                              style: TextStyle(
                                fontSize: 14,
                                color: BeeTokens.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...sortedPayees.asMap().entries.map((entry) {
                    final index = entry.key;
                    final payeeName = entry.value;
                    final payeePayables = groupedByPayee[payeeName]!;
                    final isExpanded = _expandedPayees[payeeName] ?? true;

                    // 计算该收款人的总金额和待付金额
                    double totalAmount = 0;
                    double pendingAmount = 0;
                    for (final p in payeePayables) {
                      totalAmount += p.amount;
                      if (!p.isPaid) {
                        // 获取该应付款的已付款金额
                        final paidAmount = _payablePaidAmounts[p.id] ?? 0.0;
                        pendingAmount += (p.amount - paidAmount);
                      }
                    }

                    return Column(
                      children: [
                        if (index > 0) BeeTokens.cardDivider(context),
                        // 收款人分组头部
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _expandedPayees[payeeName] = !isExpanded;
                            });
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.0.scaled(context, ref),
                              vertical: 12.0.scaled(context, ref),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: BeeTokens.primary(context).withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                    size: 20,
                                    color: BeeTokens.primary(context),
                                  ),
                                ),
                                SizedBox(width: 12.0.scaled(context, ref)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        payeeName,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: BeeTokens.textPrimary(context),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                                        child: Text(
                                          '共 ${payeePayables.length} 笔，未付 ${pendingAmount.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: BeeTokens.textSecondary(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                AmountText(
                                  value: totalAmount,
                                  signed: false,
                                  showCurrency: false,
                                  currencyCode: currencyCode,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 展开的应付款列表
                        if (isExpanded)
                          ...payeePayables.asMap().entries.map((payableEntry) {
                            final payableIndex = payableEntry.key;
                            final p = payableEntry.value;

                            return Column(
                              children: [
                                BeeTokens.cardDivider(context),
                                Padding(
                                  padding: EdgeInsets.only(left: 44.0.scaled(context, ref)),
                                  child: _PayableTile(
                                    payable: p,
                                    currencyCode: currencyCode,
                                    onTap: () => _editPayable(context, ref, p),
                                  ),
                                ),
                              ],
                            );
                          }),
                      ],
                    );
                  }),
                ],
              );
            },
            loading: () => Center(
              child: Padding(
                padding: EdgeInsets.all(24.0.scaled(context, ref)),
                child: const CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: Text(
                '${l10n.commonError}: $err',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filter = value;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12.0.scaled(context, ref),
          vertical: 4.0.scaled(context, ref),
        ),
        decoration: BoxDecoration(
          color: isSelected ? BeeTokens.primary(context) : BeeTokens.surfaceSecondary(context),
          borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : BeeTokens.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Future<void> _editPayable(
      BuildContext context, WidgetRef ref, db.Payable p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PayableEditPage(account: widget.account, payable: p),
      ),
    );
    ref.invalidate(payablesByAccountProvider(widget.account.id));
    ref.invalidate(payableBalanceProvider(widget.account.id));
  }
}

/// 应收款记录列表项
class _ReceivableTile extends ConsumerWidget {
  final db.Receivable receivable;
  final String currencyCode;
  final VoidCallback onTap;

  const _ReceivableTile({
    required this.receivable,
    required this.currencyCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final fromAccountAsync = receivable.fromAccountId != null ? ref.watch(accountByIdProvider(receivable.fromAccountId!)) : null;
    final repo = ref.watch(repositoryProvider);
    final paidAmountFuture = repo.getReceivablePaidAmount(receivable.id);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12.0.scaled(context, ref),
          vertical: 12.0.scaled(context, ref),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: receivable.isReceived
                    ? Colors.green.withValues(alpha: 0.12)
                    : primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                receivable.isReceived ? Icons.check : Icons.currency_exchange,
                size: 18,
                color: receivable.isReceived ? Colors.green : primaryColor,
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
                          receivable.borrowerName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: BeeTokens.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (receivable.isReceived)
                        Container(
                          margin: EdgeInsets.only(left: 8.0.scaled(context, ref)),
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.0.scaled(context, ref),
                            vertical: 2.0.scaled(context, ref),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
                          ),
                          child: const Text(
                            '已收款',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                    child: Text(
                      '借款账户: ${fromAccountAsync?.value?.name ?? '-'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textSecondary(context),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                    child: Text(
                      _formatDate(receivable.borrowDate),
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textTertiary(context),
                      ),
                    ),
                  ),
                  FutureBuilder<double>(
                    future: paidAmountFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final paidAmount = snapshot.data!;
                        final pendingAmount = receivable.amount - paidAmount;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(top: 4.0.scaled(context, ref)),
                              child: Row(
                                children: [
                                  Text(
                                    '总额: ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BeeTokens.textTertiary(context),
                                    ),
                                  ),
                                  Text(
                                    '¥ ${receivable.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BeeTokens.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                              child: Row(
                                children: [
                                  Text(
                                    '已收: ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BeeTokens.textTertiary(context),
                                    ),
                                  ),
                                  Text(
                                    '¥ ${paidAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                              child: Row(
                                children: [
                                  Text(
                                    '待收: ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BeeTokens.textTertiary(context),
                                    ),
                                  ),
                                  Text(
                                    '¥ ${pendingAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: pendingAmount > 0 ? Colors.red : BeeTokens.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

/// 应付款记录列表项
class _PayableTile extends ConsumerWidget {
  final db.Payable payable;
  final String currencyCode;
  final VoidCallback onTap;

  const _PayableTile({
    required this.payable,
    required this.currencyCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final toAccountAsync = payable.toAccountId != null ? ref.watch(accountByIdProvider(payable.toAccountId!)) : null;
    final repo = ref.watch(repositoryProvider);
    final paidAmountFuture = repo.getPayablePaidAmount(payable.id);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12.0.scaled(context, ref),
          vertical: 12.0.scaled(context, ref)),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: payable.isPaid
                    ? Colors.green.withValues(alpha: 0.12)
                    : primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                payable.isPaid ? Icons.check : Icons.currency_exchange,
                size: 18,
                color: payable.isPaid ? Colors.green : primaryColor,
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
                          payable.payeeName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: BeeTokens.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (payable.isPaid)
                        Container(
                          margin: EdgeInsets.only(left: 8.0.scaled(context, ref)),
                          padding: EdgeInsets.symmetric(horizontal: 6.0.scaled(context, ref),
                            vertical: 2.0.scaled(context, ref),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
                          ),
                          child: const Text(
                            '已还款',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                    child: Text(
                      '入账账户: ${toAccountAsync?.value?.name ?? '-'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textSecondary(context),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                    child: Text(
                      _formatDate(payable.payDate),
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textTertiary(context),
                      ),
                    ),
                  ),
                  FutureBuilder<double>(
                    future: paidAmountFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final paidAmount = snapshot.data!;
                        final pendingAmount = payable.amount - paidAmount;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(top: 4.0.scaled(context, ref)),
                              child: Row(
                                children: [
                                  Text(
                                    '总额: ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BeeTokens.textTertiary(context),
                                    ),
                                  ),
                                  Text(
                                    '¥ ${payable.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BeeTokens.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                              child: Row(
                                children: [
                                  Text(
                                    '已付: ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BeeTokens.textTertiary(context),
                                    ),
                                  ),
                                  Text(
                                    '¥ ${paidAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                              child: Row(
                                children: [
                                  Text(
                                    '待付: ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BeeTokens.textTertiary(context),
                                    ),
                                  ),
                                  Text(
                                    '¥ ${pendingAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: pendingAmount > 0 ? Colors.red : BeeTokens.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

/// 统计单元格
class _StatCell extends ConsumerWidget {
  final String label;
  final double value;
  final String currencyCode;
  final Color color;

  const _StatCell({
    required this.label,
    required this.value,
    required this.currencyCode,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        AmountText(
          value: value,
          signed: false,
          showCurrency: true,
          useCompactFormat: ref.watch(compactAmountProvider),
          currencyCode: currencyCode,
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
        ),
      ],
    );
  }
}

/// 交易列表项
class _TransactionTile extends ConsumerWidget {
  final db.Transaction transaction;
  final String currencyCode;
  final Color primaryColor;
  final List<db.Ledger> ledgers;
  final List<db.Category> categories;
  final VoidCallback onTap;
  final int? currentAccountId;

  const _TransactionTile({
    required this.transaction,
    required this.currencyCode,
    required this.primaryColor,
    required this.ledgers,
    required this.categories,
    required this.onTap,
    this.currentAccountId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color amountColor;
    final l10n = AppLocalizations.of(context);
    final transferCategory = ref.watch(transferCategoryProvider).valueOrNull;

    bool isTransferOut = false;
    bool isTransferIn = false;
    if (transaction.type == 'transfer' && currentAccountId != null) {
      isTransferOut = transaction.accountId == currentAccountId;
      isTransferIn = transaction.toAccountId == currentAccountId;
    }

    switch (transaction.type) {
      case 'income':
        amountColor = BeeTokens.incomeColor(context, ref);
        break;
      case 'expense':
        amountColor = BeeTokens.expenseColor(context, ref);
        break;
      case 'transfer':
        amountColor = isTransferOut ? BeeTokens.expenseColor(context, ref) : BeeTokens.incomeColor(context, ref);
        break;
      default:
        amountColor = BeeTokens.textPrimary(context);
    }

    final category = transaction.type == 'transfer'
        ? transferCategory
        : (transaction.categoryId != null
            ? categories.cast<db.Category?>().firstWhere(
                  (c) => c?.id == transaction.categoryId,
                  orElse: () => null,
                )
            : null);

    String displayTitle;
    String? displaySubtitle;

    if (transaction.type == 'transfer') {
      if (transaction.note?.isNotEmpty == true) {
        displayTitle = transaction.note!;
      } else {
        displayTitle = l10n.transferTitle;
      }

      if (isTransferOut && transaction.toAccountId != null) {
        final toAccountAsync = ref.watch(accountByIdProvider(transaction.toAccountId!));
        final toAccountName = toAccountAsync.value?.name;
        if (toAccountName != null) {
          displaySubtitle = '${l10n.transferToPrefix} $toAccountName';
        }
      } else if (isTransferIn && transaction.accountId != null) {
        final fromAccountAsync = ref.watch(accountByIdProvider(transaction.accountId!));
        final fromAccountName = fromAccountAsync.value?.name;
        if (fromAccountName != null) {
          displaySubtitle = '${l10n.transferFromPrefix} $fromAccountName';
        }
      }
    } else {
      if (transaction.note?.isNotEmpty == true) {
        displayTitle = transaction.note!;
      } else if (category != null) {
        displayTitle = category.name;
      } else {
        displayTitle = transaction.type == 'income' ? l10n.homeIncome : l10n.homeExpense;
      }
    }

    final ledger = ledgers.cast<db.Ledger?>().firstWhere(
          (l) => l?.id == transaction.ledgerId,
          orElse: () => null,
        );
    String ledgerName = ledger?.name ?? '';
    if (ledgerName == 'Default Ledger') {
      ledgerName = l10n.ledgersDefaultLedgerName;
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12.0.scaled(context, ref),
          vertical: 12.0.scaled(context, ref),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: CategoryIconWidget(
                category: category,
                size: 18,
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
                          displayTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: BeeTokens.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ledgerName.isNotEmpty) ...[
                        SizedBox(width: 6.0.scaled(context, ref)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.0.scaled(context, ref),
                            vertical: 2.0.scaled(context, ref),
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
                          ),
                          child: Text(
                            ledgerName,
                            style: TextStyle(
                              fontSize: 11,
                              color: primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (displaySubtitle != null)
                    Padding(
                      padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                      child: Text(
                        displaySubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                    child: Text(
                      _formatDate(transaction.happenedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textTertiary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AmountText(
              value: transaction.type == 'expense'
                  ? -transaction.amount
                  : transaction.type == 'transfer'
                      ? (isTransferOut ? -transaction.amount : transaction.amount)
                      : transaction.amount,
              signed: true,
              showCurrency: false,
              currencyCode: currencyCode,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();

    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

// Provider: 账户相关的交易列表
final accountTransactionsProvider = StreamProvider.family
    .autoDispose<List<db.Transaction>, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchAccountTransactions(accountId);
});

// Provider: 应收款列表
final receivablesByAccountProvider = StreamProvider.family
    .autoDispose<List<db.Receivable>, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchReceivablesByAccountId(accountId);
});

// Provider: 应收款余额
final receivableBalanceProvider = FutureProvider.family
    <double, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.getReceivableBalance(accountId);
});

// Provider: 应收款统计
final receivableStatsProvider = FutureProvider.family
    <({double pending, double total, double received}), int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.getReceivableStats(accountId);
});

// Provider: 应付款列表
final payablesByAccountProvider = StreamProvider.family
    .autoDispose<List<db.Payable>, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchPayablesByAccountId(accountId);
});

// Provider: 应付款余额
final payableBalanceProvider = FutureProvider.family
    <double, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.getPayableBalance(accountId);
});

// Provider: 应付款统计
final payableStatsProvider = FutureProvider.family
    <({double pending, double total, double paid}), int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.getPayableStats(accountId);
});
