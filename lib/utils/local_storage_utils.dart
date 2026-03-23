import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储工具类
/// 提供本地存储相关的工具方法
/// 用于处理 SharedPreferences 等本地存储
class LocalStorageUtils {
  LocalStorageUtils._();

  /// 应用状态键
  static const String appStatus = 'app_status';
  /// 没有状态
  static const String appStatusNone = 'app_status_none';
  /// 已登录状态
  static const String appStatusLogedin = 'app_status_logedin';
  /// 离线状态
  static const String appStatusOffline = 'app_status_offline';

  /// 获取当前应用状态
  static Future<String> getAppStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(appStatus) ?? appStatusNone;
  }

  /// 设置应用状态
  static Future<void> setAppStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(appStatus, status);
  }


}
 