import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database/database_bootstrap.dart';

/// 当前打开的本地 SQLite 文件 scope（切换登录/离线时会变）。
final databaseScopeKeyProvider = StateProvider<String>(
  (ref) => DatabaseBootstrap.initialScope,
);
