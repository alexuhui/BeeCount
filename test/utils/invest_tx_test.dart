import 'package:beecount/utils/invest_tx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InvestTx.accountCashFlow', () {
    test('counts refunds and reimbursements as actual inflow', () {
      expect(
        InvestTx.accountCashFlow(
          type: 'refund',
          amount: 30,
          accountId: 1,
          txAccountId: 1,
        ),
        (inflow: 30.0, outflow: 0.0),
      );
      expect(
        InvestTx.accountCashFlow(
          type: 'reimburse',
          amount: 80,
          accountId: 1,
          txAccountId: 1,
        ),
        (inflow: 80.0, outflow: 0.0),
      );
    });

    test('keeps expenses as actual outflow without netting linked credits', () {
      expect(
        InvestTx.accountCashFlow(
          type: 'expense',
          amount: 100,
          accountId: 1,
          txAccountId: 1,
        ),
        (inflow: 0.0, outflow: 100.0),
      );
    });
  });
}
