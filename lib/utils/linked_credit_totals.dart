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

final linkedCreditTotalsProvider = StreamProvider.autoDispose
    .family<Map<int, LinkedCreditTotal>, int>((ref, ledgerId) {
  final repository = ref.watch(repositoryProvider);
  return repository
      .watchTransactionsWithCategoryAll(ledgerId: ledgerId)
      .map((rows) => linkedCreditTotals(rows.map((row) => row.t)));
});
