import 'package:beecount/data/db.dart';
import 'package:beecount/utils/account_availability.dart';
import 'package:flutter_test/flutter_test.dart';

Account account({
  required int id,
  required String currency,
  String name = 'a',
}) =>
    Account(
      id: id,
      ledgerId: 1,
      name: name,
      type: 'cash',
      currency: currency,
      initialBalance: 0,
    );

Ledger ledger({required String currency}) => Ledger(
      id: 1,
      name: '账本',
      currency: currency,
      type: 'personal',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  test('missing ledger yields empty list instead of throwing', () {
    final accounts = [account(id: 1, currency: 'CNY')];
    expect(
      accountsAvailableForLedger(ledger: null, allAccounts: accounts),
      isEmpty,
    );
  });

  test('keeps accounts that share the ledger currency', () {
    final result = accountsAvailableForLedger(
      ledger: ledger(currency: 'CNY'),
      allAccounts: [
        account(id: 1, currency: 'CNY', name: '现金'),
        account(id: 2, currency: 'USD', name: '美元'),
      ],
    );
    expect(result.map((a) => a.id), [1]);
  });
}
