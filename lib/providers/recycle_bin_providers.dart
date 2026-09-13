import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/transaction_repository.dart';
import 'database_providers.dart';
import 'statistics_providers.dart';

class RecycleBinSeenStore {
  static String _key(int ledgerId) => 'recycle_bin_seen_at_$ledgerId';

  static Future<DateTime?> read(int ledgerId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key(ledgerId));
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> markNow(int ledgerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(ledgerId), DateTime.now().millisecondsSinceEpoch);
  }
}

final recycleBinSummaryProvider =
    FutureProvider.autoDispose<RecycleBinSummary>((ref) async {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  ref.watch(statsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.getDeletedTransactionsSummary(ledgerId: ledgerId);
});

final recycleBinHasNewProvider = FutureProvider.autoDispose<bool>((ref) async {
  final summary = await ref.watch(recycleBinSummaryProvider.future);
  if (summary.count <= 0 || summary.latestDeletedAt == null) return false;
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final seen = await RecycleBinSeenStore.read(ledgerId);
  if (seen == null) return true;
  return summary.latestDeletedAt!.isAfter(seen);
});
