import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart';
import '../pages/account/investment_record_page.dart';
import '../pages/transaction/transaction_editor_page.dart';
import '../providers/database_providers.dart';
import 'invest_tx.dart';

class TransactionEditUtils {
  static Future<void> editTransaction(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
    Category? category,
  ) async {
    final repo = ref.read(repositoryProvider);
    final tags = await repo.getTagsForTransaction(transaction.id);
    final tagIds = tags.map((t) => t.id).toList();

    if (!context.mounted) return;

    if (InvestTx.isPnlType(transaction.type)) {
      final accountId = transaction.accountId;
      Account? account;
      if (accountId != null) {
        account = await repo.getAccount(accountId);
      }
      if (!context.mounted || account == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvestmentRecordPage(
            account: account!,
            kind: InvestmentRecordKind.edit,
            editing: transaction,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: transaction.type,
          quickAdd: true,
          initialCategoryId: transaction.categoryId,
          initialAmount: transaction.amount,
          initialDate: transaction.happenedAt,
          initialNote: transaction.note,
          editingTransactionId: transaction.id,
          initialAccountId: transaction.accountId,
          initialToAccountId: transaction.toAccountId,
          initialTagIds: tagIds,
        ),
      ),
    );
  }
}
