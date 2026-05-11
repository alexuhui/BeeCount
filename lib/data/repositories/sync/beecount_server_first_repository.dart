import '../../db.dart';
import 'beecount_syncing_repository.dart';

/// BeeCount server-first repository.
///
/// Writes still reuse the existing local repository + sync payload builders, but
/// the local Drift transaction is only committed after the corresponding remote
/// flush succeeds. If the server rejects the write or the queue item remains
/// pending, the transaction throws and the local business row is rolled back.
class BeeCountServerFirstRepository extends BeeCountSyncingRepository {
  BeeCountServerFirstRepository(super.db, {required super.sync});

  Future<T> _serverFirst<T>(
    Future<T> Function() action, {
    List<_QueueKey> Function(T result)? touched,
  }) {
    return db.transaction(() async {
      final existing = await _pendingKeys();
      if (existing.isNotEmpty) {
        await sync.flush();
        final remaining = await _pendingKeys();
        if (remaining.isNotEmpty) {
          throw Exception(
            '存在历史待同步数据，服务器优先写入已暂停: '
            '${remaining.map((e) => '${e.entity}:${e.localId}').join(', ')}',
          );
        }
      }

      final before = await _pendingKeys();
      final result = await action();
      final expectedTouched = touched?.call(result) ?? const <_QueueKey>[];

      await sync.flush();

      final after = await _pendingKeys();
      final remainingTouched = expectedTouched.where(after.contains).toList();
      if (remainingTouched.isNotEmpty) {
        throw Exception(
          '服务器保存未完成，本地数据未入库: '
          '${remainingTouched.map((e) => '${e.entity}:${e.localId}').join(', ')}',
        );
      }

      final added = after.difference(before);
      if (added.isNotEmpty) {
        throw Exception(
          '服务器保存未完成，本地数据未入库: '
          '${added.map((e) => '${e.entity}:${e.localId}').join(', ')}',
        );
      }

      return result;
    });
  }

  Future<Set<_QueueKey>> _pendingKeys() async {
    await _ensureSyncTables();
    final rows = await db
        .customSelect(
          'SELECT entity, local_id FROM sync_queue_items',
        )
        .get();
    return rows
        .map(
          (r) => _QueueKey(
            r.data['entity'] as String,
            (r.data['local_id'] as num).toInt(),
          ),
        )
        .toSet();
  }

