import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_scopes.dart';

/// 多 scope 数据库文件路径与复制（需在关闭相关 [BeeDatabase] 连接后调用）。
abstract class DatabaseFileUtils {
  static String _safe(String scopeKey) =>
      scopeKey.replaceAll(RegExp(r'[^a-zA-Z0-9_.@-]'), '_');

  static Future<File> fileForScope(String scopeKey) async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'beecount_scope_${_safe(scopeKey)}.sqlite'));
  }

  /// 删除账本相关 SQLite（离线库、各账号库），保留进程内非账本设置走新库。
  static Future<void> deleteBusinessDatabases() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('beecount_scope_') && name.endsWith('.sqlite')) {
        if (name.contains('signed_out')) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }
}
