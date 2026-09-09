import 'package:beecount/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/beecount_server_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/language_provider.dart';
import '../../providers/ui_state_providers.dart';
import '../../services/system/logger_service.dart';
import '../../utils/local_storage_utils.dart';
import '../../widgets/ui/ui.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isSubmitting = false;
  bool _loggedIn = false;
  bool _isRegister = false;

  /// 线上服务器（release 固定使用）
  static const _prodServer = {
    'name': '线上服务器',
    'ip': '43.139.239.34',
    'port': 6060,
    'scheme': 'http://',
  };

  /// 开发包显示完整列表；release 只保留线上，测试服地址会被 tree-shake 掉
  final serverUrls = [
    _prodServer,
    if (kDebugMode) ...[
      {
        'name': '测试服务器',
        'ip': '172.25.26.17',
        'port': 6060,
        'scheme': 'http://',
      },
      {
        'name': '测试服务器',
        'ip': '192.168.31.152',
        'port': 6060,
        'scheme': 'http://',
      },
    ],
  ];

  int _selectedServerIndex = 0;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDataSyncing = ref.watch(beecountDataSyncingProvider);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: theme.primaryColor,
          body: SafeArea(
        child: Column(
          children: [
            // 顶部语言选择
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    l10n.mineLanguageSettings,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _buildLanguageDropdown(context, theme, l10n),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    Center(
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SvgPicture.asset('assets/logo.svg',
                              fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 标题
                    Text(
                      l10n.appName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSubmitting
                          ? l10n.mineCloudServiceOffline
                          : (_loggedIn
                              ? l10n.mineSyncInSyncSimple
                              : l10n.mineSyncNotLoggedIn),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // 登录表单
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          if (kDebugMode) ...[
                            DropdownButtonFormField<int>(
                              value: _selectedServerIndex,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: l10n.cloudBeeCountServerUrlLabel,
                                labelStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9)),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              dropdownColor: Colors.black.withValues(alpha: 0.8),
                              onChanged: (!_isSubmitting)
                                  ? (value) {
                                      if (value != null) {
                                        setState(() {
                                          _selectedServerIndex = value;
                                        });
                                      }
                                    }
                                  : null,
                              items: serverUrls.asMap().entries.map((entry) {
                                int index = entry.key;
                                Map<String, dynamic> server = entry.value;
                                return DropdownMenuItem<int>(
                                  value: index,
                                  child: Text(
                                    '${server['name']}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: _usernameController,
                            enabled: !_isSubmitting,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: l10n.cloudWebdavUsernameLabel,
                              labelStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            enabled: !_isSubmitting,
                            obscureText: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: l10n.cloudWebdavPasswordLabel,
                              labelStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          // 注册时再次输入确认密码
                          if (_isRegister)
                            Column(
                              children: [
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _confirmPasswordController,
                                  enabled: !_isSubmitting,
                                  obscureText: true,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: l10n.authConfirmPassword,
                                    labelStyle: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.9)),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ),

                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => _submitAuth(context),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: theme.primaryColor,
                            ),
                            child: Text(
                                _isRegister ? l10n.authSignup : l10n.authLogin),
                          ),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () =>
                                    setState(() => _isRegister = !_isRegister),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white),
                            child: Text(
                                _isRegister ? l10n.authLogin : l10n.authSignup),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
          ),
        ),
        if (isDataSyncing)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.38),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${l10n.mineSyncTitle}...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLanguageDropdown(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    final languageNotifier = ref.read(languageProvider.notifier);
    final currentLocale = ref.watch(languageProvider);

    final availableLocales = [
      null,
      const Locale('zh'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ];

    String nameForLocale(Locale? locale) {
      if (locale == null) return l10n.languageSystemDefault;
      if (locale.languageCode == 'zh' && locale.countryCode == null) {
        return '简体中文';
      }
      if (locale.languageCode == 'zh' && locale.countryCode == 'TW') {
        return '繁體中文';
      }
      if (locale.languageCode == 'en') return 'English';
      return locale.toString();
    }

    return DropdownButton<Locale?>(
      value: currentLocale,
      onChanged: (Locale? newValue) {
        languageNotifier.setLanguage(newValue);
      },
      items: availableLocales.map((Locale? locale) {
        return DropdownMenuItem<Locale?>(
          value: locale,
          child: Text(
            nameForLocale(locale),
            style: TextStyle(color: Colors.white),
          ),
        );
      }).toList(),
      style: const TextStyle(color: Colors.white),
      dropdownColor: theme.primaryColor,
    );
  }

  Future<void> _submitAuth(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final server = kDebugMode
        ? serverUrls[_selectedServerIndex]
        : _prodServer;
    final serverUrl = '${server['scheme']}${server['ip']}:${server['port']}';
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      await AppDialog.error(context,
          title: l10n.commonError, message: '请填写服务器地址、账号与密码');
      return;
    }
    if (_isRegister) {
      final confirmPassword = _confirmPasswordController.text;
      if (confirmPassword.isEmpty || confirmPassword != password) {
        await AppDialog.error(context,
            title: l10n.commonError, message: '两次输入的密码不一致');
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final auth = ref.read(beecountAuthControllerProvider);
      if (_isRegister) {
        await auth.signUp(
            serverUrl: serverUrl, username: username, password: password);
      } else {
        await auth.signIn(
            serverUrl: serverUrl, username: username, password: password);
      }
      if (!mounted) return;
      await _saveCredentials(username, password);
      setState(() => _loggedIn = true);
      await _finishLogin(context);
    } catch (e, st) {
      logger.error('Login', '登录/注册失败', e, st);
      if (!mounted) return;
      await AppDialog.error(context,
          title: l10n.commonError, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _finishLogin(BuildContext context) async {
    try {
      LocalStorageUtils.setAppStatus(LocalStorageUtils.appStatusOnline);
      final repo = ref.read(repositoryProvider);
      final ledgers = await repo.getAllLedgers();
      if (ledgers.isNotEmpty) {
        ledgers.sort((a, b) => a.id.compareTo(b.id));
        ref.read(currentLedgerIdProvider.notifier).state = ledgers.first.id;
      }
      ref.read(shouldShowLoginProvider.notifier).state = false;
      ref.read(appInitStateProvider.notifier).state = AppInitState.ready;
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const BeeApp()),
          (route) => false,
        );
      }
    } catch (e, st) {
      logger.error('Login', '完成登录失败', e, st);
      if (!mounted) return;
      await AppDialog.error(context,
          title: AppLocalizations.of(context).commonError, message: e.toString());
    }
  }

  Future<void> _saveCredentials(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('beecount_saved_username', email);
      logger.info('auth', '账号已保存');
    } catch (e, st) {
      logger.error('auth', '保存账号失败', e, st);
    }
  }
}
