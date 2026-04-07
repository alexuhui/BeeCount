import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../widget/widget_manager.dart';
import '../services/user_settings/user_setting_keys.dart';
import '../services/user_settings/user_settings_store.dart';
import 'database_providers.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

final themeModeInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(userSettingsStoreProvider);
  final saved = await store.getString(UserSettingKeys.themeMode);
  if (saved != null) {
    switch (saved) {
      case 'light':
        ref.read(themeModeProvider.notifier).state = ThemeMode.light;
        break;
      case 'dark':
        ref.read(themeModeProvider.notifier).state = ThemeMode.dark;
        break;
      default:
        ref.read(themeModeProvider.notifier).state = ThemeMode.system;
    }
  }
  ref.listen<ThemeMode>(themeModeProvider, (prev, next) async {
    String value;
    switch (next) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      default:
        value = 'system';
    }
    await store.setString(UserSettingKeys.themeMode, value);
  });
});

final darkModePatternStyleProvider = StateProvider<String>((ref) => 'icons');

final darkModePatternStyleInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(userSettingsStoreProvider);
  final saved = await store.getString(UserSettingKeys.darkModePatternStyle);
  if (saved != null) {
    ref.read(darkModePatternStyleProvider.notifier).state = saved;
  }
  ref.listen<String>(darkModePatternStyleProvider, (prev, next) async {
    await store.setString(UserSettingKeys.darkModePatternStyle, next);
  });
});

final primaryColorProvider = StateProvider<Color>((ref) => BeeTheme.honeyGold);

final hideAmountsProvider = StateProvider<bool>((ref) => false);

final primaryColorInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(userSettingsStoreProvider);
  final saved = await store.getInt(UserSettingKeys.primaryColor);
  if (saved != null) {
    ref.read(primaryColorProvider.notifier).state = Color(saved);
  }
  ref.listen<Color>(primaryColorProvider, (prev, next) async {
    final colorValue = (next.a * 255).toInt() << 24 |
        (next.r * 255).toInt() << 16 |
        (next.g * 255).toInt() << 8 |
        (next.b * 255).toInt();
    await store.setInt(UserSettingKeys.primaryColor, colorValue);
    try {
      final repository = ref.read(repositoryProvider);
      final currentLedgerId = ref.read(currentLedgerIdProvider);
      final widgetManager = WidgetManager();
      await widgetManager.updateWidget(repository, currentLedgerId, next);
    } catch (e) {
      // Silently fail
    }
  });
});

final hideAmountsInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(userSettingsStoreProvider);
  final saved = await store.getBool(UserSettingKeys.hideAmounts);
  if (saved != null) {
    ref.read(hideAmountsProvider.notifier).state = saved;
  }
  ref.listen<bool>(hideAmountsProvider, (prev, next) async {
    await store.setBool(UserSettingKeys.hideAmounts, next);
  });
});

final headerDecorationStyleProvider = StateProvider<String>((ref) => 'icons');

final compactAmountProvider = StateProvider<bool>((ref) => false);

final compactAmountInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(userSettingsStoreProvider);
  final saved = await store.getBool(UserSettingKeys.compactAmount);
  if (saved != null) {
    ref.read(compactAmountProvider.notifier).state = saved;
  }
  ref.listen<bool>(compactAmountProvider, (prev, next) async {
    await store.setBool(UserSettingKeys.compactAmount, next);
  });
});

final showTransactionTimeProvider = StateProvider<bool>((ref) => false);

final showTransactionTimeInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(userSettingsStoreProvider);
  final saved = await store.getBool(UserSettingKeys.showTransactionTime);
  if (saved != null) {
    ref.read(showTransactionTimeProvider.notifier).state = saved;
  }
  ref.listen<bool>(showTransactionTimeProvider, (prev, next) async {
    await store.setBool(UserSettingKeys.showTransactionTime, next);
  });
});

final headerDecorationStyleInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(userSettingsStoreProvider);
  final saved = await store.getString(UserSettingKeys.headerDecorationStyle);
  if (saved != null) {
    ref.read(headerDecorationStyleProvider.notifier).state = saved;
  }
  ref.listen<String>(headerDecorationStyleProvider, (prev, next) async {
    await store.setString(UserSettingKeys.headerDecorationStyle, next);
  });
});

final incomeExpenseColorSchemeProvider = StateProvider<bool>((ref) => true);

final incomeExpenseColorSchemeInitProvider = FutureProvider<void>((ref) async {
  final store = ref.read(userSettingsStoreProvider);
  final saved = await store.getBool(UserSettingKeys.incomeExpenseColorScheme);
  if (saved != null) {
    ref.read(incomeExpenseColorSchemeProvider.notifier).state = saved;
  }
  ref.listen<bool>(incomeExpenseColorSchemeProvider, (prev, next) async {
    await store.setBool(UserSettingKeys.incomeExpenseColorScheme, next);
  });
});
