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
import '../../utils/invest_tx.dart';
import '../../services/billing/post_processor.dart';
import '../../services/data/category_service.dart';
import '../../widgets/category_icon.dart';
import '../receivable_payable/receivable_edit_page.dart';
import '../receivable_payable/payable_edit_page.dart';
import '../receivable_payable/receivable_record_detail_page.dart';
import '../receivable_payable/payable_record_detail_page.dart';
import '../transaction/transaction_editor_page.dart';
import 'investment_record_page.dart';
import 'investment_transfer_page.dart';

/// 与 [ReceivablePayableRepository.getReceivableOutstandingMapForAccount] 中剩余未收/未付比较
const double _kReceivablePayableOutstandingEps = 1e-6;

Widget _swipeToDelete({
  required Key dismissKey,
  required Future<bool> Function() onConfirmDelete,
  required Widget child,
}) {
  return Dismissible(
    key: dismissKey,
    direction: DismissDirection.endToStart,
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 16),
      color: Colors.red,
      child: const Icon(Icons.delete, color: Colors.white),
    ),
    confirmDismiss: (_) => onConfirmDelete(),
    onDismissed: (_) {},
    child: child,
  );
}

Future<bool> _confirmDeleteRecord(
  BuildContext context, {
  required Future<void> Function() delete,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await AppDialog.confirm<bool>(
        context,
        title: l10n.deleteConfirmTitle,
        message: l10n.deleteConfirmMessage,
      ) ??
      false;
  if (!confirmed) return false;
  try {
    await delete();
    if (context.mounted) {
      showToast(context, l10n.ledgersDeleted);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showToast(context, '${l10n.commonError}: $e');
    }
    return false;
  }
}

void _afterTransactionDeleted(WidgetRef ref, {required int accountId}) {
  ref.invalidate(accountStatsProvider(accountId));
  ref.invalidate(accountTransactionsProvider(accountId));
  ref.invalidate(investmentPeriodStatsProvider);
  final curLedger = ref.read(currentLedgerIdProvider);
  ref.invalidate(countsForLedgerProvider(curLedger));
  ref.read(statsRefreshProvider.notifier).state++;
  PostProcessor.sync(ref, ledgerId: curLedger);
}

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
  bool get isInvestmentAccount => InvestTx.isInvestmentAccount(account.type);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);

    return BeeScaffold(
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
                    : isInvestmentAccount
                        ? _InvestmentAccountContent(account: account)
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
            label: Text(
              isInvestmentAccount
                  ? AppLocalizations.of(context).investActionsTitle
                  : '记录一笔',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
    } else if (isInvestmentAccount) {
      await _showInvestmentActions(context, ref);
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransactionEditorPage(
            initialKind: 'expense',
            quickAdd: true,
            initialAccountId: account.id,
          ),
        ),
      );
    }
  }

  Future<void> _showInvestmentActions(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.call_received),
                title: Text(l10n.investTransferIn),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvestmentTransferPage(
                        investmentAccountId: account.id,
                        transferIn: true,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.call_made),
                title: Text(l10n.investTransferOut),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvestmentTransferPage(
                        investmentAccountId: account.id,
                        transferIn: false,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.insights),
                title: Text(l10n.investMarkToMarket),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvestmentRecordPage(
                        account: account,
                        kind: InvestmentRecordKind.markToMarket,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.trending_up),
                title: Text(l10n.investRecordPnl),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvestmentRecordPage(
                        account: account,
                        kind: InvestmentRecordKind.manual,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: Text(l10n.investDividend),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvestmentRecordPage(
                        account: account,
                        kind: InvestmentRecordKind.dividend,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
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
}

class _AccountMonthGroup {
  final int year;
  final int month;
  final List<db.Transaction> transactions;
  final double inflow;
  final double outflow;
  final double endBalance;

  const _AccountMonthGroup({
    required this.year,
    required this.month,
    required this.transactions,
    required this.inflow,
    required this.outflow,
    required this.endBalance,
  });

  String get key => '$year-$month';
}

List<_AccountMonthGroup> _groupAccountTransactionsByMonth({
  required List<db.Transaction> transactions,
  required int accountId,
  required double initialBalance,
}) {
  if (transactions.isEmpty) return const [];

  final monthOrder = <String>[];
  final byMonth = <String, List<db.Transaction>>{};
  for (final tx in transactions) {
    final local = tx.happenedAt.toLocal();
    final key = '${local.year}-${local.month}';
    final bucket = byMonth.putIfAbsent(key, () {
      monthOrder.add(key);
      return <db.Transaction>[];
    });
    bucket.add(tx);
  }

  final chronological = [...transactions]..sort((a, b) {
      final byTime = a.happenedAt.compareTo(b.happenedAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });

  var running = initialBalance;
  final endBalanceByKey = <String, double>{};
  final inflowByKey = <String, double>{};
  final outflowByKey = <String, double>{};

  for (final tx in chronological) {
    final local = tx.happenedAt.toLocal();
    final key = '${local.year}-${local.month}';
    final flow = _accountTxFlow(tx, accountId);
    inflowByKey[key] = (inflowByKey[key] ?? 0) + flow.inflow;
    outflowByKey[key] = (outflowByKey[key] ?? 0) + flow.outflow;
    running = InvestTx.applyToBalance(
      balance: running,
      type: tx.type,
      amount: tx.amount,
      accountId: accountId,
      txAccountId: tx.accountId,
      txToAccountId: tx.toAccountId,
    );
    endBalanceByKey[key] = running;
  }

  return [
    for (final key in monthOrder)
      _AccountMonthGroup(
        year: int.parse(key.split('-').first),
        month: int.parse(key.split('-').last),
        transactions: byMonth[key]!,
        inflow: inflowByKey[key] ?? 0,
        outflow: outflowByKey[key] ?? 0,
        endBalance: endBalanceByKey[key] ?? initialBalance,
      ),
  ];
}

double _accountCurrentBalance({
  required List<db.Transaction> transactions,
  required int accountId,
  required double initialBalance,
}) {
  var running = initialBalance;
  final chronological = [...transactions]..sort((a, b) {
      final byTime = a.happenedAt.compareTo(b.happenedAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
  for (final tx in chronological) {
    running = InvestTx.applyToBalance(
      balance: running,
      type: tx.type,
      amount: tx.amount,
      accountId: accountId,
      txAccountId: tx.accountId,
      txToAccountId: tx.toAccountId,
    );
  }
  return running;
}

({double inflow, double outflow}) _accountTxFlow(
  db.Transaction tx,
  int accountId,
) {
  if (tx.accountId == accountId) {
    switch (tx.type) {
      case 'income':
      case InvestTx.gain:
        return (inflow: tx.amount, outflow: 0);
      case 'expense':
      case InvestTx.loss:
      case 'transfer':
        return (inflow: 0, outflow: tx.amount);
      default:
        return (inflow: 0, outflow: 0);
    }
  } else if (tx.toAccountId == accountId && tx.type == 'transfer') {
    return (inflow: tx.amount, outflow: 0);
  }
  return (inflow: 0, outflow: 0);
}

/// 普通账户内容
class _NormalAccountContent extends ConsumerStatefulWidget {
  final db.Account account;

  const _NormalAccountContent({required this.account});

  @override
  ConsumerState<_NormalAccountContent> createState() =>
      _NormalAccountContentState();
}

class _NormalAccountContentState extends ConsumerState<_NormalAccountContent> {
  final Set<String> _expandedMonths = {};

  db.Account get account => widget.account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final transactionsAsync = ref.watch(accountTransactionsProvider(account.id));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';
    final categoriesAsync = ref.watch(categoriesProvider);
    final statsMap = ref.watch(allAccountStatsProvider).asData?.value;
    final fallbackBalance =
        statsMap?[account.id]?.balance ?? account.initialBalance;

    Widget balanceCard(double balance) {
      return SectionCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0.scaled(context, ref)),
          child: _StatCell(
            label: l10n.accountBalance,
            value: balance,
            currencyCode: currencyCode,
            color: balance >= 0
                ? BeeTokens.textPrimary(context)
                : BeeTokens.error(context),
            valueSize: 28,
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: 0,
        vertical: 16.0.scaled(context, ref),
      ),
      children: [
        ...transactionsAsync.when(
          data: (transactions) {
            final currentBalance = transactions.isEmpty
                ? fallbackBalance
                : _accountCurrentBalance(
                    transactions: transactions,
                    accountId: account.id,
                    initialBalance: account.initialBalance,
                  );
            if (transactions.isEmpty) {
              return [
                balanceCard(currentBalance),
                SizedBox(height: 8.0.scaled(context, ref)),
                SectionCard(
                  child: Padding(
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
                  ),
                ),
              ];
            }

            final months = _groupAccountTransactionsByMonth(
              transactions: transactions,
              accountId: account.id,
              initialBalance: account.initialBalance,
            );
            final ledgers =
                ref.watch(ledgersStreamProvider).asData?.value ?? [];
            final categories = categoriesAsync.asData?.value ?? [];

            return [
              balanceCard(currentBalance),
              SizedBox(height: 8.0.scaled(context, ref)),
              for (var i = 0; i < months.length; i++) ...[
                if (i > 0) SizedBox(height: 8.0.scaled(context, ref)),
                _AccountMonthCard(
                  group: months[i],
                  expanded: _expandedMonths.contains(months[i].key),
                  currencyCode: currencyCode,
                  primaryColor: primaryColor,
                  ledgers: ledgers,
                  categories: categories,
                  accountId: account.id,
                  onToggle: () {
                    setState(() {
                      if (!_expandedMonths.remove(months[i].key)) {
                        _expandedMonths.add(months[i].key);
                      }
                    });
                  },
                  onEditTransaction: (tx) => _editTransaction(context, ref, tx),
                ),
              ],
            ];
          },
          loading: () => [
            balanceCard(fallbackBalance),
            SizedBox(height: 8.0.scaled(context, ref)),
            Center(
              child: Padding(
                padding: EdgeInsets.all(24.0.scaled(context, ref)),
                child: const CircularProgressIndicator(),
              ),
            ),
          ],
          error: (err, stack) => [
            balanceCard(fallbackBalance),
            Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: Text(
                '${l10n.commonError}: $err',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editTransaction(
      BuildContext context, WidgetRef ref, db.Transaction tx) async {
    final currencyCode =
        ref.read(currentLedgerProvider).asData?.value?.currency ?? 'CNY';

    if (tx.receivableId != null) {
      final rec =
          await ref.read(repositoryProvider).getReceivableById(tx.receivableId!);
      if (!context.mounted) return;
      if (rec != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceivableRecordDetailPage(
              receivable: rec,
              currencyCode: currencyCode,
            ),
          ),
        );
        ref.invalidate(accountStatsProvider(account.id));
        ref.invalidate(accountTransactionsProvider(account.id));
        return;
      }
    }
    if (tx.payableId != null) {
      final pay =
          await ref.read(repositoryProvider).getPayableById(tx.payableId!);
      if (!context.mounted) return;
      if (pay != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PayableRecordDetailPage(
              payable: pay,
              currencyCode: currencyCode,
            ),
          ),
        );
        ref.invalidate(accountStatsProvider(account.id));
        ref.invalidate(accountTransactionsProvider(account.id));
        return;
      }
    }

    final categoryAsync = tx.categoryId != null
        ? await ref.read(categoriesProvider.future)
        : null;
    final category = categoryAsync?.cast<db.Category?>().firstWhere(
          (c) => c?.id == tx.categoryId,
          orElse: () => null,
        );

    if (!context.mounted) return;
    if (InvestTx.isPnlType(tx.type)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvestmentRecordPage(
            account: account,
            kind: InvestmentRecordKind.edit,
            editing: tx,
          ),
        ),
      );
    } else {
      await TransactionEditUtils.editTransaction(context, ref, tx, category);
    }

    ref.invalidate(accountStatsProvider(account.id));
    ref.invalidate(accountTransactionsProvider(account.id));
  }
}

/// 理财账户详情：市值、区间盈亏、流水
class _InvestmentAccountContent extends ConsumerStatefulWidget {
  final db.Account account;

  const _InvestmentAccountContent({required this.account});

  @override
  ConsumerState<_InvestmentAccountContent> createState() =>
      _InvestmentAccountContentState();
}

class _InvestmentAccountContentState
    extends ConsumerState<_InvestmentAccountContent> {
  String _scope = 'month'; // month | year | custom
  late DateTime _month;
  late int _year;
  DateTime? _customFrom;
  DateTime? _customTo;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _year = now.year;
  }

  ({DateTime from, DateTime to}) _range() {
    if (_scope == 'year') {
      return (from: DateTime(_year, 1, 1), to: DateTime(_year + 1, 1, 1));
    }
    if (_scope == 'custom' && _customFrom != null && _customTo != null) {
      final from = DateTime(_customFrom!.year, _customFrom!.month, _customFrom!.day);
      final to = DateTime(_customTo!.year, _customTo!.month, _customTo!.day)
          .add(const Duration(days: 1));
      return (from: from, to: to);
    }
    return (
      from: DateTime(_month.year, _month.month, 1),
      to: DateTime(_month.year, _month.month + 1, 1),
    );
  }

  String _periodLabel() {
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (_scope == 'year') {
      return '$_year';
    }
    if (_scope == 'custom' && _customFrom != null && _customTo != null) {
      return '${ymd(_customFrom!)} – ${ymd(_customTo!)}';
    }
    return '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  }

  Future<void> _pickPeriod() async {
    if (_scope == 'year') {
      final picked = await showWheelDatePicker(
        context,
        initial: DateTime(_year),
        mode: WheelDatePickerMode.y,
      );
      if (picked != null && mounted) {
        setState(() => _year = picked.year);
      }
      return;
    }
    if (_scope == 'custom') {
      final from = await showWheelDatePicker(
        context,
        initial: _customFrom ?? _month,
      );
      if (!mounted) return;
      final to = await showWheelDatePicker(
        context,
        initial: _customTo ?? DateTime.now(),
      );
      if (from != null && to != null && mounted) {
        setState(() {
          _customFrom = from;
          _customTo = to;
        });
      }
      return;
    }
    final picked = await showWheelDatePicker(
      context,
      initial: _month,
      mode: WheelDatePickerMode.ym,
    );
    if (picked != null && mounted) {
      setState(() => _month = DateTime(picked.year, picked.month, 1));
    }
  }

  Future<void> _editTransaction(
      BuildContext context, WidgetRef ref, db.Transaction tx) async {
    if (InvestTx.isPnlType(tx.type)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvestmentRecordPage(
            account: widget.account,
            kind: InvestmentRecordKind.edit,
            editing: tx,
          ),
        ),
      );
    } else {
      final categoryAsync = tx.categoryId != null
          ? await ref.read(categoriesProvider.future)
          : null;
      final category = categoryAsync?.cast<db.Category?>().firstWhere(
            (c) => c?.id == tx.categoryId,
            orElse: () => null,
          );
      if (!context.mounted) return;
      await TransactionEditUtils.editTransaction(context, ref, tx, category);
    }
    ref.invalidate(accountStatsProvider(widget.account.id));
    ref.invalidate(accountTransactionsProvider(widget.account.id));
    ref.read(statsRefreshProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final range = _range();
    final statsAsync = ref.watch(investmentPeriodStatsProvider((
      accountId: widget.account.id,
      from: range.from,
      to: range.to,
    )));
    final transactionsAsync =
        ref.watch(accountTransactionsProvider(widget.account.id));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';
    final categoriesAsync = ref.watch(categoriesProvider);

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: 0,
        vertical: 16.0.scaled(context, ref),
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.0.scaled(context, ref)),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'month', label: Text(l10n.investScopeMonth)),
              ButtonSegment(value: 'year', label: Text(l10n.investScopeYear)),
              ButtonSegment(value: 'custom', label: Text(l10n.investScopeCustom)),
            ],
            selected: {_scope},
            onSelectionChanged: (s) async {
              final next = s.first;
              if (next == 'custom') {
                final from = await showWheelDatePicker(
                  context,
                  initial: _customFrom ?? _month,
                );
                if (!context.mounted) return;
                final to = await showWheelDatePicker(
                  context,
                  initial: _customTo ?? DateTime.now(),
                );
                if (from != null && to != null) {
                  setState(() {
                    _scope = 'custom';
                    _customFrom = from;
                    _customTo = to;
                  });
                }
              } else {
                setState(() => _scope = next);
              }
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            12.0.scaled(context, ref),
            8.0.scaled(context, ref),
            12.0.scaled(context, ref),
            0,
          ),
          child: Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: _pickPeriod,
              child: Text(_periodLabel()),
            ),
          ),
        ),
        SizedBox(height: 8.0.scaled(context, ref)),
        SectionCard(
          child: statsAsync.when(
            data: (stats) => Padding(
              padding: EdgeInsets.all(12.0.scaled(context, ref)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCell(
                          label: l10n.investClosingValue,
                          value: stats.closingValue,
                          currencyCode: currencyCode,
                          color: BeeTokens.textPrimary(context),
                        ),
                      ),
                      Expanded(
                        child: _StatCell(
                          label: l10n.investOpeningValue,
                          value: stats.openingValue,
                          currencyCode: currencyCode,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.0.scaled(context, ref)),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCell(
                          label: l10n.investPeriodNetIn,
                          value: stats.netTransferIn,
                          currencyCode: currencyCode,
                          color: BeeTokens.textPrimary(context),
                        ),
                      ),
                      Expanded(
                        child: _StatCell(
                          label: l10n.investPeriodPnl,
                          value: stats.periodPnl,
                          currencyCode: currencyCode,
                          color: stats.periodPnl >= 0
                              ? BeeTokens.incomeColor(context, ref)
                              : BeeTokens.expenseColor(context, ref),
                        ),
                      ),
                      Expanded(
                        child: _StatCell(
                          label: l10n.investTotalPnl,
                          value: stats.totalPnl,
                          currencyCode: currencyCode,
                          color: stats.totalPnl >= 0
                              ? BeeTokens.incomeColor(context, ref)
                              : BeeTokens.expenseColor(context, ref),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: Text('${l10n.commonError}: $err'),
            ),
          ),
        ),
        SizedBox(height: 8.0.scaled(context, ref)),
        SectionCard(
          child: transactionsAsync.when(
            data: (transactions) {
              final inPeriod = transactions.where((tx) {
                return !tx.happenedAt.isBefore(range.from) &&
                    tx.happenedAt.isBefore(range.to);
              }).toList();
              if (inPeriod.isEmpty) {
                return Padding(
                  padding: EdgeInsets.all(32.0.scaled(context, ref)),
                  child: Center(child: Text(l10n.commonEmpty)),
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
                  ...inPeriod.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tx = entry.value;
                    return Column(
                      children: [
                        if (index > 0) BeeTokens.cardDivider(context),
                        _swipeToDelete(
                          dismissKey: ValueKey('account-tx-${tx.id}'),
                          onConfirmDelete: () => _confirmDeleteRecord(
                            context,
                            delete: () async {
                              await ref
                                  .read(repositoryProvider)
                                  .deleteTransaction(tx.id);
                              _afterTransactionDeleted(
                                ref,
                                accountId: widget.account.id,
                              );
                            },
                          ),
                          child: _TransactionTile(
                            transaction: tx,
                            currencyCode: currencyCode,
                            primaryColor: primaryColor,
                            ledgers: ref.watch(ledgersStreamProvider).asData?.value ?? [],
                            categories: categoriesAsync.asData?.value ?? [],
                            currentAccountId: widget.account.id,
                            onTap: () => _editTransaction(context, ref, tx),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: Text('${l10n.commonError}: $err'),
            ),
          ),
        ),
      ],
    );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final receivablesAsync = ref.watch(receivablesByAccountProvider(widget.account.id));
    final outstandingAsync = ref.watch(receivableOutstandingMapProvider(widget.account.id));
    final balanceAsync = ref.watch(receivableBalanceProvider(widget.account.id));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';

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
            data: (receivables) => outstandingAsync.when(
              data: (outstandingMap) {
              // 过滤应收款（未收/已收按剩余本金，与统计、分批还款一致）
              final filteredReceivables = receivables.where((r) {
                if (_filter == 'all') return true;
                final o = outstandingMap[r.id] ?? 0;
                if (_filter == 'received') return o <= _kReceivablePayableOutstandingEps;
                if (_filter == 'pending') return o > _kReceivablePayableOutstandingEps;
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

                    // 计算该借款人的总金额
                    double totalAmount = 0;
                    double pendingAmount = 0;
                    for (final r in borrowerReceivables) {
                      totalAmount += r.amount;
                      pendingAmount += outstandingMap[r.id] ?? 0;
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
                                _swipeToDelete(
                                  dismissKey: ValueKey('account-receivable-${r.id}'),
                                  onConfirmDelete: () => _confirmDeleteRecord(
                                    context,
                                    delete: () async {
                                      await ref
                                          .read(repositoryProvider)
                                          .deleteReceivable(r.id);
                                      ref.invalidate(
                                        receivablesByAccountProvider(
                                            widget.account.id),
                                      );
                                      ref.invalidate(
                                        receivableBalanceProvider(
                                            widget.account.id),
                                      );
                                      ref.invalidate(
                                        receivableStatsProvider(
                                            widget.account.id),
                                      );
                                      ref.invalidate(
                                        receivableOutstandingMapProvider(
                                            widget.account.id),
                                      );
                                      ref.invalidate(allAccountStatsProvider);
                                      ref.invalidate(
                                          allAccountsTotalStatsProvider);
                                      final curLedger =
                                          ref.read(currentLedgerIdProvider);
                                      ref.read(statsRefreshProvider.notifier)
                                          .state++;
                                      PostProcessor.sync(ref, ledgerId: curLedger);
                                    },
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                        left: 44.0.scaled(context, ref)),
                                    child: _ReceivableTile(
                                      receivable: r,
                                      outstanding: outstandingMap[r.id] ?? 0,
                                      currencyCode: currencyCode,
                                      onTap: () => _viewReceivableDetail(
                                          context, ref, r, currencyCode),
                                    ),
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

  Future<void> _viewReceivableDetail(
      BuildContext context, WidgetRef ref, db.Receivable r, String currencyCode) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReceivableRecordDetailPage(
          receivable: r,
          currencyCode: currencyCode,
        ),
      ),
    );
    ref.invalidate(receivablesByAccountProvider(widget.account.id));
    ref.invalidate(receivableBalanceProvider(widget.account.id));
    ref.invalidate(receivableStatsProvider(widget.account.id));
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final payablesAsync = ref.watch(payablesByAccountProvider(widget.account.id));
    final outstandingAsync = ref.watch(payableOutstandingMapProvider(widget.account.id));
    final balanceAsync = ref.watch(payableBalanceProvider(widget.account.id));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';

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
            data: (payables) => outstandingAsync.when(
              data: (outstandingMap) {
              // 过滤应付款（未付/已付按剩余本金）
              final filteredPayables = payables.where((p) {
                if (_filter == 'all') return true;
                final o = outstandingMap[p.id] ?? 0;
                if (_filter == 'paid') return o <= _kReceivablePayableOutstandingEps;
                if (_filter == 'pending') return o > _kReceivablePayableOutstandingEps;
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

                    // 计算该收款人的总金额
                    double totalAmount = 0;
                    double pendingAmount = 0;
                    for (final p in payeePayables) {
                      totalAmount += p.amount;
                      pendingAmount += outstandingMap[p.id] ?? 0;
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
                                _swipeToDelete(
                                  dismissKey: ValueKey('account-payable-${p.id}'),
                                  onConfirmDelete: () => _confirmDeleteRecord(
                                    context,
                                    delete: () async {
                                      await ref
                                          .read(repositoryProvider)
                                          .deletePayable(p.id);
                                      ref.invalidate(
                                        payablesByAccountProvider(
                                            widget.account.id),
                                      );
                                      ref.invalidate(
                                        payableBalanceProvider(
                                            widget.account.id),
                                      );
                                      ref.invalidate(
                                        payableStatsProvider(widget.account.id),
                                      );
                                      ref.invalidate(
                                        payableOutstandingMapProvider(
                                            widget.account.id),
                                      );
                                      ref.invalidate(allAccountStatsProvider);
                                      ref.invalidate(
                                          allAccountsTotalStatsProvider);
                                      final curLedger =
                                          ref.read(currentLedgerIdProvider);
                                      ref.read(statsRefreshProvider.notifier)
                                          .state++;
                                      PostProcessor.sync(ref, ledgerId: curLedger);
                                    },
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                        left: 44.0.scaled(context, ref)),
                                    child: _PayableTile(
                                      payable: p,
                                      outstanding: outstandingMap[p.id] ?? 0,
                                      currencyCode: currencyCode,
                                      onTap: () => _viewPayableDetail(
                                          context, ref, p, currencyCode),
                                    ),
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

  Future<void> _viewPayableDetail(
      BuildContext context, WidgetRef ref, db.Payable p, String currencyCode) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PayableRecordDetailPage(
          payable: p,
          currencyCode: currencyCode,
        ),
      ),
    );
    ref.invalidate(payablesByAccountProvider(widget.account.id));
    ref.invalidate(payableBalanceProvider(widget.account.id));
    ref.invalidate(payableStatsProvider(widget.account.id));
  }
}

/// 应收款记录列表项
class _ReceivableTile extends ConsumerWidget {
  final db.Receivable receivable;
  /// 剩余未收本金（与列表筛选、分组小计一致）
  final double outstanding;
  final String currencyCode;
  final VoidCallback onTap;

  const _ReceivableTile({
    required this.receivable,
    required this.outstanding,
    required this.currencyCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final settled = outstanding <= _kReceivablePayableOutstandingEps;

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
                color: settled
                    ? Colors.green.withValues(alpha: 0.12)
                    : primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                settled ? Icons.check : Icons.currency_exchange,
                size: 18,
                color: settled ? Colors.green : primaryColor,
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
                      if (settled)
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
                    child: receivable.fromAccountId == null
                        ? Text(
                            '借款账户: 未关联',
                            style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textSecondary(context),
                            ),
                          )
                        : Text(
                            '借款账户: ${ref.watch(accountByIdProvider(receivable.fromAccountId!)).value?.name ?? '-'}',
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
                ],
              ),
            ),
            AmountText(
              value: outstanding,
              signed: false,
              showCurrency: false,
              currencyCode: currencyCode,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: settled
                    ? BeeTokens.textSecondary(context)
                    : BeeTokens.textPrimary(context),
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
  final double outstanding;
  final String currencyCode;
  final VoidCallback onTap;

  const _PayableTile({
    required this.payable,
    required this.outstanding,
    required this.currencyCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final settled = outstanding <= _kReceivablePayableOutstandingEps;

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
                color: settled
                    ? Colors.green.withValues(alpha: 0.12)
                    : primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                settled ? Icons.check : Icons.currency_exchange,
                size: 18,
                color: settled ? Colors.green : primaryColor,
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
                      if (settled)
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
                    child: payable.toAccountId == null
                        ? Text(
                            '入账账户: 未关联',
                            style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textSecondary(context),
                            ),
                          )
                        : Text(
                            '入账账户: ${ref.watch(accountByIdProvider(payable.toAccountId!)).value?.name ?? '-'}',
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
                ],
              ),
            ),
            AmountText(
              value: outstanding,
              signed: false,
              showCurrency: false,
              currencyCode: currencyCode,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: settled
                    ? BeeTokens.textSecondary(context)
                    : BeeTokens.textPrimary(context),
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

/// 按月折叠的账户流水卡片
class _AccountMonthCard extends ConsumerWidget {
  final _AccountMonthGroup group;
  final bool expanded;
  final String currencyCode;
  final Color primaryColor;
  final List<db.Ledger> ledgers;
  final List<db.Category> categories;
  final int accountId;
  final VoidCallback onToggle;
  final ValueChanged<db.Transaction> onEditTransaction;

  const _AccountMonthCard({
    required this.group,
    required this.expanded,
    required this.currencyCode,
    required this.primaryColor,
    required this.ledgers,
    required this.categories,
    required this.accountId,
    required this.onToggle,
    required this.onEditTransaction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: EdgeInsets.all(12.0.scaled(context, ref)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.accountMonthTitle(group.year, group.month),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
                        ),
                      ),
                      Icon(
                        expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: BeeTokens.iconSecondary(context),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.0.scaled(context, ref)),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCell(
                          label: l10n.accountInflow,
                          value: group.inflow,
                          currencyCode: currencyCode,
                          color: BeeTokens.incomeColor(context, ref),
                          valueSize: 15,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 36.0.scaled(context, ref),
                        color: BeeTokens.border(context),
                      ),
                      Expanded(
                        child: _StatCell(
                          label: l10n.accountOutflow,
                          value: group.outflow,
                          currencyCode: currencyCode,
                          color: BeeTokens.expenseColor(context, ref),
                          valueSize: 15,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 36.0.scaled(context, ref),
                        color: BeeTokens.border(context),
                      ),
                      Expanded(
                        child: _StatCell(
                          label: l10n.accountBalance,
                          value: group.endBalance,
                          currencyCode: currencyCode,
                          color: group.endBalance >= 0
                              ? BeeTokens.textPrimary(context)
                              : BeeTokens.error(context),
                          valueSize: 15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            BeeTokens.cardDivider(context),
            ...group.transactions.asMap().entries.map((entry) {
              final index = entry.key;
              final tx = entry.value;
              return Column(
                children: [
                  if (index > 0) BeeTokens.cardDivider(context),
                  _swipeToDelete(
                    dismissKey: ValueKey('account-tx-${tx.id}'),
                    onConfirmDelete: () => _confirmDeleteRecord(
                      context,
                      delete: () async {
                        await ref
                            .read(repositoryProvider)
                            .deleteTransaction(tx.id);
                        _afterTransactionDeleted(ref, accountId: accountId);
                      },
                    ),
                    child: _TransactionTile(
                      transaction: tx,
                      currencyCode: currencyCode,
                      primaryColor: primaryColor,
                      ledgers: ledgers,
                      categories: categories,
                      currentAccountId: accountId,
                      onTap: () => onEditTransaction(tx),
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// 统计单元格
class _StatCell extends ConsumerWidget {
  final String label;
  final double value;
  final String currencyCode;
  final Color color;
  final double valueSize;

  const _StatCell({
    required this.label,
    required this.value,
    required this.currencyCode,
    required this.color,
    this.valueSize = 18,
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
            fontSize: valueSize,
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
      case InvestTx.gain:
        amountColor = BeeTokens.incomeColor(context, ref);
        break;
      case 'expense':
      case InvestTx.loss:
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
      final isLoanLedger = transaction.receivableId != null ||
          transaction.payableId != null;
      if (transaction.note?.isNotEmpty == true) {
        displayTitle = transaction.note!;
      } else if (isLoanLedger) {
        displayTitle = transaction.receivableId != null
            ? (isTransferOut ? '借出' : '收回')
            : (isTransferIn ? '借入' : '偿还');
      } else {
        displayTitle = l10n.transferTitle;
      }

      if (!isLoanLedger) {
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
      }
    } else if (InvestTx.isPnlType(transaction.type)) {
      if (transaction.note?.isNotEmpty == true) {
        displayTitle = transaction.note!;
      } else if (transaction.investEvent == InvestTx.eventDividend) {
        displayTitle = l10n.investEventDividend;
      } else if (transaction.investEvent == InvestTx.eventMarkToMarket) {
        displayTitle = l10n.investEventMark;
      } else {
        displayTitle = transaction.type == InvestTx.gain
            ? l10n.investGain
            : l10n.investLoss;
      }
      displaySubtitle = transaction.investEvent == InvestTx.eventDividend
          ? l10n.investEventDividend
          : transaction.investEvent == InvestTx.eventMarkToMarket
              ? l10n.investEventMark
              : l10n.investEventManual;
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
              value: transaction.type == 'expense' ||
                      transaction.type == InvestTx.loss
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
    .autoDispose<double, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.getReceivableBalance(accountId);
});

/// 每笔应收款的剩余未收本金（收款后实时更新）
final receivableOutstandingMapProvider = StreamProvider.family
    .autoDispose<Map<int, double>, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchReceivableOutstandingMapForAccount(accountId);
});

// Provider: 应收款统计
final receivableStatsProvider = FutureProvider.family
    .autoDispose<({double pending, double total, double received}), int>((ref, accountId) {
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
    .autoDispose<double, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.getPayableBalance(accountId);
});

/// 每笔应付款的剩余未付本金（还款后实时更新）
final payableOutstandingMapProvider = StreamProvider.family
    .autoDispose<Map<int, double>, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchPayableOutstandingMapForAccount(accountId);
});

// Provider: 应付款统计
final payableStatsProvider = FutureProvider.family
    .autoDispose<({double pending, double total, double paid}), int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.getPayableStats(accountId);
});

// Provider: 收款记录
final receivablePaymentsProvider = StreamProvider.family
    .autoDispose<List<db.ReceivablePayment>, int>((ref, receivableId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchReceivablePayments(receivableId);
});

// Provider: 还款记录
final payablePaymentsProvider = StreamProvider.family
    .autoDispose<List<db.PayablePayment>, int>((ref, payableId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchPayablePayments(payableId);
});
