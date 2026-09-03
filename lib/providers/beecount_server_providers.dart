import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api/beecount_api_client.dart';
import '../services/api/beecount_api_exception.dart';
import '../services/database/database_file_utils.dart';
import '../services/database/database_scopes.dart';
import '../services/sync/beecount_session_store.dart';
import '../services/system/logger_service.dart';
import '../utils/local_storage_utils.dart';
import 'database_scope_provider.dart';
import 'ui_state_providers.dart';

final beeCountSessionStoreProvider = Provider<BeeCountSessionStore>((ref) {
  return BeeCountSessionStore();
});

final beecountSessionProvider = FutureProvider<BeeCountSession?>((ref) async {
  final store = ref.watch(beeCountSessionStoreProvider);
  return store.loadSession();
});

final beecountApiClientProvider = Provider<BeeCountApiClient?>((ref) {
  final sessionAsync = ref.watch(beecountSessionProvider);
  final session = sessionAsync.asData?.value;
  if (session == null) return null;
  return BeeCountApiClient(
    serverUrl: session.serverUrl,
    token: session.token,
    onAuthFailed: () {
      ref
          .read(beecountServerConnectionControllerProvider)
          .markAuthFailed('认证失败，请重新登录');
    },
    onNetworkError: () {
      ref
          .read(beecountServerConnectionControllerProvider)
          .markDisconnected('服务器连接失败');
    },
  );
});

class BeeCountServerConnectionState {
  const BeeCountServerConnectionState({
    this.disconnected = false,
    this.authFailed = false,
    this.checking = false,
    this.message,
  });

  final bool disconnected;
  final bool authFailed;
  final bool checking;
  final String? message;

  BeeCountServerConnectionState copyWith({
    bool? disconnected,
    bool? authFailed,
    bool? checking,
    String? message,
  }) {
    return BeeCountServerConnectionState(
      disconnected: disconnected ?? this.disconnected,
      authFailed: authFailed ?? this.authFailed,
      checking: checking ?? this.checking,
      message: message ?? this.message,
    );
  }
}

final beecountServerConnectionProvider =
    StateProvider<BeeCountServerConnectionState>(
  (ref) => const BeeCountServerConnectionState(),
);

class BeeCountServerConnectionController {
  BeeCountServerConnectionController(this._ref);
  final Ref _ref;

  void markDisconnected([String? message]) {
    _ref.read(beecountServerConnectionProvider.notifier).state =
        BeeCountServerConnectionState(
      disconnected: true,
      authFailed: false,
      checking: false,
      message: message ?? '服务器连接失败',
    );
  }

  void markAuthFailed([String? message]) {
    _ref.read(beecountServerConnectionProvider.notifier).state =
        BeeCountServerConnectionState(
      disconnected: true,
      authFailed: true,
      checking: false,
      message: message ?? '认证失败，请重新登录',
    );
  }

  void markConnected() {
    _ref.read(beecountServerConnectionProvider.notifier).state =
        const BeeCountServerConnectionState();
  }

  Future<void> reconnect() async {
    final current = _ref.read(beecountServerConnectionProvider);
    _ref.read(beecountServerConnectionProvider.notifier).state =
        current.copyWith(checking: true);
    try {
      final api = _ref.read(beecountApiClientProvider);
      if (api == null) {
        markAuthFailed();
        return;
      }
      await api.getSyncVersion();
      markConnected();
    } on BeeCountApiException catch (e) {
      if (e.isAuth) {
        markAuthFailed();
      } else {
        markDisconnected();
      }
    } catch (_) {
      markDisconnected();
    }
  }
}

final beecountServerConnectionControllerProvider =
    Provider<BeeCountServerConnectionController>((ref) {
  return BeeCountServerConnectionController(ref);
});

final beecountDataSyncingCountProvider = StateProvider<int>((ref) => 0);

final beecountDataSyncingProvider = Provider<bool>((ref) {
  return ref.watch(beecountDataSyncingCountProvider) > 0;
});

class BeeCountDataSyncOverlayController {
  BeeCountDataSyncOverlayController(this._ref);
  final Ref _ref;

  Future<T> track<T>(Future<T> Function() action) async {
    _ref.read(beecountDataSyncingCountProvider.notifier).state++;
    try {
      return await action();
    } finally {
      final notifier = _ref.read(beecountDataSyncingCountProvider.notifier);
      final next = notifier.state - 1;
      notifier.state = next < 0 ? 0 : next;
    }
  }
}

final beecountDataSyncOverlayControllerProvider =
    Provider<BeeCountDataSyncOverlayController>((ref) {
  return BeeCountDataSyncOverlayController(ref);
});

class BeeCountAuthController {
  BeeCountAuthController(this._ref);
  final Ref _ref;

  Future<void> _applySession(BeeCountSession session) async {
    final store = _ref.read(beeCountSessionStoreProvider);
    await store.setOfflineMode(false);
    await store.saveSession(session);
    await DatabaseFileUtils.deleteBusinessDatabases();
    _ref.read(beecountServerConnectionControllerProvider).markConnected();
    _ref.read(databaseScopeKeyProvider.notifier).state =
        DatabaseScopes.forUserId(session.userId);
    _ref.invalidate(beecountSessionProvider);
    try {
      final api = BeeCountApiClient(
        serverUrl: session.serverUrl,
        token: session.token,
      );
      await api.generateRecurring();
    } catch (e, st) {
      logger.warning('BeeCountAuth', '周期记账生成失败: $e');
    }
  }

  Future<void> signIn({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final result = await BeeCountApiClient.loginAt(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
    await _applySession(BeeCountSession(
      serverUrl: serverUrl,
      token: result.token,
      userId: result.userId,
      username: result.username,
    ));
  }

  Future<void> signUp({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final result = await BeeCountApiClient.registerAt(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
    await _applySession(BeeCountSession(
      serverUrl: serverUrl,
      token: result.token,
      userId: result.userId,
      username: result.username,
    ));
  }

  Future<void> signOut() async {
    final store = _ref.read(beeCountSessionStoreProvider);
    await store.clearSession();
    await store.setOfflineMode(false);
    await LocalStorageUtils.setAppStatus(LocalStorageUtils.appStatusNone);
    _ref.read(beecountServerConnectionControllerProvider).markConnected();
    _ref.read(databaseScopeKeyProvider.notifier).state =
        DatabaseScopes.signedOut;
    _ref.invalidate(beecountSessionProvider);
    _ref.read(shouldShowLoginProvider.notifier).state = true;
    _ref.read(appInitStateProvider.notifier).state = AppInitState.splash;
    _ref.invalidate(loginCheckProvider);
    _ref.invalidate(appInitStateProvider);
  }
}

final beecountAuthControllerProvider = Provider<BeeCountAuthController>((ref) {
  return BeeCountAuthController(ref);
});
