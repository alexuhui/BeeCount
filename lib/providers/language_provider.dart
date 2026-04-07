import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../services/user_settings/user_setting_keys.dart';
import '../services/user_settings/user_settings_store.dart';
import 'database_providers.dart';

final languageProvider = StateNotifierProvider<LanguageNotifier, Locale?>((ref) {
  return LanguageNotifier(ref);
});

class LanguageNotifier extends StateNotifier<Locale?> {
  LanguageNotifier(this._ref) : super(null) {
    _loadLanguage();
  }

  final Ref _ref;

  Future<void> _loadLanguage() async {
    try {
      final store = _ref.read(userSettingsStoreProvider);
      final languageCode = await store.getString(UserSettingKeys.selectedLanguage);
      final countryCode =
          await store.getString(UserSettingKeys.selectedLanguageCountry);
      if (languageCode != null) {
        state = Locale(languageCode, countryCode);
      }
    } catch (e) {
      // 跟随系统
    }
  }

  Future<void> setLanguage(Locale? locale) async {
    try {
      final store = _ref.read(userSettingsStoreProvider);
      if (locale == null) {
        await store.setString(UserSettingKeys.selectedLanguage, null);
        await store.setString(UserSettingKeys.selectedLanguageCountry, null);
      } else {
        await store.setString(UserSettingKeys.selectedLanguage, locale.languageCode);
        if (locale.countryCode != null) {
          await store.setString(
              UserSettingKeys.selectedLanguageCountry, locale.countryCode);
        } else {
          await store.setString(UserSettingKeys.selectedLanguageCountry, null);
        }
      }
      state = locale;
    } catch (e) {
      // 忽略
    }
  }

  String getLanguageDisplayName(BuildContext context, Locale? locale) {
    final l10n = AppLocalizations.of(context);

    if (locale == null) {
      return l10n.languageSystemDefault;
    }

    switch (locale.languageCode) {
      case 'zh':
        if (locale.countryCode == 'TW') {
          return '繁體中文';
        }
        return l10n.languageChinese;
      case 'en':
        return l10n.languageEnglish;
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'de':
        return 'Deutsch';
      default:
        return locale.languageCode;
    }
  }
}
