import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../system/logger_service.dart';
import 'database_scopes.dart';

/// 将旧版单文件 [beecount.sqlite] 复制到按用户隔离的新文件名（仅执行一次）。
class LegacyDatabaseMigrator {
  static const _legacyFileName = 'beecount.sqlite';
  static const _migratedKey = 'beecount_legacy_sqlite_v1_migrated';
  static const _pendingPrefsImportScopeKey = 'beecount_pending_prefs_import_scope';

  static Future<void> runIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_migratedKey) == true) return;

    final dir = await getApplicationDocumentsDirectory();
    final legacy = File(p.join(dir.path, _legacyFileName));
    if (!await legacy.exists()) {
      await prefs.setBool(_migratedKey, true);
      return;
    }

    final targetScope = _targetScopeForLegacyData(prefs);
    final targetPath = _scopedPath(dir.path, targetScope);
    final target = File(targetPath);

    if (await target.exists()) {
      logger.warning(
        'LegacyDb',
        '目标库已存在，跳过复制: $targetPath（将保留 legacy 文件供手动处理）',
      );
      await prefs.setBool(_migratedKey, true);
      return;
    }

    await legacy.copy(targetPath);
    await prefs.setString(_pendingPrefsImportScopeKey, targetScope);
    await prefs.setBool(_migratedKey, true);
    logger.info('LegacyDb', '已将 beecount.sqlite 复制到 $targetPath, scope=$targetScope');
  }

  static String _targetScopeForLegacyData(SharedPreferences prefs) {
    final offline = prefs.getBool('beecount_offline_mode') ?? false;
    if (offline) return DatabaseScopes.offline;
    final uid = prefs.getString('beecount_user_id');
    if (uid != null && uid.isNotEmpty) {
      return DatabaseScopes.forUserId(uid);
    }
    return DatabaseScopes.offline;
  }

  static String _scopedPath(String dir, String scopeKey) {
    final safe = scopeKey.replaceAll(RegExp(r'[^a-zA-Z0-9_.@-]'), '_');
    return p.join(dir, 'beecount_scope_$safe.sqlite');
  }

  static String? peekPendingPrefsImportScope(SharedPreferences prefs) {
    return prefs.getString(_pendingPrefsImportScopeKey);
  }

  static Future<void> clearPendingPrefsImportScope(SharedPreferences prefs) async {
    await prefs.remove(_pendingPrefsImportScopeKey);
  }
}
