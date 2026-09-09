import 'package:beecount/utils/account_funds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ({String type, double balance}) acc(String type, double balance) =>
      (type: type, balance: balance);

  test('sums cash-like and signed credit card, subtracts payable, skips invest/receivable',
      () {
    final value = AccountFunds.available(
      accounts: [
        acc('cash', 100),
        acc('bank_card', 200),
        acc('wechat', 50),
        acc('alipay', 30),
        acc('other', 20),
        acc('credit_card', -80),
        acc('investment', 1000),
        acc('receivable', 500),
        acc('payable', -200),
      ],
      outstandingPayable: 40,
    );
    expect(value, 260);
  });

  test('other account type is excluded from available funds', () {
    expect(
      AccountFunds.available(
        accounts: [acc('cash', 100), acc('other', 50)],
        outstandingPayable: 0,
      ),
      100,
    );
  });

  test('credit card overpayment counts as available funds', () {
    expect(
      AccountFunds.available(
        accounts: [acc('cash', 100), acc('credit_card', 20)],
        outstandingPayable: 0,
      ),
      120,
    );
  });

  test('unknown account types are excluded', () {
    expect(
      AccountFunds.available(
        accounts: [acc('mystery', 99), acc('cash', 1)],
        outstandingPayable: 0,
      ),
      1,
    );
  });
}
