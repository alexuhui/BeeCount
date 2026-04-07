import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db.dart';
import '../database/legacy_database_migrator.dart';
import '../system/logger_service.dart';
import 'user_setting_keys.dart';

/// 用户级设置（存于当前 scope 的 SQLite，与账号/离线身份绑定）。
class UserSettingsStore {
  UserSettingsStore(this._db, {this.allowPrefsFallback = true});

  final BeeDatabase _db;

  /// 为 false 时不回退读 SharedPreferences（例如已退出登录的 signed_out 壳库，避免读到上一账号的全局 prefs）。
  final bool allowPrefsFallback;

  static Future<void> importIfPending(
    BeeDatabase db,
    String currentScope,
    SharedPreferences prefs,
  ) async {
    final pending = LegacyDatabaseMigrator.peekPendingPrefsImportScope(prefs);
    if (pending == null || pending != currentScope) return;
    await UserSettingsStore(db).importAllFromSharedPreferences(prefs);
    await LegacyDatabaseMigrator.clearPendingPrefsImportScope(prefs);
    logger.info('UserSettings', '已完成旧版 prefs -> UserSettings 导入 scope=$currentScope');
  }

  Future<void> importAllFromSharedPreferences(SharedPreferences prefs) async {
    for (final k in UserSettingKeys.migrationKeys) {
      if (!prefs.containsKey(k)) continue;
      final dynamic v = prefs.get(k);
      if (v == null) continue;
      if (v is int) {
        await _putRaw(k, v.toString());
      } else if (v is bool) {
        await _putRaw(k, v ? '1' : '0');
      } else if (v is double) {
        await _putRaw(k, v.toString());
      } else if (v is String) {
        await _putRaw(k, v);
      }
    }
  }

  Future<void> _putRaw(String key, String value) async {
    await _db.customStatement(
      'INSERT OR REPLACE INTO user_settings ("key", "value") VALUES (?, ?)',
      [key, value],
    );
  }

  Future<String?> getString(String key) async {
    final row = await _db.customSelect(
      'SELECT "value" FROM user_settings WHERE "key" = ? LIMIT 1',
      variables: [Variable.withString(key)],
    ).getSingleOrNull();
    final v = row?.data['value'] as String?;
    if (v != null) return v;

    if (!allowPrefsFallback) return null;

    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(key)) return null;
    final pv = prefs.get(key);
    String? s;
    if (pv is String) {
      s = pv;
    } else if (pv is int) {
      s = pv.toString();
    } else if (pv is bool) {
      s = pv ? '1' : '0';
    } else if (pv is double) {
      s = pv.toString();
    }
    if (s != null) {
      await _putRaw(key, s);
    }
    return s;
  }

  Future<void> setString(String key, String? value) async {
    if (value == null) {
      await _db.customStatement('DELETE FROM user_settings WHERE "key" = ?', [key]);
      return;
    }
    await _putRaw(key, value);
  }

  Future<int?> getInt(String key) async {
    final s = await getString(key);
    if (s == null) return null;
    return int.tryParse(s);
  }

  Future<void> setInt(String key, int? value) async {
    if (value == null) {
      await _db.customStatement('DELETE FROM user_settings WHERE "key" = ?', [key]);
      return;
    }
    await _putRaw(key, value.toString());
  }

  Future<bool?> getBool(String key) async {
    final s = await getString(key);
    if (s == null) return null;
    if (s == '1' || s == 'true') return true;
    if (s == '0' || s == 'false') return false;
    return null;
  }

  Future<void> setBool(String key, bool? value) async {
    if (value == null) {
      await _db.customStatement('DELETE FROM user_settings WHERE "key" = ?', [key]);
      return;
    }
    await _putRaw(key, value ? '1' : '0');
  }

  Future<double?> getDouble(String key) async {
    final s = await getString(key);
    if (s == null) return null;
    return double.tryParse(s);
  }

  Future<void> setDouble(String key, double? value) async {
    if (value == null) {
      await _db.customStatement('DELETE FROM user_settings WHERE "key" = ?', [key]);
      return;
    }
    await _putRaw(key, value.toString());
  }
}
