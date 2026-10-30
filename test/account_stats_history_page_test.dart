import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/account/account_stats_history_page.dart';
import 'package:beecount/pages/receivable_payable/receivable_record_detail_page.dart';
import 'package:beecount/pages/transaction/transaction_detail_page.dart';
import 'package:beecount/providers.dart';
import 'package:beecount/widgets/biz/amount_text.dart';
import 'package:beecount/widgets/biz/transaction_list_item.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('old receivable month excludes accounts opened years later',
      (tester) async {
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'Main'),
        );
    final openedAt = DateTime(2026, 3, 24);
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: ledgerId,
          name: 'Savings',
          initialBalance: const Value(651299.06),
          createdAt: Value(openedAt),
        ));
    final receivableAccountId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            ledgerId: ledgerId,
            name: 'Receivables',
            type: const Value('receivable'),
            createdAt: Value(openedAt),
          ),
        );
    await db.into(db.receivables).insert(ReceivablesCompanion.insert(
          accountId: receivableAccountId,
          borrowerName: 'Test',
          amount: 17000,
          borrowDate: DateTime(2019, 2, 1),
        ));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(LocalRepository(db)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AccountStatsHistoryPage(metric: AccountHistoryMetric.netAssets),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('2019-02'), 700,
        scrollable: find.byType(Scrollable).first);

    final card = find.ancestor(
      of: find.text('2019-02'),
      matching: find.byType(Card),
    );
    final amounts = tester.widgetList<AmountText>(
      find.descendant(of: card, matching: find.byType(AmountText)),
    );
    expect(amounts.first.value, 17000);

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(TransactionListItem), findsOneWidget);
    final detailAmount = tester.widget<AmountText>(
      find.descendant(
        of: find.byType(TransactionListItem),
        matching: find.byType(AmountText),
      ),
    );
    expect(detailAmount.value, 17000);

    await tester.tap(find.byType(TransactionListItem));
    await tester.pumpAndSettle();
    expect(find.byType(ReceivableRecordDetailPage), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('2026-03'), -700,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('2026-03'));
    await tester.pumpAndSettle();
    final openingAmount = tester.widget<AmountText>(
      find.descendant(
        of: find.byType(TransactionListItem),
        matching: find.byType(AmountText),
      ),
    );
    expect(openingAmount.value, 651299.06);
  });

  testWidgets('monthly detail entries reconcile transfers, loans and refunds',
      (tester) async {
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'Main'),
        );
    final cashId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: ledgerId,
          name: 'Cash',
          initialBalance: const Value(1000),
          createdAt: Value(DateTime(2026, 1, 1)),
        ));
    final receivableId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            ledgerId: ledgerId,
            name: 'Receivables',
            type: const Value('receivable'),
            createdAt: Value(DateTime(2026, 1, 1)),
          ),
        );
    int epoch(int month, int day) =>
        DateTime(2026, month, day).millisecondsSinceEpoch ~/ 1000;
    Future<int> transaction(String type, double amount, int month, int day,
        {int? toAccountId, int? refundOfId}) async {
      await db.customStatement('''
        INSERT INTO transactions
          (ledger_id, type, amount, account_id, to_account_id, refund_of_id, happened_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
        ledgerId,
        type,
        amount,
        cashId,
        toAccountId,
        refundOfId,
        epoch(month, day)
      ]);
      return (await db
              .customSelect('SELECT last_insert_rowid() AS id')
              .getSingle())
          .read<int>('id');
    }

    await transaction('income', 100, 1, 5);
    final expenseId = await transaction('expense', 40, 1, 6);
    await transaction('transfer', 200, 1, 7, toAccountId: receivableId);
    await transaction('refund', 10, 2, 2, refundOfId: expenseId);
    await db.customStatement('''
      INSERT INTO transactions
        (ledger_id, type, amount, account_id, to_account_id, happened_at)
      VALUES (?, 'transfer', 50, ?, ?, ?)
    ''', [ledgerId, receivableId, cashId, epoch(2, 3)]);
    final loanId = await db.into(db.receivables).insert(
          ReceivablesCompanion.insert(
            accountId: receivableId,
            borrowerName: 'Borrower',
            amount: 200,
            borrowDate: DateTime(2026, 1, 7),
          ),
        );
    await db.customStatement('''
      INSERT INTO receivable_payments
        (receivable_id, amount, happened_at)
      VALUES (?, 50, ?)
    ''', [loanId, epoch(2, 3)]);

    Future<void> check(AccountHistoryMetric metric, double difference) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(LocalRepository(db)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AccountStatsHistoryPage(metric: metric),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('2026-02'), 500,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('2026-02'));
      await tester.pumpAndSettle();
      final amounts = tester
          .widgetList<AmountText>(find.byType(AmountText))
          .map((widget) => widget.value)
          .toList();
      expect(amounts[1], closeTo(difference, 0.000001));
      expect(amounts.skip(2).fold<double>(0, (sum, value) => sum + value),
          closeTo(difference, 0.000001));
      if (metric == AccountHistoryMetric.netAssets) {
        await tester.tap(find.byType(TransactionListItem).first);
        await tester.pumpAndSettle();
        expect(find.byType(TransactionDetailPage), findsOneWidget);
      }
    }

    await check(AccountHistoryMetric.netAssets, 10);
    await check(AccountHistoryMetric.availableFunds, 60);
    await check(AccountHistoryMetric.expense, -10);
  });
}
