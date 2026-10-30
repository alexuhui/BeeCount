import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_account_repository.dart';
import 'package:beecount/data/repositories/local/local_transaction_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account history includes hidden and investment balance movements',
      () async {
    final db = BeeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final ledgerId = await db.into(db.ledgers).insert(
          LedgersCompanion.insert(name: 'Main'),
        );
    final cashId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(ledgerId: ledgerId, name: 'Cash'),
        );
    final investmentId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            ledgerId: ledgerId,
            name: 'Investment',
          ),
        );
    await db.customStatement(
      "UPDATE accounts SET type = 'investment' WHERE id = ?",
      [investmentId],
    );
    await db.customStatement(
      '''INSERT INTO transactions
         (ledger_id, type, amount, account_id, happened_at, exclude_from_stats)
         VALUES (?, 'expense', 30, ?, ?, 1)''',
      [ledgerId, cashId, DateTime(2026, 1, 10).millisecondsSinceEpoch ~/ 1000],
    );
    await db.customStatement(
      '''INSERT INTO transactions
         (ledger_id, type, amount, account_id, happened_at, exclude_from_stats)
         VALUES (?, 'invest_gain', 10, ?, ?, 1)''',
      [
        ledgerId,
        investmentId,
        DateTime(2026, 1, 20).millisecondsSinceEpoch ~/ 1000
      ],
    );

    final accountRepo = LocalAccountRepository(db);
    final transactionRepo = LocalTransactionRepository(db);
    final summary = await accountRepo.getAllAccountsTotalStats();
    final historyTransactions =
        await transactionRepo.getAllTransactionsForAccountBalance();
    final ordinaryTransactions =
        await transactionRepo.getTransactionsByLedger(ledgerId);

    expect(summary.totalBalance, -20);
    expect(historyTransactions.map((t) => t.type),
        containsAll(['expense', 'invest_gain']));
    expect(ordinaryTransactions, isEmpty);
  });
}
