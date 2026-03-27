import 'package:drift/drift.dart' as d;

import '../../db.dart';
import '../local/local_repository.dart';
import '../../../services/sync/beecount_sync_engine.dart';

class BeeCountSyncingRepository extends LocalRepository {
  BeeCountSyncingRepository(super.db, {required this.sync});

  final BeeCountSyncEngine sync;

  @override
  Future<int> createLedger({required String name, String currency = 'CNY'}) async {
    final id = await super.createLedger(name: name, currency: currency);
    await sync.enqueueUpsert('ledgers', id);
    return id;
  }

  @override
  Future<void> updateLedgerName({required int id, required String name}) async {
    await super.updateLedgerName(id: id, name: name);
    await sync.enqueueUpsert('ledgers', id);
  }

  @override
  Future<void> updateLedger({required int id, String? name, String? currency}) async {
    await super.updateLedger(id: id, name: name, currency: currency);
    await sync.enqueueUpsert('ledgers', id);
  }

  @override
  Future<void> deleteLedger(int id) async {
    await super.deleteLedger(id);
    await sync.enqueueDelete('ledgers', id);
  }

  @override
  Future<int> addTransaction({
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    required DateTime happenedAt,
    String? note,
  }) async {
    final id = await super.addTransaction(
      ledgerId: ledgerId,
      type: type,
      amount: amount,
      categoryId: categoryId,
      accountId: accountId,
      toAccountId: toAccountId,
      happenedAt: happenedAt,
      note: note,
    );
    await sync.enqueueUpsert('transactions', id);
    return id;
  }

  @override
  Future<int> insertTransactionCompanion(TransactionsCompanion item) async {
    final id = await super.insertTransactionCompanion(item);
    await sync.enqueueUpsert('transactions', id);
    return id;
  }

  @override
  Future<int> insertTransactionsBatch(List<TransactionsCompanion> items) async {
    final count = await super.insertTransactionsBatch(items);
    final inserted = await super.db.select(super.db.transactions).get();
    for (final tx in inserted) {
      await sync.enqueueUpsert('transactions', tx.id);
    }
    return count;
  }

  @override
  Future<void> updateTransaction({
    required int id,
    required String type,
    required double amount,
    int? categoryId,
    String? note,
    DateTime? happenedAt,
    dynamic accountId,
  }) async {
    await super.updateTransaction(
      id: id,
      type: type,
      amount: amount,
      categoryId: categoryId,
      note: note,
      happenedAt: happenedAt,
      accountId: accountId,
    );
    await sync.enqueueUpsert('transactions', id);
  }

  @override
  Future<void> updateTransactionFields({
    required int id,
    int? accountId,
    int? toAccountId,
  }) async {
    await super.updateTransactionFields(id: id, accountId: accountId, toAccountId: toAccountId);
    await sync.enqueueUpsert('transactions', id);
  }

  @override
  Future<void> updateTransactionLedger({required int id, required int ledgerId}) async {
    await super.updateTransactionLedger(id: id, ledgerId: ledgerId);
    await sync.enqueueUpsert('transactions', id);
  }

  @override
  Future<void> deleteTransaction(int id) async {
    await super.deleteTransaction(id);
    await sync.enqueueDelete('transactions', id);
  }

  @override
  Future<int> createCategory({
    required String name,
    required String kind,
    String? icon,
    int? sortOrder,
  }) async {
    final id = await super.createCategory(
      name: name,
      kind: kind,
      icon: icon,
      sortOrder: sortOrder,
    );
    await sync.enqueueUpsert('categories', id);
    return id;
  }

  @override
  Future<int> createSubCategory({
    required int parentId,
    required String name,
    required String kind,
    String? icon,
    int? sortOrder,
  }) async {
    final id = await super.createSubCategory(
      parentId: parentId,
      name: name,
      kind: kind,
      icon: icon,
      sortOrder: sortOrder,
    );
    await sync.enqueueUpsert('categories', id);
    return id;
  }

  @override
  Future<void> updateCategory(
    int id, {
    String? name,
    String? icon,
    int? parentId,
    int? level,
  }) async {
    await super.updateCategory(
      id,
      name: name,
      icon: icon,
      parentId: parentId,
      level: level,
    );
    await sync.enqueueUpsert('categories', id);
  }

