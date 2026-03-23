import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../system/logger_service.dart';
import '../../cloud/sync_service.dart';
import '../../providers/sync_providers.dart';
import '../../providers/database_providers.dart';

class SyncVersionService {
  final Ref _ref;
  Timer? _timer;
  int _localVersion = 0;
  bool _isSyncing = false;

  SyncVersionService(this._ref);

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _localVersion = prefs.getInt('sync_version') ?? 0;
    logger.info('SyncVersion', '启动版本号同步服务，本地版本: $_localVersion');

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _checkVersion();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    logger.info('SyncVersion', '停止版本号同步服务');
  }

  Future<void> _checkVersion() async {
    if (_isSyncing) {
      logger.info('SyncVersion', '正在同步中，跳过本次检测');
      return;
    }

    try {
      final syncService = _ref.read(syncServiceProvider);
      
      if (syncService is LocalOnlySyncService) {
        return;
      }

      final cloudProvider = await _ref.read(cloudProviderInstanceProvider.future);
      if (cloudProvider == null) {
        return;
      }

      final dbService = cloudProvider.databaseService;
      if (dbService == null) {
        return;
      }

      if (dbService.toString().contains('BeeCountDatabaseService')) {
        final beecountDb = dbService as dynamic;
        final serverVersion = await beecountDb.getSyncVersion() as int;
        
        logger.info('SyncVersion', '服务器版本: $serverVersion, 本地版本: $_localVersion');

        if (serverVersion != _localVersion) {
          logger.info('SyncVersion', '版本不一致，触发同步');
          await _doSync(syncService);
          _localVersion = serverVersion;
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('sync_version', serverVersion);
          logger.info('SyncVersion', '本地版本已更新: $_localVersion');
        }
      }
    } catch (e) {
      logger.warning('SyncVersion', '检测版本号失败: $e');
    }
  }

  Future<void> _doSync(SyncService syncService) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final ledgerId = _ref.read(currentLedgerIdProvider);
      final status = await syncService.getStatus(ledgerId: ledgerId);
      
      logger.info('SyncVersion', '同步状态: ${status.diff}');

      switch (status.diff) {
        case SyncDiff.cloudNewer:
          logger.info('SyncVersion', '服务器数据较新，下载到本地');
          await syncService.downloadAndRestoreToCurrentLedger(ledgerId: ledgerId);
          _ref.read(syncStatusRefreshProvider.notifier).state++;
          break;
        case SyncDiff.localNewer:
          logger.info('SyncVersion', '本地数据较新，上传到服务器');
          await syncService.uploadCurrentLedger(ledgerId: ledgerId);
          _ref.read(syncStatusRefreshProvider.notifier).state++;
          break;
        case SyncDiff.different:
          logger.info('SyncVersion', '数据不同，下载服务器数据');
          await syncService.downloadAndRestoreToCurrentLedger(ledgerId: ledgerId);
          _ref.read(syncStatusRefreshProvider.notifier).state++;
          break;
        case SyncDiff.noRemote:
          logger.info('SyncVersion', '服务器没有数据，上传本地数据');
          await syncService.uploadCurrentLedger(ledgerId: ledgerId);
          _ref.read(syncStatusRefreshProvider.notifier).state++;
          break;
        case SyncDiff.inSync:
          logger.info('SyncVersion', '数据已同步');
          break;
        default:
          break;
      }
    } catch (e) {
      logger.error('SyncVersion', '同步失败', e);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> updateLocalVersion(int version) async {
    _localVersion = version;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_version', version);
    logger.info('SyncVersion', '本地版本已更新: $_localVersion');
  }
}

final syncVersionServiceProvider = Provider<SyncVersionService>((ref) {
  return SyncVersionService(ref);
});

final syncVersionServiceRunningProvider = StateProvider<bool>((ref) => false);
