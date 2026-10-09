import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/utils/refund_tx.dart';

void main() {
  group('RefundTx.netExpense', () {
    test('deducts refunds and reimbursements from the original expense', () {
      expect(
        RefundTx.netExpense(original: 100, linkedCredits: 30),
        70,
      );
    });

    test('floors a fully offset expense at zero', () {
      expect(
        RefundTx.netExpense(original: 100, linkedCredits: 100),
        0,
      );
    });

    test('does not turn an over-refunded expense negative', () {
      expect(
        RefundTx.netExpense(original: 100, linkedCredits: 130),
        0,
      );
    });
  });
}
