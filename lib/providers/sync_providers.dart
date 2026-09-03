import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cloud/sync_service.dart';
import '../models/ledger_display_item.dart';
import '../services/system/logger_service.dart';
import 'database_providers.dart';
import 'ui_state_providers.dart';
import 'statistics_providers.dart';

final syncStatusProvider =
    FutureProvider.family<SyncStatus, int>((ref, ledgerId) async {
  ref.watch(syncStatusRefreshProvider);
  const status = SyncStatus(
    diff: SyncDiff.inSync,
    localCount: 0,
    localFingerprint: '',
  );
  ref.read(lastSyncStatusProvider(ledgerId).notifier).state = status;
  return status;
});

final lastSyncStatusProvider =
    StateProvider.family<SyncStatus?, int>((ref, ledgerId) => null);

final autoSyncValueProvider = FutureProvider.autoDispose<bool>((ref) async {
  return false;
});

class AutoSyncSetter {
  AutoSyncSetter(this._ref);
  final Ref _ref;
  Future<void> set(bool v) async {}
}

final autoSyncSetterProvider = Provider<AutoSyncSetter>((ref) {
  return AutoSyncSetter(ref);
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return LocalOnlySyncService();
});

final syncStatusRefreshProvider = StateProvider<int>((ref) => 0);

final ledgerListRefreshProvider = StateProvider<int>((ref) => 0);

final uploadingLedgerIdsProvider = StateProvider<Set<int>>((ref) => {});

final localLedgersProvider =
    FutureProvider<List<LedgerDisplayItem>>((ref) async {
  ref.watch(ledgerListRefreshProvider);
  ref.watch(statsRefreshProvider);
  try {
    final accountFeatureEnabled =
        await ref.watch(accountFeatureEnabledProvider.future);
    final repo = ref.watch(repositoryProvider);
    final localLedgers = await repo.getAllLedgers();
    final result = <LedgerDisplayItem>[];
    for (final ledger in localLedgers) {
      final stats = await repo.getLedgerStats(
        ledgerId: ledger.id,
        accountFeatureEnabled: accountFeatureEnabled,
      );
      result.add(LedgerDisplayItem.fromLocal(
        id: ledger.id,
        name: ledger.name,
        currency: ledger.currency,
        createdAt: ledger.createdAt,
        transactionCount: stats.transactionCount,
        balance: stats.balance,
      ));
    }
    return result;
  } catch (e, stackTrace) {
    logger.error('LocalLedgers', '获取账本列表失败', e, stackTrace);
    return [];
  }
});

final remoteLedgersProvider =
    FutureProvider<List<LedgerDisplayItem>>((ref) async {
  return const [];
});

final allLedgersProvider = FutureProvider<List<LedgerDisplayItem>>((ref) async {
  return ref.watch(localLedgersProvider.future);
});
