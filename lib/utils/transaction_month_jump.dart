/// 明细列表按日期从新到旧排列时，定位到目标月份（或最近的更早记录）。
int? monthJumpIndex(Map<String, int> dateIndexMap, DateTime targetMonth) {
  if (dateIndexMap.isEmpty) return null;

  final monthKey =
      '${targetMonth.year}-${targetMonth.month.toString().padLeft(2, '0')}';
  for (final entry in dateIndexMap.entries) {
    if (entry.key.startsWith(monthKey)) return entry.value;
  }

  final monthStart = '$monthKey-01';
  for (final entry in dateIndexMap.entries) {
    if (entry.key.compareTo(monthStart) < 0) return entry.value;
  }

  return dateIndexMap.values.last;
}

bool datesContainMonth(Iterable<DateTime> dates, DateTime month) {
  return dates.any((d) => d.year == month.year && d.month == month.month);
}

/// [dates] 从新到旧。最旧一条已早于目标月月初，说明已经翻过该月。
bool datesPassedMonth(Iterable<DateTime> dates, DateTime month) {
  if (dates.isEmpty) return false;
  final oldest = dates.last;
  return oldest.isBefore(DateTime(month.year, month.month, 1));
}
