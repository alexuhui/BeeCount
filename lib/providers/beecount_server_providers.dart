import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_cloud_sync_beecount/flutter_cloud_sync_beecount.dart';

import 'database_providers.dart';
import 'database_scope_provider.dart';
import '../services/database/database_scopes.dart';
import '../services/sync/beecount_session_store.dart';
import '../services/sync/beecount_initial_sync_service.dart';
import '../services/sync/beecount_sync_engine.dart';
import '../services/sync/sync_version_service.dart';
import '../services/system/logger_service.dart';

final beeCountSessionStoreProvider = Provider<BeeCountSessionStore>((ref) {
  return BeeCountSessionStore();
});

final beecountOfflineModeProvider = FutureProvider<bool>((ref) async {
  final store = ref.watch(beeCountSessionStoreProvider);
  return store.loadOfflineMode();
});

class BeeCountServerConnectionState {
  const BeeCountServerConnectionState({
    this.disconnected = false,
    this.checking = false,
    this.message,
  });

  final bool disconnected;
  final bool checking;
  final String? message;

  BeeCountServerConnectionState copyWith({
    bool? disconnected,
    bool? checking,
    String? message,
  }) {
    return BeeCountServerConnectionState(
      disconnected: disconnected ?? this.disconnected,
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
      checking: false,
      message: message ?? '服务器连接失败',
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
      await _ref.read(syncVersionServiceProvider).checkVersion();
    } finally {
      final next = _ref.read(beecountServerConnectionProvider);
      if (next.checking) {
        _ref.read(beecountServerConnectionProvider.notifier).state =
            next.copyWith(checking: false);
      }
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

class BeeCountOfflineModeSetter {
  BeeCountOfflineModeSetter(this._ref);
  final Ref _ref;

  Future<void> set(bool v) async {
    final store = _ref.read(beeCountSessionStoreProvider);
    await store.setOfflineMode(v);
    if (v) {
      _ref.read(databaseScopeKeyProvider.notifier).state =
          DatabaseScopes.offline;
      _ref.invalidate(databaseProvider);
      resetInMemoryDataForAccountSwitch(_ref);
    }
    _ref.invalidate(beecountOfflineModeProvider);
    _ref.invalidate(beecountSessionProvider);
    _ref.invalidate(beecountProviderProvider);
    _ref.invalidate(beecountSyncEngineProvider);
    _ref.invalidate(beecountPendingSyncCountProvider);
    _ref.read(_beecountBootstrappedProvider.notifier).state = false;
  }
}

final beecountOfflineModeSetterProvider =
    Provider<BeeCountOfflineModeSetter>((ref) {
  return BeeCountOfflineModeSetter(ref);
});

final beecountSessionProvider = FutureProvider<BeeCountSession?>((ref) async {
  final store = ref.watch(beeCountSessionStoreProvider);
  final offline = await ref.watch(beecountOfflineModeProvider.future);
  if (offline) return null;
  return store.loadSession();
});

final beecountProviderProvider = FutureProvider<CloudProvider?>((ref) async {
  final offline = await ref.watch(beecountOfflineModeProvider.future);
  if (offline) return null;
  final session = await ref.watch(beecountSessionProvider.future);
  if (session == null) return null;

  final provider = BeeCountProvider();
  await provider.initialize({'serverUrl': session.serverUrl});
  final auth = provider.auth;
  if (auth is BeeCountAuthService) {
    auth.restoreSession(
      token: session.token,
      userId: session.userId,
      username: session.username,
    );
  }

  return provider;
});

final beecountSyncEngineProvider = Provider<BeeCountSyncEngine?>((ref) {
  final providerAsync = ref.watch(beecountProviderProvider);
  if (!providerAsync.hasValue || providerAsync.value == null) return null;
  final db = ref.watch(databaseProvider);

  final syncVersionService = ref.read(syncVersionServiceProvider);

  final engine = BeeCountSyncEngine(
    db: db,
    provider: providerAsync.value!,
    onFlushComplete: () async {
      await syncVersionService.syncVersionFromServer();
    },
    onConnectionLost: (error) {
      ref
          .read(beecountServerConnectionControllerProvider)
          .markDisconnected('服务器连接失败，请重新连接');
    },
    onConnectionRestored: () {
      ref.read(beecountServerConnectionControllerProvider).markConnected();
    },
  );
  engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

final _beecountBootstrappedProvider = StateProvider<bool>((ref) => false);

final beecountBootstrapProvider = Provider<void>((ref) {
  final already = ref.watch(_beecountBootstrappedProvider);
  if (already) return;

  final providerAsync = ref.watch(beecountProviderProvider);
  final syncEngine = ref.watch(beecountSyncEngineProvider);
  if (!providerAsync.hasValue || providerAsync.value == null) return;
  if (syncEngine == null) return;

  ref.read(_beecountBootstrappedProvider.notifier).state = true;

  final db = ref.watch(databaseProvider);
  Future(() async {
    final svc = BeeCountInitialSyncService(
      db: db,
      provider: providerAsync.value!,
      sync: syncEngine,
    );
    await ref.read(beecountDataSyncOverlayControllerProvider).track(svc.run);
  }).catchError((e, st) {
    logger.error('BeeCountBootstrap', '启动拉取失败', e, st);
  });
});

final beecountPendingSyncCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return Stream.periodic(const Duration(seconds: 1)).asyncMap((_) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_queue_items')
        .getSingle();
    return (row.data['c'] as int?) ?? 0;
  }).distinct();
});

class BeeCountAuthController {
  BeeCountAuthController(this._ref);
  final Ref _ref;

  Future<void> signIn({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final provider = BeeCountProvider();
    await provider.initialize({'serverUrl': serverUrl});
    final user = await provider.auth
        .signInWithEmail(email: username, password: password);
    final token = user.metadata?['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw Exception('Missing token');
    }

    final store = _ref.read(beeCountSessionStoreProvider);
    await store.setOfflineMode(false);
    await store.saveSession(
      BeeCountSession(
        serverUrl: serverUrl,
        token: token,
        userId: user.id,
        username: user.email ?? username,
      ),
    );
    _ref.read(beecountServerConnectionControllerProvider).markConnected();

    _ref.invalidate(beecountOfflineModeProvider);
    _ref.invalidate(beecountSessionProvider);
    _ref.invalidate(beecountProviderProvider);
    _ref.read(_beecountBootstrappedProvider.notifier).state = false;
  }

  Future<void> signUp({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final provider = BeeCountProvider();
    await provider.initialize({'serverUrl': serverUrl});
    final user = await provider.auth
        .signUpWithEmail(email: username, password: password);
    final token = user.metadata?['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw Exception('Missing token');
    }

    final store = _ref.read(beeCountSessionStoreProvider);
    await store.setOfflineMode(false);
    await store.saveSession(
      BeeCountSession(
        serverUrl: serverUrl,
        token: token,
        userId: user.id,
        username: user.email ?? username,
      ),
    );
    _ref.read(beecountServerConnectionControllerProvider).markConnected();

    _ref.invalidate(beecountOfflineModeProvider);
    _ref.invalidate(beecountSessionProvider);
    _ref.invalidate(beecountProviderProvider);
    _ref.read(_beecountBootstrappedProvider.notifier).state = false;
  }

  Future<void> signOut() async {
    final store = _ref.read(beeCountSessionStoreProvider);
    await store.clearSession();
    await store.setOfflineMode(false);
    _ref.read(beecountServerConnectionControllerProvider).markConnected();
    _ref.read(databaseScopeKeyProvider.notifier).state =
        DatabaseScopes.signedOut;
    _ref.invalidate(databaseProvider);
    resetInMemoryDataForAccountSwitch(_ref);
    _ref.invalidate(beecountProviderProvider);
    _ref.invalidate(beecountOfflineModeProvider);
    _ref.invalidate(beecountSyncEngineProvider);
    _ref.invalidate(beecountPendingSyncCountProvider);
    _ref.read(_beecountBootstrappedProvider.notifier).state = false;
  }

  Future<void> useOfflineMode() async {
    final store = _ref.read(beeCountSessionStoreProvider);
    await store.setOfflineMode(true);
    await store.clearSession();
    _ref.read(beecountServerConnectionControllerProvider).markConnected();
    _ref.read(databaseScopeKeyProvider.notifier).state = DatabaseScopes.offline;
    _ref.invalidate(databaseProvider);
    resetInMemoryDataForAccountSwitch(_ref);
    _ref.invalidate(beecountOfflineModeProvider);
    _ref.invalidate(beecountSessionProvider);
    _ref.invalidate(beecountProviderProvider);
    _ref.invalidate(beecountSyncEngineProvider);
    _ref.invalidate(beecountPendingSyncCountProvider);
    _ref.read(_beecountBootstrappedProvider.notifier).state = false;
  }
}

final beecountAuthControllerProvider = Provider<BeeCountAuthController>((ref) {
  return BeeCountAuthController(ref);
});
