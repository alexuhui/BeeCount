import 'package:shared_preferences/shared_preferences.dart';

import '../sync/beecount_session_store.dart';
import 'database_scopes.dart';
import 'legacy_database_migrator.dart';

/// 在 [runApp] 之前调用：迁移旧版单库文件并解析首次启动应使用的 scope。
class DatabaseBootstrap {
  static late String initialScope;

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    await LegacyDatabaseMigrator.runIfNeeded(prefs);
    initialScope = await _resolveScope(prefs);
  }

  static Future<String> _resolveScope(SharedPreferences prefs) async {
    final offline = prefs.getBool('beecount_offline_mode') ?? false;
    if (offline) return DatabaseScopes.offline;
    final session = await BeeCountSessionStore().loadSession();
    if (session != null) return DatabaseScopes.forUserId(session.userId);
    return DatabaseScopes.signedOut;
  }
}
