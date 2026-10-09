import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../providers/database_providers.dart';
import 'refund_tx.dart';

typedef LinkedCreditTotal = ({double refund, double reimburse});

Map<int, LinkedCreditTotal> linkedCreditTotals(
  Iterable<Transaction> transactions,
) {
  final totals = <int, LinkedCreditTotal>{};
  for (final transaction in transactions) {
    final originalId = transaction.refundOfId;
    if (originalId == null || !RefundTx.isLinkedCredit(transaction.type)) {
      continue;
    }
    final current = totals[originalId] ?? (refund: 0.0, reimburse: 0.0);
    totals[originalId] = (
      refund: current.refund +
          (RefundTx.isRefund(transaction.type) ? transaction.amount : 0),
      reimburse: current.reimburse +
          (ReimburseTx.isReimburse(transaction.type) ? transaction.amount : 0),
    );
  }
  return totals;
}

double transactionStatTotalInRange(
  Iterable<Transaction> transactions, {
  required String type,
  required DateTime start,
  required DateTime end,
}) {
  final rows = transactions
      .where((transaction) => !transaction.excludeFromStats)
      .toList(growable: false);
  final linkedTotals = linkedCreditTotals(rows);

  var total = 0.0;
  for (final transaction in rows) {
    if (transaction.type != type ||
        transaction.happenedAt.isBefore(start) ||
        !transaction.happenedAt.isBefore(end)) {
      continue;
    }
    if (type == 'expense') {
      final linked = linkedTotals[transaction.id];
      final net =
          transaction.amount - (linked?.refund ?? 0) - (linked?.reimburse ?? 0);
      total += net > 0 ? net : 0;
    } else {
      total += transaction.amount;
    }
  }
  return total;
}

final linkedCreditTotalsProvider = StreamProvider.autoDispose
    .family<Map<int, LinkedCreditTotal>, int>((ref, ledgerId) {
  final repository = ref.watch(repositoryProvider);
  return repository
      .watchTransactionsWithCategoryAll(ledgerId: ledgerId)
      .map((rows) => linkedCreditTotals(rows.map((row) => row.t)));
});
