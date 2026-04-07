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

  /// 将离线库整文件复制为当前登录用户的库（覆盖目标文件）。
  static Future<void> copyOfflineDatabaseToUser(String userId) async {
    final from = await fileForScope(DatabaseScopes.offline);
    if (!await from.exists()) return;
    final to = await fileForScope(DatabaseScopes.forUserId(userId));
    if (await to.exists()) {
      await to.delete();
    }
    await from.copy(to.path);
  }
}
