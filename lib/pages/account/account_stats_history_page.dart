import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/account_funds.dart';
import '../../utils/invest_tx.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/ui/primary_header.dart';

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

  const _MonthValue(this.month, this.value, this.difference);
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
    final ledgers = await repo.getAllLedgers();
    final transactionGroups = await Future.wait(
      ledgers.map((ledger) => repo.getTransactionsByLedger(ledger.id)),
    );
    final transactions = transactionGroups.expand((group) => group).toList()
      ..sort((a, b) => a.happenedAt.compareTo(b.happenedAt));
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
      final balances = {for (final a in accounts) a.id: a.initialBalance};
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
      values.add(_MonthValue(month, value, value - previous));
      previous = value;
    }
    return values.reversed.toList();
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
                                          ? BeeTokens.incomeColor(context, ref)
                                          : BeeTokens.expenseColor(
                                              context, ref))),
                            ]),
                      ]),
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