  @override
  Future<void> updateCategoryIcon(
    int id, {
    required String iconType,
    String? icon,
    String? customIconPath,
    String? communityIconId,
  }) async {
    await super.updateCategoryIcon(
      id,
      iconType: iconType,
      icon: icon,
      customIconPath: customIconPath,
      communityIconId: communityIconId,
    );
    await sync.enqueueUpsert('categories', id);
  }

  @override
  Future<void> clearCategoryCustomIcon(int id, {String? materialIcon}) async {
    await super.clearCategoryCustomIcon(id, materialIcon: materialIcon);
    await sync.enqueueUpsert('categories', id);
  }

  @override
  Future<void> deleteCategory(int id) async {
    await super.deleteCategory(id);
    await sync.enqueueDelete('categories', id);
  }

  @override
  Future<void> deleteCategoriesByIds(List<int> ids) async {
    await super.deleteCategoriesByIds(ids);
    for (final id in ids) {
      await sync.enqueueDelete('categories', id);
    }
  }

  @override
  Future<void> updateCategorySortOrders(List<({int id, int sortOrder})> updates) async {
    await super.updateCategorySortOrders(updates);
    for (final u in updates) {
      await sync.enqueueUpsert('categories', u.id);
    }
  }

  @override
  Future<void> batchInsertCategories(List<CategoriesCompanion> categories) async {
    await super.batchInsertCategories(categories);
    final rows = await super.db.select(super.db.categories).get();
    for (final c in rows) {
      await sync.enqueueUpsert('categories', c.id);
    }
  }

  @override
  Future<int> insertCategory(CategoriesCompanion category) async {
    final id = await super.insertCategory(category);
    await sync.enqueueUpsert('categories', id);
    return id;
  }

  @override
  Future<int> createTag({required String name, String? color, int sortOrder = 0}) async {
    final id = await super.createTag(name: name, color: color, sortOrder: sortOrder);
    await sync.enqueueUpsert('tags', id);
    return id;
  }

  @override
  Future<void> updateTag(int id, {String? name, String? color, int? sortOrder}) async {
    await super.updateTag(id, name: name, color: color, sortOrder: sortOrder);
    await sync.enqueueUpsert('tags', id);
  }

  @override
  Future<void> deleteTag(int id) async {
    await super.deleteTag(id);
    await sync.enqueueDelete('tags', id);
  }

  @override
  Future<void> batchInsertTags(List<TagsCompanion> tags) async {
    await super.batchInsertTags(tags);
    final rows = await super.db.select(super.db.tags).get();
    for (final t in rows) {
      await sync.enqueueUpsert('tags', t.id);
    }
  }

