import 'dart:async';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_cloud_sync_beecount/flutter_cloud_sync_beecount.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../system/logger_service.dart';
import '../../providers/beecount_server_providers.dart';
import '../../providers/database_providers.dart';
import 'beecount_initial_sync_service.dart';
import 'beecount_sync_engine.dart';

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
      final syncEngine = _ref.read(beecountSyncEngineProvider);
      logger.debug('SyncVersion', 'syncEngine: $syncEngine');
      if (syncEngine == null) {
        logger.debug('SyncVersion', 'syncEngine 为 null，跳过检测');
        return;
      }

      final provider = syncEngine.provider;
      logger.debug('SyncVersion', 'provider: $provider, databaseService: ${provider.databaseService}');
      if (provider.databaseService == null) {
        logger.debug('SyncVersion', 'databaseService 为 null，跳过检测');
        return;
      }

      if (provider.databaseService is BeeCountDatabaseService) {
        final beecountDb = provider.databaseService as BeeCountDatabaseService;
        final serverVersion = await beecountDb.getSyncVersion();
        
        logger.info('SyncVersion', '服务器版本: $serverVersion, 本地版本: $_localVersion');

        // 只有当服务器版本号大于本地版本号时才触发同步
        // （表示服务器有新数据需要拉取）
        if (serverVersion > _localVersion) {
          logger.info('SyncVersion', '服务器有新数据，触发同步');
          await _doSync(syncEngine, provider);
          
          _localVersion = serverVersion;
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('sync_version', serverVersion);
          logger.info('SyncVersion', '本地版本已更新: $_localVersion');
        }
      } else {
        logger.debug('SyncVersion', 'databaseService 不是 BeeCountDatabaseService: ${provider.databaseService.runtimeType}');
      }
    } catch (e, st) {
      logger.warning('SyncVersion', '检测版本号失败: $e\n$st');
    }
  }

  Future<void> _doSync(BeeCountSyncEngine syncEngine, CloudProvider provider) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final db = _ref.read(databaseProvider);
      
      logger.info('SyncVersion', '开始从服务器拉取数据');
      
      final syncService = BeeCountInitialSyncService(
        db: db,
        provider: provider,
        sync: syncEngine,
      );
      await syncService.run();
      
      logger.info('SyncVersion', '同步完成，更新当前账本');

      final ledgers = await db.select(db.ledgers).get();
      if (ledgers.isNotEmpty) {
        final firstLedgerId = ledgers.first.id;
        final currentId = _ref.read(currentLedgerIdProvider);
        if (currentId != firstLedgerId) {
          _ref.read(currentLedgerIdProvider.notifier).state = firstLedgerId;
          logger.info('SyncVersion', '已设置当前账本 ID: $firstLedgerId');
        }
      }
    } catch (e, st) {
      logger.error('SyncVersion', '同步失败', e, st);
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

  /// 从服务器同步版本号（在本地推送数据后调用）
  Future<void> syncVersionFromServer() async {
    try {
      final syncEngine = _ref.read(beecountSyncEngineProvider);
      if (syncEngine == null) return;

      final provider = syncEngine.provider;
      if (provider.databaseService == null) return;

      if (provider.databaseService is BeeCountDatabaseService) {
        final beecountDb = provider.databaseService as BeeCountDatabaseService;
        final serverVersion = await beecountDb.getSyncVersion();
        _localVersion = serverVersion;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('sync_version', serverVersion);
        logger.info('SyncVersion', '从服务器同步版本号: $_localVersion');
      }
    } catch (e) {
      logger.warning('SyncVersion', '同步版本号失败: $e');
    }
  }
}

final syncVersionServiceProvider = Provider<SyncVersionService>((ref) {
  return SyncVersionService(ref);
});

final syncVersionServiceRunningProvider = StateProvider<bool>((ref) => false);
