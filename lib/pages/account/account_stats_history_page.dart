import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/account_funds.dart';
import '../../utils/category_utils.dart';
import '../../utils/invest_tx.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/transaction_list_item.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/ui/primary_header.dart';
import 'account_detail_page.dart';
import '../receivable_payable/receivable_record_detail_page.dart';
import '../receivable_payable/payable_record_detail_page.dart';

enum AccountHistoryMetric {
  netAssets,
  availableFunds,
  income,
  expense,
  investments,
  investmentPnl,
}

class _MonthValue {
  final DateTime month;
  final double value;
  final double difference;
  final List<_HistoryChange> changes;

  const _MonthValue(this.month, this.value, this.difference, this.changes);
}

enum _ChangeKind {
  opening,
  income,
  expense,
  transfer,
  refund,
  reimburse,
  gain,
  loss,
  receivable,
  payable,
}

class _HistoryChange {
  final DateTime date;
  final _ChangeKind kind;
  final String name;
  final String? note;
  final double amount;
  final db.Transaction? transaction;
  final db.Account? account;
  final db.Receivable? receivable;
  final db.Payable? payable;
  final db.Category? category;

  const _HistoryChange(this.date, this.kind, this.name, this.note, this.amount,
      {this.transaction,
      this.account,
      this.receivable,
      this.payable,
      this.category});
}

class AccountStatsHistoryPage extends ConsumerStatefulWidget {
  final AccountHistoryMetric metric;

  const AccountStatsHistoryPage({super.key, required this.metric});

  @override
  ConsumerState<AccountStatsHistoryPage> createState() =>
      _AccountStatsHistoryPageState();
}

