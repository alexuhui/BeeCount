import 'package:shared_preferences/shared_preferences.dart';

class BeeCountSession {
  final String serverUrl;
  final String token;
  final String userId;
  final String username;

  const BeeCountSession({
    required this.serverUrl,
    required this.token,
    required this.userId,
    required this.username,
  });
}

class BeeCountSessionStore {
  static const _kOfflineMode = 'beecount_offline_mode';
  static const _kServerUrl = 'beecount_server_url';
  static const _kToken = 'beecount_token';
  static const _kUserId = 'beecount_user_id';
  static const _kUsername = 'beecount_username';

  Future<bool> loadOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOfflineMode) ?? false;
  }

  Future<void> setOfflineMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOfflineMode, v);
  }

  Future<BeeCountSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(_kServerUrl);
    final token = prefs.getString(_kToken);
    final userId = prefs.getString(_kUserId);
    final username = prefs.getString(_kUsername);
    if (serverUrl == null || token == null || userId == null || username == null) {
      return null;
    }
    if (serverUrl.isEmpty || token.isEmpty || userId.isEmpty || username.isEmpty) {
      return null;
    }
    return BeeCountSession(
      serverUrl: serverUrl,
      token: token,
      userId: userId,
      username: username,
    );
  }

  Future<void> saveSession(BeeCountSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrl, session.serverUrl);
    await prefs.setString(_kToken, session.token);
    await prefs.setString(_kUserId, session.userId);
    await prefs.setString(_kUsername, session.username);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kUsername);
  }
}

