/// 本地数据库文件隔离用的 scope 标识（与 BeeCount 云端 userId 无关，仅本地文件名）。
abstract class DatabaseScopes {
  static const String offline = 'offline';
  static const String signedOut = 'signed_out';

  static String forUserId(String userId) {
    final s = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_.@-]'), '_');
    return 'user_$s';
  }
}
