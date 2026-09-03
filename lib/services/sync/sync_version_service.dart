import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../system/logger_service.dart';
import '../user_settings/user_setting_keys.dart';
import '../user_settings/user_settings_store.dart';
import '../../providers/beecount_server_providers.dart';
import '../../providers/budget_providers.dart';
import '../../providers/calendar_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/statistics_providers.dart';
import '../../providers/sync_providers.dart';
import '../../providers/tag_providers.dart';
import '../api/beecount_api_exception.dart';

class SyncVersionService {
  final Ref _ref;
  Timer? _timer;
  int _localVersion = 0;
  bool _isSyncing = false;

  SyncVersionService(this._ref);

  Future<void> start() async {
    final store = UserSettingsStore(_ref.read(databaseProvider));
    _localVersion = await store.getInt(UserSettingKeys.syncVersion) ?? 0;
    logger.info('SyncVersion', '启动版本号检查，本地版本: $_localVersion');
    await checkVersion();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await checkVersion();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> checkVersion() async {
    await _checkVersion();
  }

  Future<void> _checkVersion() async {
    if (_isSyncing) return;
    try {
      final api = _ref.read(beecountApiClientProvider);
      if (api == null) return;
      final serverVersion = await api.getSyncVersion();
      if (serverVersion == null) {
        _ref
            .read(beecountServerConnectionControllerProvider)
            .markDisconnected('服务器连接失败，请重新连接');
        return;
      }
      _ref.read(beecountServerConnectionControllerProvider).markConnected();
      if (serverVersion > _localVersion) {
        logger.info('SyncVersion', '服务器数据已更新，刷新列表');
        _isSyncing = true;
        try {
          _ref.read(budgetRefreshProvider.notifier).state++;
          _ref.invalidate(accountsStreamProvider);
          _ref.invalidate(allAccountsStreamProvider);
          _ref.read(statsRefreshProvider.notifier).state++;
          _ref.read(tagListRefreshProvider.notifier).state++;
          _ref.read(calendarRefreshProvider.notifier).state++;
          _ref.read(ledgerListRefreshProvider.notifier).state++;
          _ref.read(syncStatusRefreshProvider.notifier).state++;
          await updateLocalVersion(serverVersion);
        } finally {
          _isSyncing = false;
        }
      }
    } on BeeCountApiException catch (e) {
      if (e.isAuth) {
        _ref
            .read(beecountServerConnectionControllerProvider)
            .markAuthFailed('认证失败，请重新登录');
      } else {
        _ref
            .read(beecountServerConnectionControllerProvider)
            .markDisconnected('服务器连接失败，请重新连接');
      }
    } catch (e) {
      logger.warning('SyncVersion', '检测版本号失败: $e');
      _ref
          .read(beecountServerConnectionControllerProvider)
          .markDisconnected('服务器连接失败，请重新连接');
    }
  }

  Future<void> updateLocalVersion(int version) async {
    _localVersion = version;
    final store = UserSettingsStore(_ref.read(databaseProvider));
    await store.setInt(UserSettingKeys.syncVersion, version);
  }

  Future<void> syncVersionFromServer() async {
    try {
      final api = _ref.read(beecountApiClientProvider);
      if (api == null) return;
      final serverVersion = await api.getSyncVersion();
      if (serverVersion != null) {
        _ref.read(beecountServerConnectionControllerProvider).markConnected();
        await updateLocalVersion(serverVersion);
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
