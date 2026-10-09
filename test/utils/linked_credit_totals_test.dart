import 'package:beecount/data/db.dart';
import 'package:beecount/utils/linked_credit_totals.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction tx({
  required int id,
  required String type,
  required double amount,
  required DateTime happenedAt,
  int? refundOfId,
}) {
  return Transaction(
    id: id,
    ledgerId: 1,
    type: type,
    amount: amount,
    happenedAt: happenedAt,
    excludeFromStats: false,
    refundOfId: refundOfId,
  );
}

void main() {
  final start = DateTime(2026, 10, 1);
  final end = DateTime(2026, 11, 1);

  test('expense ranking uses net expense and includes later linked credits',
      () {
    final rows = [
      tx(
        id: 1,
        type: 'expense',
        amount: 100,
        happenedAt: DateTime(2026, 10, 10),
      ),
      tx(
        id: 2,
        type: 'refund',
        amount: 30,
        happenedAt: DateTime(2026, 11, 2),
        refundOfId: 1,
      ),
      tx(
        id: 3,
        type: 'reimburse',
        amount: 20,
        happenedAt: DateTime(2026, 10, 20),
        refundOfId: 1,
      ),
      tx(
        id: 4,
        type: 'income',
        amount: 999,
        happenedAt: DateTime(2026, 10, 12),
      ),
    ];

    expect(
      transactionStatTotalInRange(
        rows,
        type: 'expense',
        start: start,
        end: end,
      ),
      50,
    );
  });

  test('expense ranking floors each over-refunded expense at zero', () {
    final rows = [
      tx(
        id: 1,
        type: 'expense',
        amount: 100,
        happenedAt: DateTime(2026, 10, 10),
      ),
      tx(
        id: 2,
        type: 'refund',
        amount: 130,
        happenedAt: DateTime(2026, 10, 11),
        refundOfId: 1,
      ),
    ];

    expect(
      transactionStatTotalInRange(
        rows,
        type: 'expense',
        start: start,
        end: end,
      ),
      0,
    );
  });
}