class _AccountStatsHistoryPageState
    extends ConsumerState<AccountStatsHistoryPage> {
  late Future<List<_MonthValue>> _history;

  @override
  void initState() {
    super.initState();
    _history = _load();
  }

  String _title(AppLocalizations l10n) => switch (widget.metric) {
        AccountHistoryMetric.netAssets => l10n.accountTotalBalance,
        AccountHistoryMetric.availableFunds => l10n.accountAvailableFunds,
        AccountHistoryMetric.income => l10n.accountTotalIncome,
        AccountHistoryMetric.expense => l10n.accountTotalExpense,
        AccountHistoryMetric.investments => l10n.investSummaryTitle,
        AccountHistoryMetric.investmentPnl => l10n.investTotalPnl,
      };

  Future<List<_MonthValue>> _load() async {
    final repo = ref.read(repositoryProvider);
    final accounts = await repo.getAllAccounts();
    final categories = await repo.getAllCategories();
    final transactions = await repo.getAllTransactionsForAccountBalance();
    transactions.sort((a, b) => a.happenedAt.compareTo(b.happenedAt));
    final receivables = <db.Receivable>[];
    final payables = <db.Payable>[];
    final receivablePayments = <db.ReceivablePayment>[];
    final payablePayments = <db.PayablePayment>[];
    for (final account in accounts) {
      if (account.type == 'receivable') {
        for (final item in await repo.getReceivablesByAccountId(account.id)) {
          receivables.add(item);
          receivablePayments.addAll(await repo.getReceivablePayments(item.id));
        }
      } else if (account.type == 'payable') {
        for (final item in await repo.getPayablesByAccountId(account.id)) {
          payables.add(item);
          payablePayments.addAll(await repo.getPayablePayments(item.id));
        }
      }
    }

    final now = DateTime.now();
    var first = DateTime(now.year, now.month);
    void include(DateTime? date) {
      if (date != null && date.isBefore(first)) {
        first = DateTime(date.year, date.month);
      }
    }

    for (final account in accounts) {
      include(account.createdAt);
    }
    for (final tx in transactions) {
      include(tx.happenedAt);
    }
    for (final item in receivables) {
      include(item.borrowDate);
    }
    for (final item in payables) {
      include(item.payDate);
    }

    final accountIds = accounts.map((a) => a.id).toSet();
    final investmentIds = accounts
        .where((a) => InvestTx.isInvestmentAccount(a.type))
        .map((a) => a.id)
        .toSet();
    final values = <_MonthValue>[];
    double previous = 0;
    for (var month = first;
        !month.isAfter(DateTime(now.year, now.month));
        month = DateTime(month.year, month.month + 1)) {
      final end = DateTime(month.year, month.month + 1);
      // 初始余额从账户建立时才存在，不能倒填到更早的应收/应付月份。
      // 旧数据可能没有 createdAt，此时保留原有的初始余额口径。
      final balances = {
        for (final a in accounts)
          a.id: a.createdAt == null || a.createdAt!.isBefore(end)
              ? a.initialBalance
              : 0.0,
      };
      var income = 0.0;
      var expense = 0.0;
      var investmentPnl = 0.0;
      final refunds = <int, double>{};
      for (final tx in transactions) {
        if (!tx.happenedAt.isBefore(end)) break;
        if (tx.refundOfId != null &&
            (tx.type == 'refund' || tx.type == 'reimburse')) {
          refunds.update(tx.refundOfId!, (v) => v + tx.amount,
              ifAbsent: () => tx.amount);
        }
        for (final id in {tx.accountId, tx.toAccountId}) {
          if (id != null && balances.containsKey(id)) {
            balances[id] = InvestTx.applyToBalance(
              balance: balances[id]!,
              type: tx.type,
              amount: tx.amount,
              accountId: id,
              txAccountId: tx.accountId,
              txToAccountId: tx.toAccountId,
            );
          }
        }
        if (tx.accountId != null && accountIds.contains(tx.accountId)) {
          if (tx.type == 'income') income += tx.amount;
          if (investmentIds.contains(tx.accountId)) {
            if (tx.type == InvestTx.gain) investmentPnl += tx.amount;
            if (tx.type == InvestTx.loss) investmentPnl -= tx.amount;
          }
        }
      }
      for (final tx in transactions) {
        if (!tx.happenedAt.isBefore(end)) break;
        if (tx.type == 'expense' &&
            tx.accountId != null &&
            accountIds.contains(tx.accountId)) {
          final net = tx.amount - (refunds[tx.id] ?? 0);
          expense += net > 0 ? net : 0;
        }
      }
      double outstandingReceivable = 0;
      for (final item in receivables) {
        if (!item.borrowDate.isBefore(end)) continue;
        final paid = receivablePayments
            .where(
                (p) => p.receivableId == item.id && p.happenedAt.isBefore(end))
            .fold<double>(0, (sum, p) => sum + p.amount);
        final remainder = item.amount - paid;
        if (remainder > 0) outstandingReceivable += remainder;
      }
      double outstandingPayable = 0;
      for (final item in payables) {
        if (!item.payDate.isBefore(end)) continue;
        final paid = payablePayments
            .where((p) => p.payableId == item.id && p.happenedAt.isBefore(end))
            .fold<double>(0, (sum, p) => sum + p.amount);
        final remainder = item.amount - paid;
        if (remainder > 0) outstandingPayable += remainder;
      }
      final ordinary =
          accounts.where((a) => a.type != 'receivable' && a.type != 'payable');
      final totalBalance =
          ordinary.fold<double>(0, (sum, a) => sum + (balances[a.id] ?? 0)) +
              outstandingReceivable -
              outstandingPayable;
      final availableFunds = AccountFunds.available(
        accounts:
            ordinary.map((a) => (type: a.type, balance: balances[a.id] ?? 0.0)),
        outstandingPayable: outstandingPayable,
      );
      final investments = accounts
          .where((a) => InvestTx.isInvestmentAccount(a.type))
          .fold<double>(0, (sum, a) => sum + (balances[a.id] ?? 0));
      final value = switch (widget.metric) {
        AccountHistoryMetric.netAssets => totalBalance,
        AccountHistoryMetric.availableFunds => availableFunds,
        AccountHistoryMetric.income => income,
        AccountHistoryMetric.expense => expense,
        AccountHistoryMetric.investments => investments,
        AccountHistoryMetric.investmentPnl => investmentPnl,
      };
      final changes = _changesForMonth(
        month: month,
        first: first,
        end: end,
        accounts: accounts,
        categories: categories,
        transactions: transactions,
        receivables: receivables,
        payables: payables,
        receivablePayments: receivablePayments,
        payablePayments: payablePayments,
      );
      values.add(_MonthValue(month, value, value - previous, changes));
      previous = value;
    }
    return values.reversed.toList();
  }

  List<_HistoryChange> _changesForMonth({
    required DateTime month,
    required DateTime first,
    required DateTime end,
    required List<db.Account> accounts,
    required List<db.Category> categories,
    required List<db.Transaction> transactions,
    required List<db.Receivable> receivables,
    required List<db.Payable> payables,
    required List<db.ReceivablePayment> receivablePayments,
    required List<db.PayablePayment> payablePayments,
  }) {
    final metric = widget.metric;
    final byId = {for (final account in accounts) account.id: account};
    final categoryById = {
      for (final category in categories) category.id: category
    };
    final changes = <_HistoryChange>[];
    bool inMonth(DateTime date) => !date.isBefore(month) && date.isBefore(end);
    bool includedAccount(db.Account account) => switch (metric) {
          AccountHistoryMetric.netAssets =>
            account.type != 'receivable' && account.type != 'payable',
          AccountHistoryMetric.availableFunds =>
            AccountFunds.isLiquidType(account.type),
          AccountHistoryMetric.investments =>
            InvestTx.isInvestmentAccount(account.type),
          _ => false,
        };
    void add(DateTime date, _ChangeKind kind, String name, String? note,
        double amount,
        {db.Transaction? transaction,
        db.Account? account,
        db.Receivable? receivable,
        db.Payable? payable,
        db.Category? category}) {
      if (amount.abs() < 0.000001) return;
      changes.add(_HistoryChange(date, kind, name, note, amount,
          transaction: transaction,
          account: account,
          receivable: receivable,
          payable: payable,
          category: category));
    }

    for (final account in accounts) {
      if (!includedAccount(account)) continue;
      final date = account.createdAt;
      if ((date == null && month == first) || (date != null && inMonth(date))) {
        add(date ?? month, _ChangeKind.opening, account.name, null,
            account.initialBalance,
            account: account);
      }
    }

    final accountIds = byId.keys.toSet();
    for (final tx in transactions) {
      if (!inMonth(tx.happenedAt)) continue;
      final account = tx.accountId == null ? null : byId[tx.accountId];
      final target = tx.toAccountId == null ? null : byId[tx.toAccountId];
      final name = tx.type == 'transfer' && target != null
          ? '${account?.name ?? ''} → ${target.name}'
          : account?.name ?? target?.name ?? '';
      if (metric == AccountHistoryMetric.income) {
        if (tx.type == 'income' && accountIds.contains(tx.accountId)) {
          add(tx.happenedAt, _ChangeKind.income, name, tx.note, tx.amount,
              transaction: tx, category: categoryById[tx.categoryId]);
        }
      } else if (metric == AccountHistoryMetric.investmentPnl) {
        if (account != null && InvestTx.isInvestmentAccount(account.type)) {
          if (tx.type == InvestTx.gain) {
            add(tx.happenedAt, _ChangeKind.gain, name, tx.note, tx.amount,
                transaction: tx, category: categoryById[tx.categoryId]);
          } else if (tx.type == InvestTx.loss) {
            add(tx.happenedAt, _ChangeKind.loss, name, tx.note, -tx.amount,
                transaction: tx, category: categoryById[tx.categoryId]);
          }
        }
      } else if (metric != AccountHistoryMetric.expense) {
        var amount = 0.0;
        for (final id in {tx.accountId, tx.toAccountId}) {
          final affected = id == null ? null : byId[id];
          if (affected == null || !includedAccount(affected)) continue;
          amount += InvestTx.applyToBalance(
            balance: 0,
            type: tx.type,
            amount: tx.amount,
            accountId: id!,
            txAccountId: tx.accountId,
            txToAccountId: tx.toAccountId,
          );
        }
        final kind = switch (tx.type) {
          'income' => _ChangeKind.income,
          'expense' => _ChangeKind.expense,
          'refund' => _ChangeKind.refund,
          'reimburse' => _ChangeKind.reimburse,
          InvestTx.gain => _ChangeKind.gain,
          InvestTx.loss => _ChangeKind.loss,
          _ => _ChangeKind.transfer,
        };
        add(tx.happenedAt, kind, name, tx.note, amount,
            transaction: tx, category: categoryById[tx.categoryId]);
      }
    }

    if (metric == AccountHistoryMetric.expense) {
      final linked = <int, List<db.Transaction>>{};
      for (final tx in transactions) {
        if (tx.refundOfId != null &&
            (tx.type == 'refund' || tx.type == 'reimburse')) {
          linked.putIfAbsent(tx.refundOfId!, () => []).add(tx);
        }
      }
      for (final tx in transactions) {
        if (tx.type != 'expense' || !accountIds.contains(tx.accountId)) {
          continue;
        }
        double netAt(DateTime cutoff) {
          if (!tx.happenedAt.isBefore(cutoff)) return 0;
          final refunded = (linked[tx.id] ?? const <db.Transaction>[])
              .where((r) => r.happenedAt.isBefore(cutoff))
              .fold<double>(0, (sum, r) => sum + r.amount);
          final net = tx.amount - refunded;
          return net > 0 ? net : 0;
        }

        final amount = netAt(end) - netAt(month);
        final recentLinked = (linked[tx.id] ?? const <db.Transaction>[])
            .where((r) => inMonth(r.happenedAt))
            .toList();
        final event = inMonth(tx.happenedAt)
            ? tx
            : recentLinked.isNotEmpty
                ? recentLinked.last
                : tx;
        final kind = amount < 0
            ? event.type == 'reimburse'
                ? _ChangeKind.reimburse
                : _ChangeKind.refund
            : _ChangeKind.expense;
        add(event.happenedAt, kind, byId[tx.accountId]?.name ?? '', tx.note,
            amount,
            transaction: event, category: categoryById[tx.categoryId]);
      }
    }

    double outstanding(double amount, DateTime openedAt, DateTime cutoff,
        Iterable<({DateTime date, double amount})> payments) {
      if (!openedAt.isBefore(cutoff)) return 0;
      final paid = payments
          .where((p) => p.date.isBefore(cutoff))
          .fold<double>(0, (sum, p) => sum + p.amount);
      final remainder = amount - paid;
      return remainder > 0 ? remainder : 0;
    }

    if (metric == AccountHistoryMetric.netAssets) {
      for (final item in receivables) {
        final payments = receivablePayments
            .where((p) => p.receivableId == item.id)
            .map((p) => (date: p.happenedAt, amount: p.amount));
        final amount =
            outstanding(item.amount, item.borrowDate, end, payments) -
                outstanding(item.amount, item.borrowDate, month, payments);
        final paymentDates =
            payments.where((p) => inMonth(p.date)).map((p) => p.date).toList();
        add(
            inMonth(item.borrowDate)
                ? item.borrowDate
                : paymentDates.isNotEmpty
                    ? paymentDates.last
                    : month,
            _ChangeKind.receivable,
            item.borrowerName,
            item.note,
            amount,
            receivable: item,
            account: byId[item.accountId]);
      }
    }
    if (metric == AccountHistoryMetric.netAssets ||
        metric == AccountHistoryMetric.availableFunds) {
      for (final item in payables) {
        final payments = payablePayments
            .where((p) => p.payableId == item.id)
            .map((p) => (date: p.happenedAt, amount: p.amount));
        final amount = outstanding(item.amount, item.payDate, month, payments) -
            outstanding(item.amount, item.payDate, end, payments);
        final paymentDates =
            payments.where((p) => inMonth(p.date)).map((p) => p.date).toList();
        add(
            inMonth(item.payDate)
                ? item.payDate
                : paymentDates.isNotEmpty
                    ? paymentDates.last
                    : month,
            _ChangeKind.payable,
            item.payeeName,
            item.note,
            amount,
            payable: item,
            account: byId[item.accountId]);
      }
    }
    changes.sort((a, b) => b.date.compareTo(a.date));
    return changes;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(children: [
        PrimaryHeader(title: _title(l10n), showBack: true),
        Expanded(
          child: FutureBuilder<List<_MonthValue>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Text('${l10n.commonError}: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final change = row.difference;
                  final now = DateTime.now();
                  final isCurrentMonth = row.month.year == now.year &&
                      row.month.month == now.month;
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _HistoryDetailPage(
                            metricTitle: _title(l10n),
                            row: row,
                          ),
                        ));
                        if (mounted) {
                          final refreshed = _load();
                          setState(() {
                            _history = refreshed;
                          });
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              '${row.month.year}-${row.month.month.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                          ),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                    isCurrentMonth
                                        ? l10n.accountHistoryCurrentValue
                                        : l10n.accountHistoryMonthEnd,
                                    style: TextStyle(
                                        color: BeeTokens.textSecondary(context),
                                        fontSize: 12)),
                                AmountText(
                                    value: row.value,
                                    signed: false,
                                    style: TextStyle(
                                        color: BeeTokens.textPrimary(context),
                                        fontWeight: FontWeight.w600)),
                              ]),
                          const SizedBox(width: 18),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(l10n.accountHistoryDifference,
                                    style: TextStyle(
                                        color: BeeTokens.textSecondary(context),
                                        fontSize: 12)),
                                AmountText(
                                    value: change,
                                    signed: true,
                                    style: TextStyle(
                                        color: change >= 0
                                            ? BeeTokens.incomeColor(
                                                context, ref)
                                            : BeeTokens.expenseColor(
                                                context, ref))),
                              ]),
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right,
                              size: 18,
                              color: BeeTokens.iconSecondary(context)),
                        ]),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _HistoryDetailPage extends ConsumerWidget {
  final String metricTitle;
  final _MonthValue row;

  const _HistoryDetailPage({required this.metricTitle, required this.row});

  String _kindLabel(AppLocalizations l10n, _ChangeKind kind) => switch (kind) {
        _ChangeKind.opening => l10n.accountInitialBalance,
        _ChangeKind.income => l10n.accountTotalIncome,
        _ChangeKind.expense => l10n.accountTotalExpense,
        _ChangeKind.transfer => l10n.exportTypeTransfer,
        _ChangeKind.refund => l10n.refundTitle,
        _ChangeKind.reimburse => l10n.reimburseTitle,
        _ChangeKind.gain => l10n.investGain,
        _ChangeKind.loss => l10n.investLoss,
        _ChangeKind.receivable => l10n.accountHistoryReceivable,
        _ChangeKind.payable => l10n.accountHistoryPayable,
      };

  IconData _kindIcon(_ChangeKind kind) => switch (kind) {
        _ChangeKind.opening => Icons.account_balance_wallet_outlined,
        _ChangeKind.income => Icons.south_west,
        _ChangeKind.expense => Icons.north_east,
        _ChangeKind.transfer => Icons.swap_horiz,
        _ChangeKind.refund => Icons.assignment_return_outlined,
        _ChangeKind.reimburse => Icons.receipt_long_outlined,
        _ChangeKind.gain => Icons.trending_up,
        _ChangeKind.loss => Icons.trending_down,
        _ChangeKind.receivable => Icons.call_received,
        _ChangeKind.payable => Icons.call_made,
      };

  Future<void> _openChange(BuildContext context, _HistoryChange change) async {
    final transaction = change.transaction;
    if (transaction != null) {
      await TransactionEditUtils.openDetail(context, transaction.id);
    } else if (change.receivable != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReceivableRecordDetailPage(
          receivable: change.receivable!,
          currencyCode: change.account?.currency ?? 'CNY',
        ),
      ));
    } else if (change.payable != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PayableRecordDetailPage(
          payable: change.payable!,
          currencyCode: change.account?.currency ?? 'CNY',
        ),
      ));
    } else if (change.account != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AccountDetailPage(account: change.account!),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final period =
        '${row.month.year}-${row.month.month.toString().padLeft(2, '0')}';
    final isCurrentMonth = row.month.year == DateTime.now().year &&
        row.month.month == DateTime.now().month;
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(children: [
        PrimaryHeader(
            title: '$period ${l10n.accountHistoryDetails}', showBack: true),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metricTitle,
                        style:
                            TextStyle(color: BeeTokens.textSecondary(context))),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isCurrentMonth
                              ? l10n.accountHistoryCurrentValue
                              : l10n.accountHistoryMonthEnd),
                          AmountText(
                              value: row.value,
                              signed: false,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: BeeTokens.textPrimary(context))),
                        ],
                      )),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(l10n.accountHistoryDifference),
                          AmountText(
                              value: row.difference,
                              signed: true,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: row.difference >= 0
                                      ? BeeTokens.incomeColor(context, ref)
                                      : BeeTokens.expenseColor(context, ref))),
                        ],
                      )),
                    ]),
                  ],
                ),
              )),
              const SizedBox(height: 16),
              Text(l10n.accountHistoryDetails,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context))),
              const SizedBox(height: 8),
              if (row.changes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text(l10n.accountHistoryNoChanges,
                          style: TextStyle(
                              color: BeeTokens.textSecondary(context)))),
                ),
              for (final change in row.changes)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  clipBehavior: Clip.antiAlias,
                  child: Builder(builder: (context) {
                    final label = _kindLabel(l10n, change.kind);
                    final categoryName = change.category == null
                        ? label
                        : CategoryUtils.getDisplayName(
                            change.category!.name, context,
                            kind: change.kind == _ChangeKind.income
                                ? 'income'
                                : 'expense');
                    final displayCategory = change.kind == _ChangeKind.refund ||
                            change.kind == _ChangeKind.reimburse
                        ? '$label · $categoryName'
                        : categoryName;
                    final note = change.note?.trim() ?? '';
                    return TransactionListItem(
                      icon: change.category == null
                          ? _kindIcon(change.kind)
                          : getCategoryIconData(category: change.category),
                      category: change.category,
                      title: note.isEmpty ? displayCategory : note,
                      categoryName: displayCategory,
                      amount: change.amount.abs(),
                      isExpense: change.amount < 0,
                      isRefund: change.kind == _ChangeKind.refund,
                      isReimburse: change.kind == _ChangeKind.reimburse,
                      accountName: change.name,
                      happenedAt: change.date,
                      showFullDate: true,
                      onTap: () => _openChange(context, change),
                    );
                  }),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
