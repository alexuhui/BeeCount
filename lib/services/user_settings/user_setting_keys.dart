/// 存入 [UserSettings] 表的键名（与旧 SharedPreferences 键一致，便于迁移）。
abstract class UserSettingKeys {
  static const themeMode = 'themeMode';
  static const darkModePatternStyle = 'darkModePatternStyle';
  static const primaryColor = 'primaryColor';
  static const hideAmounts = 'hideAmounts';
  static const compactAmount = 'compactAmount';
  static const showTransactionTime = 'showTransactionTime';
  static const headerDecorationStyle = 'headerDecorationStyle';
  static const incomeExpenseColorScheme = 'incomeExpenseColorScheme';
  static const selectedLanguage = 'selected_language';
  static const selectedLanguageCountry = 'selected_language_country';
  static const fontScaleLevel = 'fontScaleLevel';
  static const customFontScale = 'customFontScale';
  static const currentLedgerId = 'current_ledger_id';
  static const welcomeShown = 'welcome_shown';
  static const selectedCurrency = 'selected_currency';
  static const categoryMode = 'category_mode';
  static const syncVersion = 'sync_version';
  static const reminderEnabled = 'reminder_enabled';
  static const reminderHour = 'reminder_hour';
  static const reminderMinute = 'reminder_minute';

  /// 从旧版 SharedPreferences 一次性导入时扫描的键（含类型混合，按 prefs 实际类型读取）。
  static const List<String> migrationKeys = [
    themeMode,
    darkModePatternStyle,
    primaryColor,
    hideAmounts,
    compactAmount,
    showTransactionTime,
    headerDecorationStyle,
    incomeExpenseColorScheme,
    selectedLanguage,
    selectedLanguageCountry,
    fontScaleLevel,
    customFontScale,
    currentLedgerId,
    welcomeShown,
    selectedCurrency,
    categoryMode,
    syncVersion,
    reminderEnabled,
    reminderHour,
    reminderMinute,
  ];
}