  @override
  Future<void> addTagToTransaction({required int transactionId, required int tagId}) async {
    await super.addTagToTransaction(transactionId: transactionId, tagId: tagId);
    final row = await (super.db.select(super.db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId) & t.tagId.equals(tagId))
          ..orderBy([(t) => d.OrderingTerm(expression: t.id, mode: d.OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    if (row != null) {
      await sync.enqueueUpsert('transaction_tags', row.id);
    }
  }

  @override
  Future<void> addTagsToTransaction({required int transactionId, required List<int> tagIds}) async {
    await super.addTagsToTransaction(transactionId: transactionId, tagIds: tagIds);
    final rows = await (super.db.select(super.db.transactionTags)..where((t) => t.transactionId.equals(transactionId))).get();
    for (final r in rows) {
      await sync.enqueueUpsert('transaction_tags', r.id);
    }
  }

  @override
  Future<void> removeTagFromTransaction({required int transactionId, required int tagId}) async {
    final rows = await (super.db.select(super.db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId) & t.tagId.equals(tagId)))
        .get();
    await super.removeTagFromTransaction(transactionId: transactionId, tagId: tagId);
    for (final r in rows) {
      await sync.enqueueDelete('transaction_tags', r.id);
    }
  }

  @override
  Future<void> removeAllTagsFromTransaction(int transactionId) async {
    final rows = await (super.db.select(super.db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
    await super.removeAllTagsFromTransaction(transactionId);
    for (final r in rows) {
      await sync.enqueueDelete('transaction_tags', r.id);
    }
  }

  @override
  Future<void> updateTransactionTags({required int transactionId, required List<int> tagIds}) async {
    final before = await (super.db.select(super.db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
    await super.updateTransactionTags(transactionId: transactionId, tagIds: tagIds);
    for (final r in before) {
      await sync.enqueueDelete('transaction_tags', r.id);
    }
    final after = await (super.db.select(super.db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
    for (final r in after) {
      await sync.enqueueUpsert('transaction_tags', r.id);
    }
  }

  @override
  Future<int> createAccount({
    required int ledgerId,
    required String name,
    String type = 'cash',
    String currency = 'CNY',
    double initialBalance = 0.0,
  }) async {
    final id = await super.createAccount(
      ledgerId: ledgerId,
      name: name,
      type: type,
      currency: currency,
      initialBalance: initialBalance,
    );
    await sync.enqueueUpsert('accounts', id);
    return id;
  }

  @override
  Future<void> updateAccount(
    int id, {
    String? name,
    String? type,
    String? currency,
    double? initialBalance,
  }) async {
    await super.updateAccount(
      id,
      name: name,
      type: type,
      currency: currency,
      initialBalance: initialBalance,
    );
    await sync.enqueueUpsert('accounts', id);
  }

  @override
  Future<void> deleteAccount(int id) async {
    await super.deleteAccount(id);
    await sync.enqueueDelete('accounts', id);
  }

  @override
  Future<void> batchInsertAccounts(List<AccountsCompanion> accounts) async {
    await super.batchInsertAccounts(accounts);
    final rows = await super.db.select(super.db.accounts).get();
    for (final a in rows) {
      await sync.enqueueUpsert('accounts', a.id);
    }
  }

  @override
  Future<int> migrateAccount({required int fromAccountId, required int toAccountId}) async {
    final changedTxs = await (super.db.select(super.db.transactions)
          ..where((t) => t.accountId.equals(fromAccountId) | t.toAccountId.equals(fromAccountId)))
        .get();
    final migrated = await super.migrateAccount(fromAccountId: fromAccountId, toAccountId: toAccountId);
    for (final tx in changedTxs) {
      await sync.enqueueUpsert('transactions', tx.id);
    }
    return migrated;
  }

  @override
  Future<int> createBudget({
    required int ledgerId,
    required int year,
    required int month,
    int? categoryId,
    required double amount,
    required bool prompt,
    int? promptDay,
    bool? ignored,
  }) async {
    final id = await super.createBudget(
      ledgerId: ledgerId,
      year: year,
      month: month,
      categoryId: categoryId,
      amount: amount,
      prompt: prompt,
      promptDay: promptDay,
      ignored: ignored,
    );
    await sync.enqueueUpsert('budgets', id);
    return id;
  }

  @override
  Future<void> updateBudget(
    int id, {
    double? amount,
    int? startDay,
    bool? enabled,
  }) async {
    await super.updateBudget(id, amount: amount, startDay: startDay, enabled: enabled);
    await sync.enqueueUpsert('budgets', id);
  }

  @override
  Future<void> deleteBudget(int id) async {
    await super.deleteBudget(id);
    await sync.enqueueDelete('budgets', id);
  }

  @override
  Future<int> addRecurringTransaction({
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    String? note,
    required String frequency,
    required int interval,
    int? dayOfMonth,
    int? dayOfWeek,
    int? monthOfYear,
    required DateTime startDate,
    DateTime? endDate,
    bool enabled = true,
  }) async {
    final id = await super.addRecurringTransaction(
      ledgerId: ledgerId,
      type: type,
      amount: amount,
      categoryId: categoryId,
      accountId: accountId,
      toAccountId: toAccountId,
      note: note,
      frequency: frequency,
      interval: interval,
      dayOfMonth: dayOfMonth,
      dayOfWeek: dayOfWeek,
      monthOfYear: monthOfYear,
      startDate: startDate,
      endDate: endDate,
      enabled: enabled,
    );
    await sync.enqueueUpsert('recurring_transactions', id);
    return id;
  }

  @override
  Future<void> updateRecurringTransaction({
    required int id,
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    String? note,
    required String frequency,
    required int interval,
    int? dayOfMonth,
    int? dayOfWeek,
    int? monthOfYear,
    required DateTime startDate,
    DateTime? endDate,
    bool? enabled,
    DateTime? lastGeneratedDate,
  }) async {
    await super.updateRecurringTransaction(
      id: id,
      ledgerId: ledgerId,
      type: type,
      amount: amount,
      categoryId: categoryId,
      accountId: accountId,
      toAccountId: toAccountId,
      note: note,
      frequency: frequency,
      interval: interval,
      dayOfMonth: dayOfMonth,
      dayOfWeek: dayOfWeek,
      monthOfYear: monthOfYear,
      startDate: startDate,
      endDate: endDate,
      enabled: enabled,
      lastGeneratedDate: lastGeneratedDate,
    );
    await sync.enqueueUpsert('recurring_transactions', id);
  }

  @override
  Future<void> deleteRecurringTransaction(int id) async {
    await super.deleteRecurringTransaction(id);
    await sync.enqueueDelete('recurring_transactions', id);
  }

  // ============================================
  // ReceivablePayableRepository 接口覆盖 - 添加同步支持
  // ============================================

  @override
  Future<int> createReceivable({
    required int accountId,
    required String borrowerName,
    required double amount,
    required DateTime borrowDate,
    String? note,
    required int fromAccountId,
    bool isReceived = false,
    DateTime? receiveDate,
    int? toAccountId,
  }) async {
    final id = await super.createReceivable(
      accountId: accountId,
      borrowerName: borrowerName,
      amount: amount,
      borrowDate: borrowDate,
      note: note,
      fromAccountId: fromAccountId,
      isReceived: isReceived,
      receiveDate: receiveDate,
      toAccountId: toAccountId,
    );
    await sync.enqueueUpsert('receivables', id);
    return id;
  }

  @override
  Future<void> updateReceivable({
    required int id,
    String? borrowerName,
    double? amount,
    DateTime? borrowDate,
    String? note,
    int? fromAccountId,
    bool? isReceived,
    DateTime? receiveDate,
    int? toAccountId,
    DateTime? updatedAt,
  }) async {
    await super.updateReceivable(
      id: id,
      borrowerName: borrowerName,
      amount: amount,
      borrowDate: borrowDate,
      note: note,
      fromAccountId: fromAccountId,
      isReceived: isReceived,
      receiveDate: receiveDate,
      toAccountId: toAccountId,
      updatedAt: updatedAt,
    );
    await sync.enqueueUpsert('receivables', id);
  }

  @override
  Future<void> deleteReceivable(int id) async {
    await super.deleteReceivable(id);
    await sync.enqueueDelete('receivables', id);
  }

  @override
  Future<int> createPayable({
    required int accountId,
    required String payeeName,
    required double amount,
    required DateTime payDate,
    String? note,
    required int toAccountId,
    bool isPaid = false,
    DateTime? paidDate,
    int? fromAccountId,
  }) async {
    final id = await super.createPayable(
      accountId: accountId,
      payeeName: payeeName,
      amount: amount,
      payDate: payDate,
      note: note,
      toAccountId: toAccountId,
      isPaid: isPaid,
      paidDate: paidDate,
      fromAccountId: fromAccountId,
    );
    await sync.enqueueUpsert('payables', id);
    return id;
  }

  @override
  Future<void> updatePayable({
    required int id,
    String? payeeName,
    double? amount,
    DateTime? payDate,
    String? note,
    int? toAccountId,
    bool? isPaid,
    DateTime? paidDate,
    int? fromAccountId,
    DateTime? updatedAt,
  }) async {
    await super.updatePayable(
      id: id,
      payeeName: payeeName,
      amount: amount,
      payDate: payDate,
      note: note,
      toAccountId: toAccountId,
      isPaid: isPaid,
      paidDate: paidDate,
      fromAccountId: fromAccountId,
      updatedAt: updatedAt,
    );
    await sync.enqueueUpsert('payables', id);
  }

  @override
  Future<void> deletePayable(int id) async {
    await super.deletePayable(id);
    await sync.enqueueDelete('payables', id);
  }
}