  Future<void> _ensureSyncTables() async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_queue_items (
        entity TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        payload TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        PRIMARY KEY (entity, local_id)
      );
    ''');
  }

  Future<void> _flushOnly(
      Future<void> Function() action, List<_QueueKey> touched) {
    return _serverFirst<void>(
      () async => action(),
      touched: (_) => touched,
    );
  }

  @override
  Future<int> createLedger({required String name, String currency = 'CNY'}) {
    return _serverFirst(
      () => super.createLedger(name: name, currency: currency),
      touched: (id) => [_QueueKey('ledgers', id)],
    );
  }

  @override
  Future<void> updateLedgerName({required int id, required String name}) {
    return _flushOnly(
      () => super.updateLedgerName(id: id, name: name),
      [_QueueKey('ledgers', id)],
    );
  }

  @override
  Future<void> updateLedger({required int id, String? name, String? currency}) {
    return _flushOnly(
      () => super.updateLedger(id: id, name: name, currency: currency),
      [_QueueKey('ledgers', id)],
    );
  }

  @override
  Future<void> deleteLedger(int id) {
    return _flushOnly(() => super.deleteLedger(id), [_QueueKey('ledgers', id)]);
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
  }) {
    return _serverFirst(
      () => super.addTransaction(
        ledgerId: ledgerId,
        type: type,
        amount: amount,
        categoryId: categoryId,
        accountId: accountId,
        toAccountId: toAccountId,
        happenedAt: happenedAt,
        note: note,
      ),
      touched: (id) => [_QueueKey('transactions', id)],
    );
  }

  @override
  Future<int> insertTransactionCompanion(TransactionsCompanion item) {
    return _serverFirst(
      () => super.insertTransactionCompanion(item),
      touched: (id) => [_QueueKey('transactions', id)],
    );
  }

  @override
  Future<int> insertTransactionsBatch(List<TransactionsCompanion> items) {
    return _serverFirst(() => super.insertTransactionsBatch(items));
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
  }) {
    return _flushOnly(
      () => super.updateTransaction(
        id: id,
        type: type,
        amount: amount,
        categoryId: categoryId,
        note: note,
        happenedAt: happenedAt,
        accountId: accountId,
      ),
      [_QueueKey('transactions', id)],
    );
  }

  @override
  Future<void> updateTransactionFields({
    required int id,
    int? accountId,
    int? toAccountId,
  }) {
    return _flushOnly(
      () => super.updateTransactionFields(
        id: id,
        accountId: accountId,
        toAccountId: toAccountId,
      ),
      [_QueueKey('transactions', id)],
    );
  }

  @override
  Future<void> updateTransactionLedger(
      {required int id, required int ledgerId}) {
    return _flushOnly(
      () => super.updateTransactionLedger(id: id, ledgerId: ledgerId),
      [_QueueKey('transactions', id)],
    );
  }

  @override
  Future<void> deleteTransaction(int id) {
    return _flushOnly(
      () => super.deleteTransaction(id),
      [_QueueKey('transactions', id)],
    );
  }

  @override
  Future<int> createCategory({
    required String name,
    required String kind,
    String? icon,
    int? sortOrder,
  }) {
    return _serverFirst(
      () => super.createCategory(
        name: name,
        kind: kind,
        icon: icon,
        sortOrder: sortOrder,
      ),
      touched: (id) => [_QueueKey('categories', id)],
    );
  }

  @override
  Future<int> createSubCategory({
    required int parentId,
    required String name,
    required String kind,
    String? icon,
    int? sortOrder,
  }) {
    return _serverFirst(
      () => super.createSubCategory(
        parentId: parentId,
        name: name,
        kind: kind,
        icon: icon,
        sortOrder: sortOrder,
      ),
      touched: (id) => [_QueueKey('categories', id)],
    );
  }

  @override
  Future<void> updateCategory(
    int id, {
    String? name,
    String? icon,
    int? parentId,
    int? level,
  }) {
    return _flushOnly(
      () => super.updateCategory(
        id,
        name: name,
        icon: icon,
        parentId: parentId,
        level: level,
      ),
      [_QueueKey('categories', id)],
    );
  }

  @override
  Future<void> updateCategoryIcon(
    int id, {
    required String iconType,
    String? icon,
    String? customIconPath,
    String? communityIconId,
  }) {
    return _flushOnly(
      () => super.updateCategoryIcon(
        id,
        iconType: iconType,
        icon: icon,
        customIconPath: customIconPath,
        communityIconId: communityIconId,
      ),
      [_QueueKey('categories', id)],
    );
  }

  @override
  Future<void> clearCategoryCustomIcon(int id, {String? materialIcon}) {
    return _flushOnly(
      () => super.clearCategoryCustomIcon(id, materialIcon: materialIcon),
      [_QueueKey('categories', id)],
    );
  }

  @override
  Future<void> deleteCategory(int id) {
    return _flushOnly(
        () => super.deleteCategory(id), [_QueueKey('categories', id)]);
  }

  @override
  Future<void> deleteCategoriesByIds(List<int> ids) {
    return _flushOnly(
      () => super.deleteCategoriesByIds(ids),
      ids.map((id) => _QueueKey('categories', id)).toList(),
    );
  }

  @override
  Future<void> updateCategorySortOrders(
      List<({int id, int sortOrder})> updates) {
    return _flushOnly(
      () => super.updateCategorySortOrders(updates),
      updates.map((u) => _QueueKey('categories', u.id)).toList(),
    );
  }

  @override
  Future<void> batchInsertCategories(List<CategoriesCompanion> categories) {
    return _serverFirst(() => super.batchInsertCategories(categories));
  }

  @override
  Future<int> insertCategory(CategoriesCompanion category) {
    return _serverFirst(
      () => super.insertCategory(category),
      touched: (id) => [_QueueKey('categories', id)],
    );
  }

  @override
  Future<int> createTag({
    required String name,
    String? color,
    int sortOrder = 0,
  }) {
    return _serverFirst(
      () => super.createTag(name: name, color: color, sortOrder: sortOrder),
      touched: (id) => [_QueueKey('tags', id)],
    );
  }

  @override
  Future<void> updateTag(int id,
      {String? name, String? color, int? sortOrder}) {
    return _flushOnly(
      () => super.updateTag(id, name: name, color: color, sortOrder: sortOrder),
      [_QueueKey('tags', id)],
    );
  }

  @override
  Future<void> deleteTag(int id) {
    return _flushOnly(() => super.deleteTag(id), [_QueueKey('tags', id)]);
  }

  @override
  Future<void> batchInsertTags(List<TagsCompanion> tags) {
    return _serverFirst(() => super.batchInsertTags(tags));
  }

  @override
  Future<void> addTagToTransaction({
    required int transactionId,
    required int tagId,
  }) {
    return _serverFirst(
      () => super.addTagToTransaction(
        transactionId: transactionId,
        tagId: tagId,
      ),
    );
  }

  @override
  Future<void> addTagsToTransaction({
    required int transactionId,
    required List<int> tagIds,
  }) {
    return _serverFirst(
      () => super.addTagsToTransaction(
        transactionId: transactionId,
        tagIds: tagIds,
      ),
    );
  }

  @override
  Future<void> removeTagFromTransaction({
    required int transactionId,
    required int tagId,
  }) {
    return _serverFirst(
      () => super.removeTagFromTransaction(
        transactionId: transactionId,
        tagId: tagId,
      ),
    );
  }

  @override
  Future<void> removeAllTagsFromTransaction(int transactionId) {
    return _serverFirst(
        () => super.removeAllTagsFromTransaction(transactionId));
  }

  @override
  Future<void> updateTransactionTags({
    required int transactionId,
    required List<int> tagIds,
  }) {
    return _serverFirst(
      () => super.updateTransactionTags(
        transactionId: transactionId,
        tagIds: tagIds,
      ),
    );
  }

  @override
  Future<int> createAccount({
    required int ledgerId,
    required String name,
    String type = 'cash',
    String currency = 'CNY',
    double initialBalance = 0.0,
  }) {
    return _serverFirst(
      () => super.createAccount(
        ledgerId: ledgerId,
        name: name,
        type: type,
        currency: currency,
        initialBalance: initialBalance,
      ),
      touched: (id) => [_QueueKey('accounts', id)],
    );
  }

  @override
  Future<void> updateAccount(
    int id, {
    String? name,
    String? type,
    String? currency,
    double? initialBalance,
  }) {
    return _flushOnly(
      () => super.updateAccount(
        id,
        name: name,
        type: type,
        currency: currency,
        initialBalance: initialBalance,
      ),
      [_QueueKey('accounts', id)],
    );
  }

  @override
  Future<void> deleteAccount(int id) {
    return _flushOnly(
        () => super.deleteAccount(id), [_QueueKey('accounts', id)]);
  }

  @override
  Future<void> batchInsertAccounts(List<AccountsCompanion> accounts) {
    return _serverFirst(() => super.batchInsertAccounts(accounts));
  }

  @override
  Future<int> migrateAccount({
    required int fromAccountId,
    required int toAccountId,
  }) {
    return _serverFirst(
      () => super.migrateAccount(
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
      ),
    );
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
  }) {
    return _serverFirst(
      () => super.createBudget(
        ledgerId: ledgerId,
        year: year,
        month: month,
        categoryId: categoryId,
        amount: amount,
        prompt: prompt,
        promptDay: promptDay,
        ignored: ignored,
      ),
      touched: (id) => [_QueueKey('budgets', id)],
    );
  }

  @override
  Future<void> updateBudget(
    int id, {
    double? amount,
    int? startDay,
    bool? enabled,
  }) {
    return _flushOnly(
      () => super.updateBudget(id,
          amount: amount, startDay: startDay, enabled: enabled),
      [_QueueKey('budgets', id)],
    );
  }

  @override
  Future<void> deleteBudget(int id) {
    return _flushOnly(() => super.deleteBudget(id), [_QueueKey('budgets', id)]);
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
  }) {
    return _serverFirst(
      () => super.addRecurringTransaction(
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
      ),
      touched: (id) => [_QueueKey('recurring_transactions', id)],
    );
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
  }) {
    return _flushOnly(
      () => super.updateRecurringTransaction(
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
      ),
      [_QueueKey('recurring_transactions', id)],
    );
  }

  @override
  Future<void> deleteRecurringTransaction(int id) {
    return _flushOnly(
      () => super.deleteRecurringTransaction(id),
      [_QueueKey('recurring_transactions', id)],
    );
  }

  @override
  Future<int> createReceivable({
    required int accountId,
    required String borrowerName,
    required double amount,
    required DateTime borrowDate,
    String? note,
    int? fromAccountId,
    bool isReceived = false,
    DateTime? receiveDate,
    int? toAccountId,
  }) {
    return _serverFirst(
      () => super.createReceivable(
        accountId: accountId,
        borrowerName: borrowerName,
        amount: amount,
        borrowDate: borrowDate,
        note: note,
        fromAccountId: fromAccountId,
        isReceived: isReceived,
        receiveDate: receiveDate,
        toAccountId: toAccountId,
      ),
      touched: (id) => [_QueueKey('receivables', id)],
    );
  }

  @override
  Future<void> updateReceivable({
    required int id,
    String? borrowerName,
    double? amount,
    DateTime? borrowDate,
    String? note,
    int? fromAccountId,
    bool applyFromAccountId = false,
    bool? isReceived,
    DateTime? receiveDate,
    int? toAccountId,
    DateTime? updatedAt,
  }) {
    return _flushOnly(
      () => super.updateReceivable(
        id: id,
        borrowerName: borrowerName,
        amount: amount,
        borrowDate: borrowDate,
        note: note,
        fromAccountId: fromAccountId,
        applyFromAccountId: applyFromAccountId,
        isReceived: isReceived,
        receiveDate: receiveDate,
        toAccountId: toAccountId,
        updatedAt: updatedAt,
      ),
      [_QueueKey('receivables', id)],
    );
  }

  @override
  Future<void> deleteReceivable(int id) {
    return _flushOnly(
        () => super.deleteReceivable(id), [_QueueKey('receivables', id)]);
  }

  @override
  Future<int> createPayable({
    required int accountId,
    required String payeeName,
    required double amount,
    required DateTime payDate,
    String? note,
    int? toAccountId,
    bool isPaid = false,
    DateTime? paidDate,
    int? fromAccountId,
  }) {
    return _serverFirst(
      () => super.createPayable(
        accountId: accountId,
        payeeName: payeeName,
        amount: amount,
        payDate: payDate,
        note: note,
        toAccountId: toAccountId,
        isPaid: isPaid,
        paidDate: paidDate,
        fromAccountId: fromAccountId,
      ),
      touched: (id) => [_QueueKey('payables', id)],
    );
  }

  @override
  Future<void> updatePayable({
    required int id,
    String? payeeName,
    double? amount,
    DateTime? payDate,
    String? note,
    int? toAccountId,
    bool applyToAccountId = false,
    bool? isPaid,
    DateTime? paidDate,
    int? fromAccountId,
    DateTime? updatedAt,
  }) {
    return _flushOnly(
      () => super.updatePayable(
        id: id,
        payeeName: payeeName,
        amount: amount,
        payDate: payDate,
        note: note,
        toAccountId: toAccountId,
        applyToAccountId: applyToAccountId,
        isPaid: isPaid,
        paidDate: paidDate,
        fromAccountId: fromAccountId,
        updatedAt: updatedAt,
      ),
      [_QueueKey('payables', id)],
    );
  }

  @override
  Future<void> deletePayable(int id) {
    return _flushOnly(
        () => super.deletePayable(id), [_QueueKey('payables', id)]);
  }

  @override
  Future<int> addReceivablePayment({
    required int receivableId,
    required double amount,
    double interestAmount = 0.0,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  }) {
    return _serverFirst(
      () => super.addReceivablePayment(
        receivableId: receivableId,
        amount: amount,
        interestAmount: interestAmount,
        happenedAt: happenedAt,
        accountId: accountId,
        note: note,
      ),
      touched: (id) => [_QueueKey('receivable_payments', id)],
    );
  }

  @override
  Future<void> deleteReceivablePayment(int id) {
    return _flushOnly(
      () => super.deleteReceivablePayment(id),
      [_QueueKey('receivable_payments', id)],
    );
  }

  @override
  Future<int> addPayablePayment({
    required int payableId,
    required double amount,
    double interestAmount = 0.0,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  }) {
    return _serverFirst(
      () => super.addPayablePayment(
        payableId: payableId,
        amount: amount,
        interestAmount: interestAmount,
        happenedAt: happenedAt,
        accountId: accountId,
        note: note,
      ),
      touched: (id) => [_QueueKey('payable_payments', id)],
    );
  }

  @override
  Future<void> deletePayablePayment(int id) {
    return _flushOnly(
      () => super.deletePayablePayment(id),
      [_QueueKey('payable_payments', id)],
    );
  }
}

class _QueueKey {
  const _QueueKey(this.entity, this.localId);

  final String entity;
  final int localId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _QueueKey && entity == other.entity && localId == other.localId;

  @override
  int get hashCode => Object.hash(entity, localId);
}
