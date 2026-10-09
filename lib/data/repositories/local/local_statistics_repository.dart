import 'package:drift/drift.dart' as d;

import '../../db.dart';
import '../../../utils/refund_tx.dart';
import '../statistics_repository.dart';

/// 本地统计Repository实现
/// 基于 Drift 数据库实现
class LocalStatisticsRepository implements StatisticsRepository {
  final BeeDatabase db;

  LocalStatisticsRepository(this.db);

  Future<List<Transaction>> _ledgerRows(int ledgerId) {
    return (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) & t.excludeFromStats.equals(false)))
        .get();
  }

  Map<int, double> _linkedTotals(Iterable<Transaction> rows) {
    final totals = <int, double>{};
    for (final row in rows) {
      final originalId = row.refundOfId;
      if (originalId == null || !RefundTx.isLinkedCredit(row.type)) continue;
      totals.update(
        originalId,
        (value) => value + row.amount,
        ifAbsent: () => row.amount,
      );
    }
    return totals;
  }

  double _netExpense(Transaction expense, Map<int, double> linkedTotals) {
    final net = expense.amount - (linkedTotals[expense.id] ?? 0);
    return net > 0 ? net : 0;
  }

  bool _inRange(Transaction row, DateTime start, DateTime end) {
    return !row.happenedAt.isBefore(start) && row.happenedAt.isBefore(end);
  }

  Future<(double income, double expense)> _rangeTotals(
    int ledgerId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _ledgerRows(ledgerId);
    final linkedTotals = _linkedTotals(rows);
    var income = 0.0;
    var expense = 0.0;
    for (final row in rows) {
      if (!_inRange(row, start, end)) continue;
      if (row.type == 'income') {
        income += row.amount;
      } else if (row.type == 'expense') {
        expense += _netExpense(row, linkedTotals);
      }
    }
    return (income, expense);
  }

  @override
  Future<List<({int? id, String name, String? icon, double total})>>
      totalsByCategory({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final allRows = await _ledgerRows(ledgerId);
    final linkedTotals = _linkedTotals(allRows);
    final selected =
        allRows.where((t) => t.type == type && _inRange(t, start, end));
    final q = (db.select(db.transactions)
          ..where((t) => t.id.isIn(selected.map((row) => row.id).toList())))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    final rows = await q.get();
    final map = <int?, double>{};
    final names = <int?, String>{};
    final icons = <int?, String?>{};
    for (final r in rows) {
      final t = r.readTable(db.transactions);
      final c = r.readTableOrNull(db.categories);
      final id = c?.id;
      final name = c?.name ?? '未分类';
      final icon = c?.icon;
      names[id] = name;
      icons[id] = icon;
      final value = type == 'expense' ? _netExpense(t, linkedTotals) : t.amount;
      map.update(id, (v) => v + value, ifAbsent: () => value);
    }
    final list = map.entries
        .map((e) => (
              id: e.key,
              name: names[e.key] ?? '未分类',
              icon: icons[e.key],
              total: e.value
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list;
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
    final allRows = await _ledgerRows(ledgerId);
    final linkedTotals = _linkedTotals(allRows);
    final selected =
        allRows.where((t) => t.type == type && _inRange(t, start, end));
    final q = (db.select(db.transactions)
          ..where((t) => t.id.isIn(selected.map((row) => row.id).toList())))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);

    final rows = await q.get();
    final map = <int?, double>{};
    final categoryInfo =
        <int?, ({String name, String? icon, int? parentId, int level})>{};

    for (final r in rows) {
      final t = r.readTable(db.transactions);
      final c = r.readTableOrNull(db.categories);
      final id = c?.id;

      if (c != null) {
        categoryInfo[id] = (
          name: c.name,
          icon: c.icon,
          parentId: c.parentId,
          level: c.level,
        );
      } else {
        categoryInfo[id] = (
          name: '未分类',
          icon: null,
          parentId: null,
          level: 1,
        );
      }

      final value = type == 'expense' ? _netExpense(t, linkedTotals) : t.amount;
      map.update(id, (v) => v + value, ifAbsent: () => value);
    }

    final list = map.entries.map((e) {
      final info = categoryInfo[e.key]!;
      return (
        id: e.key,
        name: info.name,
        icon: info.icon,
        parentId: info.parentId,
        level: info.level,
        total: e.value,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return list;
  }

  @override
  Future<List<({DateTime day, double total})>> totalsByDay({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final allRows = await _ledgerRows(ledgerId);
    final linkedTotals = _linkedTotals(allRows);
    final rows =
        allRows.where((t) => t.type == type && _inRange(t, start, end));
    final map = <DateTime, double>{};
    for (final t in rows) {
      final dt = t.happenedAt.toLocal();
      final day = DateTime(dt.year, dt.month, dt.day);
      final value = type == 'expense' ? _netExpense(t, linkedTotals) : t.amount;
      map.update(day, (v) => v + value, ifAbsent: () => value);
    }
    // ensure full range continuity
    final result = <({DateTime day, double total})>[];
    for (DateTime d = DateTime(start.year, start.month, start.day);
        d.isBefore(end);
        d = d.add(const Duration(days: 1))) {
      result.add((day: d, total: map[d] ?? 0));
    }
    return result;
  }

  @override
  Future<List<({DateTime month, double total})>> totalsByMonth({
    required int ledgerId,
    required String type,
    required int year,
  }) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final allRows = await _ledgerRows(ledgerId);
    final linkedTotals = _linkedTotals(allRows);
    final rows =
        allRows.where((t) => t.type == type && _inRange(t, start, end));
    final map = <int, double>{};
    for (final t in rows) {
      final dt = t.happenedAt.toLocal();
      final value = type == 'expense' ? _netExpense(t, linkedTotals) : t.amount;
      map.update(dt.month, (v) => v + value, ifAbsent: () => value);
    }
    final result = <({DateTime month, double total})>[];
    for (int m = 1; m <= 12; m++) {
      result.add((month: DateTime(year, m, 1), total: map[m] ?? 0));
    }
    return result;
  }

  @override
  Future<List<({int year, double total})>> totalsByYearSeries({
    required int ledgerId,
    required String type,
  }) async {
    final rows = await _ledgerRows(ledgerId);
    if (rows.isEmpty) return const [];
    final linkedTotals = _linkedTotals(rows);
    final typedRows = rows.where((t) => t.type == type);
    final map = <int, double>{};
    int minYear = 9999, maxYear = 0;
    for (final t in typedRows) {
      final y = t.happenedAt.toLocal().year;
      if (y < minYear) minYear = y;
      if (y > maxYear) maxYear = y;
      final value = type == 'expense' ? _netExpense(t, linkedTotals) : t.amount;
      map.update(y, (v) => v + value, ifAbsent: () => value);
    }
    if (map.isEmpty) return const [];
    final out = <({int year, double total})>[];
    for (int y = minYear; y <= maxYear; y++) {
      out.add((year: y, total: map[y] ?? 0));
    }
    return out;
  }

  @override
  Future<(double income, double expense)> totalsInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    return _rangeTotals(ledgerId, start, end);
  }

  @override
  Future<(double income, double expense)> monthlyTotals({
    required int ledgerId,
    required DateTime month,
  }) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return _rangeTotals(ledgerId, start, end);
  }

  @override
  Future<(double income, double expense)> yearlyTotals({
    required int ledgerId,
    required int year,
  }) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    return _rangeTotals(ledgerId, start, end);
  }
}
