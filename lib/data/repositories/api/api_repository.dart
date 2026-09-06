import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../config/page_sizes.dart';
import '../../../services/api/api_json.dart';
import '../../../services/api/beecount_api_client.dart';
import '../../category_node.dart';
import '../../db.dart';
import '../local/local_repository.dart';

/// Server-first repository: ledger data over HTTP, AI still uses local Drift.
class ApiRepository extends LocalRepository {
  ApiRepository(super.db, {required this.api});

  final BeeCountApiClient api;
  final _refresh = StreamController<void>.broadcast();

  void notifyChanged() {
    if (!_refresh.isClosed) _refresh.add(null);
  }

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    await for (final _ in _refresh.stream) {
      yield await load();
    }
  }

  Future<List<Map<String, dynamic>>> _allPages(
    String path, [
    Map<String, String?> extra = const {},
  ]) async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final r = await api.listPaged(
        path,
        page: page,
        pageSize: 200,
        extra: extra,
      );
      out.addAll(r.items);
      if (r.items.isEmpty || out.length >= r.total) break;
      page++;
    }
    return out;
  }

  Map<String, String?> _txQuery({
    int? ledgerId,
    DateTime? from,
    DateTime? to,
    String? type,
    int? categoryId,
    int? accountId,
    int? tagId,
    String? q,
  }) =>
      {
        if (ledgerId != null) 'ledger_id': '$ledgerId',
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
        if (type != null) 'type': type,
        if (categoryId != null) 'category_id': '$categoryId',
        if (accountId != null) 'account_id': '$accountId',
        if (tagId != null) 'tag_id': '$tagId',
        if (q != null && q.isNotEmpty) 'q': q,
      };

  List<Category>? _categoryCache;
  Future<List<Category>>? _categoryInFlight;
  int _categoryCacheGen = 0;

  Future<List<Category>> _cats({bool force = false}) {
    if (force) {
      _invalidateCategoryCache();
    } else {
      final cached = _categoryCache;
      if (cached != null) return Future<List<Category>>.value(cached);
      final inFlight = _categoryInFlight;
      if (inFlight != null) return inFlight;
    }

    final gen = _categoryCacheGen;
    final future = () async {
      final rows = await api.listAll('/categories');
      final list = rows.map(categoryFromJson).toList();
      if (gen == _categoryCacheGen) {
        _categoryCache = list;
      }
      return list;
    }();
    _categoryInFlight = future.whenComplete(() {
      if (identical(_categoryInFlight, future)) {
        _categoryInFlight = null;
      }
    });
    return future;
  }

  void _invalidateCategoryCache() {
    _categoryCache = null;
    _categoryInFlight = null;
    _categoryCacheGen++;
  }

  List<Account>? _accountCache;
  Future<List<Account>>? _accountInFlight;
  int _accountCacheGen = 0;

  Future<List<Account>> _accounts({bool force = false}) {
    if (force) {
      _invalidateAccountCache();
    } else {
      final cached = _accountCache;
      if (cached != null) return Future<List<Account>>.value(cached);
      final inFlight = _accountInFlight;
      if (inFlight != null) return inFlight;
    }

    final gen = _accountCacheGen;
    final future = () async {
      final rows = await api.listAll('/accounts');
      final list = rows.map(accountFromJson).toList();
      if (gen == _accountCacheGen) {
        _accountCache = list;
      }
      return list;
    }();
    _accountInFlight = future.whenComplete(() {
      if (identical(_accountInFlight, future)) {
        _accountInFlight = null;
      }
    });
    return future;
  }

  void _invalidateAccountCache() {
    _accountCache = null;
    _accountInFlight = null;
    _accountCacheGen++;
  }

  Future<Map<int, Category>> _catMap() async {
    final list = await _cats();
    return {for (final c in list) c.id: c};
  }

  Future<List<({Transaction t, Category? category})>> _withCats(
      List<Transaction> txs) async {
    final cats = await _catMap();
    return txs.map((t) => (t: t, category: cats[t.categoryId])).toList();
  }

  @override
  Stream<List<Ledger>> watchLedgers() => _watch(getAllLedgers);

  @override
  Future<List<Ledger>> getAllLedgers() async {
    final rows = await api.listAll('/ledgers');
    return rows.map(ledgerFromJson).toList();
  }

  @override
  Future<Ledger?> getLedgerById(int id) async {
    final all = await getAllLedgers();
    for (final l in all) {
      if (l.id == id) return l;
    }
    return null;
  }

  @override
  Future<int> getLedgerCount() async => (await getAllLedgers()).length;

  @override
  Future<int> ledgerCount() => getLedgerCount();

  @override
  Future<({int dayCount, int txCount})> getCountsForLedger(
      {required int ledgerId}) async {
    final data = await api.get('/ledgers/$ledgerId/counts');
    return (
      dayCount: asInt(data['dayCount']),
      txCount: asInt(data['txCount']),
    );
  }

  @override
  Future<({int dayCount, int txCount})> getCountsAll() async {
    var day = 0;
    var tx = 0;
    for (final l in await getAllLedgers()) {
      final c = await getCountsForLedger(ledgerId: l.id);
      day += c.dayCount;
      tx += c.txCount;
    }
    return (dayCount: day, txCount: tx);
  }

  @override
  Future<({double balance, int transactionCount})> getLedgerStats({
    required int ledgerId,
    bool accountFeatureEnabled = true,
    List<Transaction>? transactions,
  }) async {
    final data = await api.get('/ledgers/$ledgerId/stats');
    return (
      balance: asDouble(data['balance']),
      transactionCount: asInt(data['transactionCount']),
    );
  }

  @override
  Future<int> createLedger({required String name, String currency = 'CNY'}) async {
    final row = await api.post('/ledgers', {'name': name, 'currency': currency});
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<void> updateLedgerName({required int id, required String name}) async {
    await api.put('/ledgers/$id', {'name': name});
    notifyChanged();
  }

  @override
  Future<void> updateLedger(
      {required int id, String? name, String? currency}) async {
    await api.put('/ledgers/$id', {
      if (name != null) 'name': name,
      if (currency != null) 'currency': currency,
    });
    notifyChanged();
  }

  @override
  Future<void> deleteLedger(int id) async {
    await api.delete('/ledgers/$id');
    notifyChanged();
  }

  @override
  Future<int> getMaxLedgerId() async {
    final all = await getAllLedgers();
    if (all.isEmpty) return 0;
    return all.map((e) => e.id).reduce((a, b) => a > b ? a : b);
  }

  @override
  Future<int> getNextFreeLedgerId() async => (await getMaxLedgerId()) + 1;

  @override
  Future<void> reassignLedgerId({required int fromId, required int toId}) {
    throw UnsupportedError('Server assigns ledger ids');
  }

  @override
  Future<int> clearLedgerTransactions(int ledgerId) async {
    final exported = await api.get('/transactions/export');
    final items = asItemMaps(exported);
    var n = 0;
    for (final m in items) {
      if (asInt(m['ledger_id'] ?? m['ledgerId']) == ledgerId) {
        await api.delete('/transactions/${asInt(m['id'])}');
        n++;
      }
    }
    notifyChanged();
    return n;
  }

  @override
  Future<double> getTotalInitialBalance(int ledgerId) async {
    final accounts = await getAllAccounts();
    return accounts
        .where((a) => a.ledgerId == ledgerId)
        .fold<double>(0, (s, a) => s + a.initialBalance);
  }

  @override
  Future<({List<({Transaction t, Category? category})> items, int total})>
      fetchTransactionsPage({
    int? ledgerId,
    required int page,
    required int pageSize,
    DateTime? from,
    DateTime? to,
    String? type,
    int? categoryId,
    int? accountId,
    int? tagId,
    String? q,
  }) async {
    final paged = await api.listPaged(
      '/transactions',
      page: page,
      pageSize: pageSize,
      extra: _txQuery(
        ledgerId: ledgerId,
        from: from,
        to: to,
        type: type,
        categoryId: categoryId,
        accountId: accountId,
        tagId: tagId,
        q: q,
      ),
    );
    final txs = paged.items.map(txFromJson).toList();
    return (items: await _withCats(txs), total: paged.total);
  }

  @override
  Stream<List<Transaction>> watchRecentTransactions(
      {required int ledgerId, int limit = 20}) {
    return _watch(() async {
      final page = await fetchTransactionsPage(
        ledgerId: ledgerId,
        page: 1,
        pageSize: limit,
      );
      return page.items.map((e) => e.t).toList();
    });
  }

  @override
  Stream<List<Transaction>> watchTransactionsInMonth(
      {required int ledgerId, required DateTime month}) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return _watch(() async {
      final page = await fetchTransactionsPage(
        ledgerId: ledgerId,
        page: 1,
        pageSize: PageSizes.homeTransactions,
        from: start,
        to: end,
      );
      return page.items.map((e) => e.t).toList();
    });
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryAll({int? ledgerId}) {
    return _watch(() async {
      final page = await fetchTransactionsPage(
        ledgerId: ledgerId,
        page: 1,
        pageSize: PageSizes.homeTransactions,
      );
      return page.items;
    });
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      transactionsWithCategoryAll({int? ledgerId}) =>
          watchTransactionsWithCategoryAll(ledgerId: ledgerId);

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryInMonth({
    required int ledgerId,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return _watch(() async {
      final page = await fetchTransactionsPage(
        ledgerId: ledgerId,
        page: 1,
        pageSize: PageSizes.homeTransactions,
        from: start,
        to: end,
      );
      return page.items;
    });
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsWithCategoryInYear({
    required int ledgerId,
    required int year,
  }) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    return _watch(() async {
      final page = await fetchTransactionsPage(
        ledgerId: ledgerId,
        page: 1,
        pageSize: PageSizes.homeTransactions,
        from: start,
        to: end,
      );
      return page.items;
    });
  }

  @override
  Stream<List<({Transaction t, Category? category})>>
      watchTransactionsForCategoryInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
    int? categoryId,
    required String type,
  }) {
    return _watch(() async {
      final page = await fetchTransactionsPage(
        ledgerId: ledgerId,
        page: 1,
        pageSize: PageSizes.categoryDetail,
        from: start,
        to: end,
        type: type,
        categoryId: categoryId,
      );
      return page.items;
    });
  }

  @override
  Future<List<({Transaction t, Category? category})>>
      getRecentTransactionsWithCategory(
          {required int ledgerId, required int limit}) async {
    final page = await fetchTransactionsPage(
      ledgerId: ledgerId,
      page: 1,
      pageSize: limit,
    );
    return page.items;
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
    final row = await api.post('/transactions', {
      'ledger_id': ledgerId,
      'type': type,
      'amount': amount,
      'category_id': categoryId,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'happened_at': happenedAt.toIso8601String(),
      'note': note,
    });
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<int> insertTransactionCompanion(TransactionsCompanion item) {
    return addTransaction(
      ledgerId: item.ledgerId.value,
      type: item.type.value,
      amount: item.amount.value,
      categoryId: item.categoryId.present ? item.categoryId.value : null,
      accountId: item.accountId.present ? item.accountId.value : null,
      toAccountId: item.toAccountId.present ? item.toAccountId.value : null,
      happenedAt: item.happenedAt.present
          ? item.happenedAt.value
          : DateTime.now(),
      note: item.note.present ? item.note.value : null,
    );
  }

  @override
  Future<int> insertTransactionsBatch(List<TransactionsCompanion> items) async {
    var n = 0;
    for (final item in items) {
      await insertTransactionCompanion(item);
      n++;
    }
    return n;
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
    await api.put('/transactions/$id', {
      'type': type,
      'amount': amount,
      'category_id': categoryId,
      'note': note,
      if (happenedAt != null) 'happened_at': happenedAt.toIso8601String(),
      if (accountId != null) 'account_id': accountId,
    });
    notifyChanged();
  }

  @override
  Future<void> deleteTransaction(int id) async {
    await api.delete('/transactions/$id');
    notifyChanged();
  }

  @override
  Future<Transaction?> getTransactionById(int id) async {
    try {
      final row = await api.get('/transactions/$id');
      return txFromJson(row);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> countByTypeInRange({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final page = await fetchTransactionsPage(
      ledgerId: ledgerId,
      page: 1,
      pageSize: 1,
      from: start,
      to: end,
      type: type,
    );
    return page.total;
  }

  @override
  Future<List<Transaction>> getTransactionsByLedger(int ledgerId) async {
    final data = await api.get('/transactions/export',
        query: {'ledger_id': '$ledgerId'});
    return asItemMaps(data).map(txFromJson).toList();
  }

  @override
  Future<List<Transaction>> getTransactionsByLedgerInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    final data = await api.get('/transactions/export', query: {
      'ledger_id': '$ledgerId',
      'from': start.toIso8601String(),
      'to': end.toIso8601String(),
    });
    return asItemMaps(data).map(txFromJson).toList();
  }

  @override
  Future<void> updateTransactionFields({
    required int id,
    int? accountId,
    int? toAccountId,
  }) async {
    await api.put('/transactions/$id', {
      if (accountId != null) 'account_id': accountId,
      if (toAccountId != null) 'to_account_id': toAccountId,
    });
    notifyChanged();
  }

  @override
  Future<Transaction?> getFirstTransactionByLedger(int ledgerId) async {
    final list = await getTransactionsByLedger(ledgerId);
    if (list.isEmpty) return null;
    list.sort((a, b) => a.happenedAt.compareTo(b.happenedAt));
    return list.first;
  }

  @override
  Future<Transaction?> getLastTransactionByLedger(int ledgerId) async {
    final page = await fetchTransactionsPage(
      ledgerId: ledgerId,
      page: 1,
      pageSize: 1,
    );
    return page.items.isEmpty ? null : page.items.first.t;
  }

  @override
  Future<void> updateTransactionLedger(
      {required int id, required int ledgerId}) async {
    await api.put('/transactions/$id', {'ledger_id': ledgerId});
    notifyChanged();
  }

  @override
  Future<(double income, double expense)> totalsInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    final data = await _statsGet('/stats/range', {
      'ledger_id': '$ledgerId',
      'from': start.toIso8601String(),
      'to': end.toIso8601String(),
    });
    return (asDouble(data['income']), asDouble(data['expense']));
  }

  Future<Map<String, dynamic>> _statsGet(
      String path, Map<String, String> query) async {
    return api.get(path, query: query);
  }

  @override
  Future<(double income, double expense)> monthlyTotals({
    required int ledgerId,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return totalsInRange(ledgerId: ledgerId, start: start, end: end);
  }

  @override
  Future<(double income, double expense)> yearlyTotals({
    required int ledgerId,
    required int year,
  }) {
    return totalsInRange(
      ledgerId: ledgerId,
      start: DateTime(year, 1, 1),
      end: DateTime(year + 1, 1, 1),
    );
  }

  @override
  Future<List<({int? id, String name, String? icon, double total})>>
      totalsByCategory({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final data = await _statsGet('/stats/by_category', {
      'ledger_id': '$ledgerId',
      'type': type,
      'from': start.toIso8601String(),
      'to': end.toIso8601String(),
    });
    return asItemMaps(data)
        .map((m) => (
              id: asIntN(m['id']),
              name: '${m['name'] ?? ''}',
              icon: m['icon']?.toString(),
              total: asDouble(m['total']),
            ))
        .toList();
  }

  @override
  Future<
      List<
          ({
            int? id,
            String name,
            String? icon,
            int? parentId,
            int level,
            double total
          })>> totalsByCategoryWithHierarchy({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final data = await _statsGet('/stats/by_category', {
      'ledger_id': '$ledgerId',
      'type': type,
      'from': start.toIso8601String(),
      'to': end.toIso8601String(),
    });
    return asItemMaps(data)
        .map((m) => (
              id: asIntN(m['id']),
              name: '${m['name'] ?? ''}',
              icon: m['icon']?.toString(),
              parentId: asIntN(m['parent_id']),
              level: asInt(m['level'], 1),
              total: asDouble(m['total']),
            ))
        .toList();
  }

  @override
  Future<List<({DateTime day, double total})>> totalsByDay({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final data = await _statsGet('/stats/by_day', {
      'ledger_id': '$ledgerId',
      'type': type,
      'from': start.toIso8601String(),
      'to': end.toIso8601String(),
    });
    return asItemMaps(data)
        .map((m) => (
              day: asDate(m['day']),
              total: asDouble(m['total']),
            ))
        .toList();
  }

  @override
  Future<List<({DateTime month, double total})>> totalsByMonth({
    required int ledgerId,
    required String type,
    required int year,
  }) async {
    final data = await _statsGet('/stats/by_month', {
      'ledger_id': '$ledgerId',
      'type': type,
      'year': '$year',
    });
    return asItemMaps(data)
        .map((m) => (
              month: DateTime(year, asInt(m['month'], 1), 1),
              total: asDouble(m['total']),
            ))
        .toList();
  }

  @override
  Future<List<({int year, double total})>> totalsByYearSeries({
    required int ledgerId,
    required String type,
  }) async {
    final data = await _statsGet('/stats/by_year', {
      'ledger_id': '$ledgerId',
      'type': type,
    });
    return asItemMaps(data)
        .map((m) => (year: asInt(m['year']), total: asDouble(m['total'])))
        .toList();
  }

  @override
  Future<Map<String, (double, double)>> getDailyTotalsByMonth({
    required int ledgerId,
    required DateTime month,
  }) async {
    final data = await _statsGet('/stats/daily_totals', {
      'ledger_id': '$ledgerId',
      'year': '${month.year}',
      'month': '${month.month}',
    });
    final items = data['items'];
    final out = <String, (double, double)>{};
    if (items is Map) {
      items.forEach((k, v) {
        final m = Map<String, dynamic>.from(v as Map);
        out['$k'] = (asDouble(m['income']), asDouble(m['expense']));
      });
    }
    return out;
  }

  @override
  Future<List<String>> getTransactionDatesByMonth({
    required int ledgerId,
    required DateTime month,
  }) async {
    final map = await getDailyTotalsByMonth(ledgerId: ledgerId, month: month);
    final keys = map.keys.toList()..sort();
    return keys;
  }

  @override
  Future<List<Category>> getAllCategories() => _cats();

  @override
  Future<List<Category>> refreshAllCategories() => _cats(force: true);

  @override
  Future<List<Category>> getTopLevelCategories(String kind) async {
    return CategoryHierarchy.getTopLevelOnly(await _cats())
        .where((c) => c.kind == kind)
        .toList();
  }

  @override
  Future<List<Category>> getSubCategories(int parentId) async {
    return CategoryHierarchy.getSubCategoriesOf(await _cats(), parentId);
  }

  @override
  Future<List<Category>> getUsableCategories(String kind) async {
    return CategoryHierarchy.getUsableCategoriesByKind(await _cats(), kind);
  }

  @override
  Future<bool> hasSubCategories(int categoryId) async {
    return (await getSubCategories(categoryId)).isNotEmpty;
  }

  @override
  Future<int> getSubCategoryCount(int categoryId) async {
    return (await getSubCategories(categoryId)).length;
  }

  @override
  Future<bool> isCategoryNameDuplicate({
    required String name,
    int? excludeId,
    int? parentId,
  }) async {
    final all = await _cats();
    bool same(Category c) => c.name == name && (excludeId == null || c.id != excludeId);
    if (all.any((c) => same(c) && c.level == 1)) return true;
    if (parentId == null) {
      return all.any((c) => same(c) && c.level == 2);
    }
    return all.any((c) => same(c) && c.parentId == parentId && c.level == 2);
  }

  @override
  Future<int> upsertCategory({required String name, required String kind}) async {
    final all = await _cats();
    for (final c in all) {
      if (c.name == name && c.kind == kind) return c.id;
    }
    return createCategory(name: name, kind: kind);
  }

  @override
  Future<Category> getTransferCategory() async {
    final all = await _cats();
    for (final c in all) {
      if (c.kind == 'transfer') return c;
    }
    final id = await createCategory(
      name: '转账',
      kind: 'transfer',
      icon: 'swap_horiz',
      sortOrder: -1,
    );
    return (await getCategoryById(id))!;
  }

  @override
  Future<Map<int, int>> getAllCategoryTransactionCounts() async {
    final cats = await _cats();
    final out = <int, int>{};
    for (final c in cats) {
      final page = await fetchTransactionsPage(
        page: 1,
        pageSize: 1,
        categoryId: c.id,
      );
      out[c.id] = page.total;
    }
    return out;
  }

  @override
  Stream<List<({Category category, int transactionCount})>>
      watchCategoriesWithCount() => _watch(() async {
            final cats = await _cats();
            final counts = await getAllCategoryTransactionCounts();
            return cats
                .map((c) =>
                    (category: c, transactionCount: counts[c.id] ?? 0))
                .toList();
          });

  @override
  Future<Category?> getCategoryById(int categoryId) async {
    final all = await _cats();
    for (final c in all) {
      if (c.id == categoryId) return c;
    }
    return null;
  }

  @override
  Future<int> createCategory(
      {required String name,
      required String kind,
      String? icon,
      int? sortOrder}) async {
    final row = await api.post('/categories', {
      'name': name,
      'kind': kind,
      'icon': icon,
      'sort_order': sortOrder ?? 0,
    });
    _invalidateCategoryCache();
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<int> createSubCategory({
    required int parentId,
    required String name,
    required String kind,
    String? icon,
    int? sortOrder,
  }) async {
    final row = await api.post('/categories', {
      'name': name,
      'kind': kind,
      'icon': icon,
      'sort_order': sortOrder ?? 0,
      'parent_id': parentId,
      'level': 2,
    });
    _invalidateCategoryCache();
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<void> updateCategory(int id,
      {String? name, String? icon, int? parentId, int? level}) async {
    await api.put('/categories/$id', {
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (parentId != null) 'parent_id': parentId,
      if (level != null) 'level': level,
    });
    _invalidateCategoryCache();
    notifyChanged();
  }

  @override
  Future<void> deleteCategory(int id) async {
    await api.delete('/categories/$id');
    _invalidateCategoryCache();
    notifyChanged();
  }

  @override
  Future<void> deleteCategoriesByIds(List<int> ids) async {
    for (final id in ids) {
      await api.delete('/categories/$id');
    }
    _invalidateCategoryCache();
    notifyChanged();
  }

  @override
  Future<List<Transaction>> getTransactionsByCategory(int categoryId) async {
    final page = await fetchTransactionsPage(
      page: 1,
      pageSize: PageSizes.exportMax,
      categoryId: categoryId,
    );
    return page.items.map((e) => e.t).toList();
  }

  @override
  Future<List<Account>> getAccountsByIds(List<int> accountIds) async {
    if (accountIds.isEmpty) return [];
    final want = accountIds.toSet();
    return (await getAllAccounts()).where((a) => want.contains(a.id)).toList();
  }

  @override
  Future<Map<int, List<Tag>>> getTagsForTransactions(
      List<int> transactionIds) async {
    if (transactionIds.isEmpty) return {};
    final tags = await getAllTags();
    final byId = {for (final t in tags) t.id: t};
    final out = <int, List<Tag>>{};
    for (final id in transactionIds) {
      try {
        final row = await api.get('/transactions/$id');
        final raw = row['tag_ids'];
        final ids = raw is List ? raw.map(asInt).toList() : <int>[];
        out[id] = [
          for (final tid in ids)
            if (byId[tid] != null) byId[tid]!
        ];
      } catch (_) {
        out[id] = [];
      }
    }
    return out;
  }

  @override
  Future<Map<int, int>> getAttachmentCountsForTransactions(
      List<int> transactionIds) async {
    if (transactionIds.isEmpty) return {};
    final rows = await api.listAll('/attachments');
    final counts = <int, int>{};
    for (final m in rows) {
      final tid = asInt(m['transaction_id']);
      counts[tid] = (counts[tid] ?? 0) + 1;
    }
    return {for (final id in transactionIds) id: counts[id] ?? 0};
  }

  Future<List<
      ({
        Transaction t,
        Category? category,
        List<Tag> tags,
        List<TransactionAttachment> attachments,
        Account? account,
      })>> _detailsForPage(
    List<({Transaction t, Category? category})> items,
  ) async {
    final ids = items.map((e) => e.t.id).toList();
    final tagsMap = await getTagsForTransactions(ids);
    final accounts = await getAllAccounts();
    final accountById = {for (final a in accounts) a.id: a};
    final out = <({
      Transaction t,
      Category? category,
      List<Tag> tags,
      List<TransactionAttachment> attachments,
      Account? account,
    })>[];
    for (final item in items) {
      final attachments = await getAttachmentsByTransaction(item.t.id);
      out.add((
        t: item.t,
        category: item.category,
        tags: tagsMap[item.t.id] ?? const <Tag>[],
        attachments: attachments,
        account: item.t.accountId == null
            ? null
            : accountById[item.t.accountId!],
      ));
    }
    return out;
  }

  @override
  Future<List<
      ({
        Transaction t,
        Category? category,
        List<Tag> tags,
        List<TransactionAttachment> attachments,
        Account? account,
      })>> getTransactionsByDate({
    required int ledgerId,
    required DateTime date,
  }) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final page = await fetchTransactionsPage(
      ledgerId: ledgerId,
      page: 1,
      pageSize: PageSizes.calendarDay,
      from: start,
      to: end,
    );
    return _detailsForPage(page.items);
  }

  @override
  Future<List<
      ({
        Transaction t,
        Category? category,
        List<Tag> tags,
        List<TransactionAttachment> attachments,
        Account? account,
      })>> getTransactionsByDateRange({
    required int ledgerId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final page = await fetchTransactionsPage(
      ledgerId: ledgerId,
      page: 1,
      pageSize: PageSizes.exportMax,
      from: startDate,
      to: endDate,
    );
    return _detailsForPage(page.items);
  }

  @override
  Stream<List<Account>> watchAllAccounts() => _watch(getAllAccounts);

  @override
  Stream<List<Account>> watchAccountsForLedger(int ledgerId) => _watch(() async {
        final all = await getAllAccounts();
        return all.where((a) => a.ledgerId == ledgerId).toList();
      });

  @override
  Future<List<Account>> getAllAccounts() => _accounts();

  @override
  Future<List<Account>> refreshAllAccounts() => _accounts(force: true);

  @override
  Future<Account?> getAccount(int accountId) async {
    final all = await getAllAccounts();
    for (final a in all) {
      if (a.id == accountId) return a;
    }
    return null;
  }

  @override
  Future<int> createAccount({
    required int ledgerId,
    required String name,
    String type = 'cash',
    String currency = 'CNY',
    double initialBalance = 0.0,
  }) async {
    final row = await api.post('/accounts', {
      'ledger_id': ledgerId,
      'name': name,
      'type': type,
      'currency': currency,
      'initial_balance': initialBalance,
    });
    _invalidateAccountCache();
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<void> updateAccount(
    int id, {
    String? name,
    String? type,
    String? currency,
    double? initialBalance,
  }) async {
    await api.put('/accounts/$id', {
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (currency != null) 'currency': currency,
      if (initialBalance != null) 'initial_balance': initialBalance,
    });
    _invalidateAccountCache();
    notifyChanged();
  }

  @override
  Future<void> deleteAccount(int id) async {
    await api.delete('/accounts/$id');
    _invalidateAccountCache();
    notifyChanged();
  }

  @override
  Future<double> getAccountBalance(int accountId) async {
    final data = await api.get('/accounts/$accountId/balance');
    return asDouble(data['balance']);
  }

  @override
  Future<double> getAccountGlobalBalance(int accountId) =>
      getAccountBalance(accountId);

  @override
  Future<Map<int, ({double balance, double expense, double income})>>
      getAllAccountStats() async {
    final data = await api.get('/accounts/stats');
    final out = <int, ({double balance, double expense, double income})>{};
    for (final m in asItemMaps(data)) {
      out[asInt(m['id'])] = (
        balance: asDouble(m['balance']),
        expense: asDouble(m['expense']),
        income: asDouble(m['income']),
      );
    }
    return out;
  }

  @override
  Future<({double totalBalance, double totalExpense, double totalIncome})>
      getAllAccountsTotalStats() async {
    final data = await api.get('/accounts/stats');
    if (data.containsKey('total_balance')) {
      return (
        totalBalance: asDouble(data['total_balance']),
        totalExpense: asDouble(data['total_expense']),
        totalIncome: asDouble(data['total_income']),
      );
    }
    final typeById = {
      for (final a in await getAllAccounts()) a.id: a.type,
    };
    var totalBalance = 0.0;
    var totalExpense = 0.0;
    var totalIncome = 0.0;
    for (final m in asItemMaps(data)) {
      final type = typeById[asInt(m['id'])];
      totalIncome += asDouble(m['income']);
      totalExpense += asDouble(m['expense']);
      if (type != 'receivable' && type != 'payable') {
        totalBalance += asDouble(m['balance']);
      }
    }
    return (
      totalBalance: totalBalance,
      totalExpense: totalExpense,
      totalIncome: totalIncome,
    );
  }

  @override
  Future<List<Tag>> getAllTags() async {
    final rows = await api.listAll('/tags');
    return rows.map(tagFromJson).toList();
  }

  @override
  Stream<List<Tag>> watchAllTags() => _watch(getAllTags);

  @override
  Future<int> createTag(
      {required String name, String? color, int sortOrder = 0}) async {
    final row = await api.post(
        '/tags', {'name': name, 'color': color, 'sort_order': sortOrder});
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<void> deleteTag(int id) async {
    await api.delete('/tags/$id');
    notifyChanged();
  }

  @override
  Future<List<RecurringTransaction>> getAllRecurringTransactions() async {
    final rows = await api.listAll('/recurring_transactions');
    return rows.map(recurringFromJson).toList();
  }

  @override
  Stream<List<RecurringTransaction>> watchAllRecurringTransactions() =>
      _watch(getAllRecurringTransactions);

  @override
  Future<List<Budget>> getAllBudgets(int ledgerId) async {
    final rows = await api.listAll('/budgets');
    return rows.map(budgetFromJson).where((b) => b.ledgerId == ledgerId).toList();
  }

  @override
  Stream<List<Budget>> watchBudgets(int ledgerId) =>
      _watch(() => getAllBudgets(ledgerId));

  @override
  Future<List<TransactionAttachment>> getAttachmentsByTransaction(
      int transactionId) async {
    final rows =
        await api.listAll('/attachments', {'transaction_id': '$transactionId'});
    return rows.map(attachmentFromJson).toList();
  }

  @override
  Future<int> createAttachment({
    required int transactionId,
    required String fileName,
    String? originalName,
    int? fileSize,
    int? width,
    int? height,
    int sortOrder = 0,
  }) async {
    final bytes = await File(fileName).readAsBytes();
    final row = await api.post('/attachments', {
      'transaction_id': transactionId,
      'file_base64': base64Encode(bytes),
      'original_name': originalName ?? fileName,
      'file_size': fileSize ?? bytes.length,
      'width': width,
      'height': height,
      'sort_order': sortOrder,
    });
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<void> deleteAttachment(int id) async {
    await api.delete('/attachments/$id');
    notifyChanged();
  }

  @override
  Future<void> clearAllData() async {
    await super.clearAllData();
    notifyChanged();
  }

  Future<List<Receivable>> _receivables({int? accountId}) async {
    final rows = await _allPages('/receivables', {
      if (accountId != null) 'account_id': '$accountId',
    });
    final list = rows.map(receivableFromJson).toList();
    if (accountId == null) return list;
    return list.where((r) => r.accountId == accountId).toList();
  }

  Future<List<Payable>> _payables({int? accountId}) async {
    final rows = await _allPages('/payables', {
      if (accountId != null) 'account_id': '$accountId',
    });
    final list = rows.map(payableFromJson).toList();
    if (accountId == null) return list;
    return list.where((p) => p.accountId == accountId).toList();
  }

  Future<List<ReceivablePayment>> _recvPayments({int? receivableId}) async {
    final rows = await _allPages('/receivable_payments', {
      if (receivableId != null) 'receivable_id': '$receivableId',
    });
    return rows.map(receivablePaymentFromJson).toList();
  }

  Future<List<PayablePayment>> _payPayments({int? payableId}) async {
    final rows = await _allPages('/payable_payments', {
      if (payableId != null) 'payable_id': '$payableId',
    });
    return rows.map(payablePaymentFromJson).toList();
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
  }) async {
    final row = await api.post('/receivables', {
      'account_id': accountId,
      'borrower_name': borrowerName,
      'amount': amount,
      'borrow_date': borrowDate.toIso8601String(),
      'note': note,
      'from_account_id': fromAccountId,
      'is_received': isReceived,
      'receive_date': receiveDate?.toIso8601String(),
      'to_account_id': toAccountId,
    });
    notifyChanged();
    return asInt(row['id']);
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
  }) async {
    await api.put('/receivables/$id', {
      if (borrowerName != null) 'borrower_name': borrowerName,
      if (amount != null) 'amount': amount,
      if (borrowDate != null) 'borrow_date': borrowDate.toIso8601String(),
      if (note != null) 'note': note,
      if (applyFromAccountId) 'from_account_id': fromAccountId,
      if (isReceived != null) 'is_received': isReceived,
      if (receiveDate != null) 'receive_date': receiveDate.toIso8601String(),
      if (toAccountId != null) 'to_account_id': toAccountId,
    });
    notifyChanged();
  }

  @override
  Future<void> deleteReceivable(int id) async {
    await api.delete('/receivables/$id');
    notifyChanged();
  }

  @override
  Future<List<Receivable>> getReceivablesByAccountId(int accountId) =>
      _receivables(accountId: accountId);

  @override
  Stream<List<Receivable>> watchReceivablesByAccountId(int accountId) =>
      _watch(() => getReceivablesByAccountId(accountId));

  @override
  Future<Receivable?> getReceivableById(int id) async {
    for (final r in await _receivables()) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<Map<int, double>> getReceivableOutstandingMapForAccount(
      int accountId) async {
    final recs = await _receivables(accountId: accountId);
    final pays = await _recvPayments();
    final paidBy = <int, double>{};
    for (final p in pays) {
      paidBy[p.receivableId] = (paidBy[p.receivableId] ?? 0) + p.amount;
    }
    return {
      for (final r in recs)
        r.id: () {
          final remaining = r.amount - (paidBy[r.id] ?? 0);
          return remaining > 0 ? remaining : 0.0;
        }(),
    };
  }

  @override
  Stream<Map<int, double>> watchReceivableOutstandingMapForAccount(
          int accountId) =>
      _watch(() => getReceivableOutstandingMapForAccount(accountId));

  @override
  Future<double> getReceivableBalance(int accountId) async {
    final map = await getReceivableOutstandingMapForAccount(accountId);
    final recs = await _receivables(accountId: accountId);
    var sum = 0.0;
    for (final r in recs) {
      if (!r.isReceived) sum += map[r.id] ?? 0;
    }
    return sum;
  }

  @override
  Future<({double pending, double total, double received})> getReceivableStats(
      int accountId) async {
    final recs = await _receivables(accountId: accountId);
    final map = await getReceivableOutstandingMapForAccount(accountId);
    var pending = 0.0;
    var total = 0.0;
    var received = 0.0;
    for (final r in recs) {
      total += r.amount;
      final remain = map[r.id] ?? 0;
      received += r.amount - remain;
      if (!r.isReceived) pending += remain;
    }
    return (pending: pending, total: total, received: received);
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
  }) async {
    final row = await api.post('/payables', {
      'account_id': accountId,
      'payee_name': payeeName,
      'amount': amount,
      'pay_date': payDate.toIso8601String(),
      'note': note,
      'to_account_id': toAccountId,
      'is_paid': isPaid,
      'paid_date': paidDate?.toIso8601String(),
      'from_account_id': fromAccountId,
    });
    notifyChanged();
    return asInt(row['id']);
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
  }) async {
    await api.put('/payables/$id', {
      if (payeeName != null) 'payee_name': payeeName,
      if (amount != null) 'amount': amount,
      if (payDate != null) 'pay_date': payDate.toIso8601String(),
      if (note != null) 'note': note,
      if (applyToAccountId) 'to_account_id': toAccountId,
      if (isPaid != null) 'is_paid': isPaid,
      if (paidDate != null) 'paid_date': paidDate.toIso8601String(),
      if (fromAccountId != null) 'from_account_id': fromAccountId,
    });
    notifyChanged();
  }

  @override
  Future<void> deletePayable(int id) async {
    await api.delete('/payables/$id');
    notifyChanged();
  }

  @override
  Future<List<Payable>> getPayablesByAccountId(int accountId) =>
      _payables(accountId: accountId);

  @override
  Stream<List<Payable>> watchPayablesByAccountId(int accountId) =>
      _watch(() => getPayablesByAccountId(accountId));

  @override
  Future<Payable?> getPayableById(int id) async {
    for (final p in await _payables()) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<Map<int, double>> getPayableOutstandingMapForAccount(
      int accountId) async {
    final pays = await _payables(accountId: accountId);
    final parts = await _payPayments();
    final paidBy = <int, double>{};
    for (final p in parts) {
      paidBy[p.payableId] = (paidBy[p.payableId] ?? 0) + p.amount;
    }
    return {
      for (final p in pays)
        p.id: () {
          final remaining = p.amount - (paidBy[p.id] ?? 0);
          return remaining > 0 ? remaining : 0.0;
        }(),
    };
  }

  @override
  Stream<Map<int, double>> watchPayableOutstandingMapForAccount(
          int accountId) =>
      _watch(() => getPayableOutstandingMapForAccount(accountId));

  @override
  Future<double> getPayableBalance(int accountId) async {
    final map = await getPayableOutstandingMapForAccount(accountId);
    final pays = await _payables(accountId: accountId);
    var sum = 0.0;
    for (final p in pays) {
      if (!p.isPaid) sum += map[p.id] ?? 0;
    }
    return sum;
  }

  @override
  Future<({double pending, double total, double paid})> getPayableStats(
      int accountId) async {
    final pays = await _payables(accountId: accountId);
    final map = await getPayableOutstandingMapForAccount(accountId);
    var pending = 0.0;
    var total = 0.0;
    var paid = 0.0;
    for (final p in pays) {
      total += p.amount;
      final remain = map[p.id] ?? 0;
      paid += p.amount - remain;
      if (!p.isPaid) pending += remain;
    }
    return (pending: pending, total: total, paid: paid);
  }

  @override
  Future<int> addReceivablePayment({
    required int receivableId,
    required double amount,
    double interestAmount = 0.0,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  }) async {
    final row = await api.post('/receivable_payments', {
      'receivable_id': receivableId,
      'amount': amount,
      'interest_amount': interestAmount,
      'happened_at': happenedAt.toIso8601String(),
      'account_id': accountId,
      'note': note,
    });
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<void> deleteReceivablePayment(int id) async {
    await api.delete('/receivable_payments/$id');
    notifyChanged();
  }

  @override
  Future<List<ReceivablePayment>> getReceivablePayments(int receivableId) =>
      _recvPayments(receivableId: receivableId);

  @override
  Stream<List<ReceivablePayment>> watchReceivablePayments(int receivableId) =>
      _watch(() => getReceivablePayments(receivableId));

  @override
  Future<int> addPayablePayment({
    required int payableId,
    required double amount,
    double interestAmount = 0.0,
    required DateTime happenedAt,
    int? accountId,
    String? note,
  }) async {
    final row = await api.post('/payable_payments', {
      'payable_id': payableId,
      'amount': amount,
      'interest_amount': interestAmount,
      'happened_at': happenedAt.toIso8601String(),
      'account_id': accountId,
      'note': note,
    });
    notifyChanged();
    return asInt(row['id']);
  }

  @override
  Future<void> deletePayablePayment(int id) async {
    await api.delete('/payable_payments/$id');
    notifyChanged();
  }

  @override
  Future<List<PayablePayment>> getPayablePayments(int payableId) =>
      _payPayments(payableId: payableId);

  @override
  Stream<List<PayablePayment>> watchPayablePayments(int payableId) =>
      _watch(() => getPayablePayments(payableId));
}
