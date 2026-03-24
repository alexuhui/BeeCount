import 'package:beecount/app.dart';
import 'package:beecount/providers/sync_providers.dart';
import 'package:beecount/services/sync/beecount_sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../data/db.dart';
import '../../providers/beecount_server_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/language_provider.dart';
import '../../providers/ui_state_providers.dart';
import '../../services/data/seed_service.dart';
import '../../services/system/logger_service.dart';
import '../../services/sync/beecount_initial_sync_service.dart';
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
  bool _offlineSelected = false;
  bool _loggedIn = false;
  bool _isRegister = false;

  /// 服务器列表
  final serverUrls = [
    {'name': '线上服务器', 'ip': '43.139.239.34', 'port': 6060, 'scheme': 'http://'},
    {'name': '测试服务器1', 'ip': '172.25.26.17', 'port': 6060, 'scheme': 'http://'},
    {
      'name': '测试服务器2',
      'ip': '192.168.31.152',
      'port': 6060,
      'scheme': 'http://'
    },
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

    return Scaffold(
      backgroundColor: theme.primaryColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部语言选择下拉框
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
                      _offlineSelected
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
                            onChanged: (!_isSubmitting && !_offlineSelected)
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
                                  '${server['name']} (${server['ip']})',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _usernameController,
                            enabled: !_isSubmitting && !_offlineSelected,
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
                            enabled: !_isSubmitting && !_offlineSelected,
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
                          // 如果是注册，需要再次输入确认密码
                          if (_isRegister)
                            Column(
                              children: [
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _confirmPasswordController,
                                  enabled: !_isSubmitting && !_offlineSelected,
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
                            onPressed: _isSubmitting || _offlineSelected
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
                            onPressed: _isSubmitting || _offlineSelected
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
                    OutlinedButton(
                      onPressed:
                          _isSubmitting ? null : () => _useOfflineMode(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      child: Text(l10n.mineCloudServiceOffline),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
      if (locale.languageCode == 'zh' && locale.countryCode == null)
        return '简体中文';
      if (locale.languageCode == 'zh' && locale.countryCode == 'TW')
        return '繁體中文';
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

  Future<void> _useOfflineMode(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isSubmitting = true;
    });

    try {
      await ref.read(beecountAuthControllerProvider).useOfflineMode();
      if (!mounted) return;
      setState(() {
        _offlineSelected = true;
        _loggedIn = false;
      });
      await _finishLogin(context);
    } catch (e, st) {
      logger.error('Login', '离线模式切换失败', e, st);
      if (!mounted) return;
      await AppDialog.error(context,
          title: l10n.commonError, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitAuth(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final serverUrl =
        '${serverUrls[_selectedServerIndex]['scheme']}${serverUrls[_selectedServerIndex]['ip']}:${serverUrls[_selectedServerIndex]['port']}';
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
      final wasOffline = await ref.read(beecountOfflineModeProvider.future);
      final db = ref.read(databaseProvider);
      bool hasLocalData = false;
      if (wasOffline) {
        final ledgers = await db.select(db.ledgers).get();
        final transactions = await db.select(db.transactions).get();
        hasLocalData = ledgers.isNotEmpty || transactions.isNotEmpty;
      }

      final auth = ref.read(beecountAuthControllerProvider);
      logger.info("login",
          "登录/注册 :  ${_isRegister ? '注册' : '登录'} url : $serverUrl  账号 : $username 密码 : $password");
      if (_isRegister) {
        await auth.signUp(
            serverUrl: serverUrl, username: username, password: password);
      } else {
        await auth.signIn(
            serverUrl: serverUrl, username: username, password: password);
      }

      if (!mounted) return;
      await _saveCredentials(username, password);

      if (wasOffline && hasLocalData) {
        final syncLocalData = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('数据同步'),
            content: const Text(
                '检测到本地有数据，是否将本地数据同步到服务器？\n\n选择"同步"：本地数据将上传到服务器\n选择"不同步"：将清空本地数据并从服务器拉取数据'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('不同步'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('同步'),
              ),
            ],
          ),
        );

        if (syncLocalData == true) {
          logger.info('Login', '用户选择同步本地数据到服务器');
          await _syncLocalDataToServer(db);
        } else {
          logger.info('Login', '用户选择不同步，清空本地数据');
          await db.delete(db.transactions).go();
          await db.delete(db.accounts).go();
          await db.delete(db.categories).go();
          await db.delete(db.ledgers).go();
          await db.delete(db.tags).go();
          await db.delete(db.budgets).go();
          await db.delete(db.recurringTransactions).go();
          await db.delete(db.transactionTags).go();
          await db.customStatement('DELETE FROM sync_id_maps');
          await db.customStatement('DELETE FROM local_change_log');
          await db.customStatement('DELETE FROM sync_queue_items');
        }
      }

      setState(() {
        _offlineSelected = false;
        _loggedIn = true;
      });
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

  Future<void> _syncLocalDataToServer(BeeDatabase db) async {
    try {
      final provider = await ref.read(beecountProviderProvider.future);
      if (provider == null) {
        logger.error('Login', '无法获取 CloudProvider');
        return;
      }

      final syncEngine = BeeCountSyncEngine(db: db, provider: provider);
      syncEngine.start();

      try {
        final ledgers = await db.select(db.ledgers).get();
        for (final r in ledgers) {
          logger.info('Login', '同步账本 ${r.name} ID: ${r.id}');
          await syncEngine.enqueueUpsert('ledgers', r.id);
        }

        final accounts = await db.select(db.accounts).get();
        for (final r in accounts) {
          logger.info('Login', '同步账户 ${r.name} ID: ${r.id}');
          await syncEngine.enqueueUpsert('accounts', r.id);
        }

        final categories = await db.select(db.categories).get();
        for (final r in categories) {
          logger.info('Login', '同步分类 ${r.name} ID: ${r.id}');
          await syncEngine.enqueueUpsert('categories', r.id);
        }

        final tags = await db.select(db.tags).get();
        for (final r in tags) {
          logger.info('Login', '同步标签 ${r.name} ID: ${r.id}');
          await syncEngine.enqueueUpsert('tags', r.id);
        }

        final budgets = await db.select(db.budgets).get();
        for (final r in budgets) {
          logger.info('Login', '同步预算 ID: ${r.id}');
          await syncEngine.enqueueUpsert('budgets', r.id);
        }

        final recurring = await db.select(db.recurringTransactions).get();
        for (final r in recurring) {
          logger.info('Login', '同步周期交易 ID: ${r.id}');
          await syncEngine.enqueueUpsert('recurring_transactions', r.id);
        }

        final transactions = await db.select(db.transactions).get();
        for (final r in transactions) {
          logger.info('Login', '同步交易 ID: ${r.id}');
          await syncEngine.enqueueUpsert('transactions', r.id);
        }

        final transactionTags = await db.select(db.transactionTags).get();
        for (final r in transactionTags) {
          await syncEngine.enqueueUpsert('transaction_tags', r.id);
        }

        await syncEngine.flush();
        logger.info('Login', '本地数据同步完成');
      } finally {
        syncEngine.dispose();
      }
    } catch (e, st) {
      logger.error('Login', '同步本地数据失败', e, st);
    }
  }

  Future<void> _finishLogin(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('welcome_shown', true);
      await prefs.setString('selected_currency', 'CNY');
      await prefs.setString('category_mode', 'hierarchical'); // 固定为二级分类模式
      // await prefs.setString('app_mode', 'local');

      final db = ref.read(databaseProvider);

      final offline = await ref.read(beecountOfflineModeProvider.future);
      LocalStorageUtils.setAppStatus(offline
          ? LocalStorageUtils.appStatusOffline
          : LocalStorageUtils.appStatusOnline);

      if (!offline) {
        CloudProvider? provider;
        try {
          provider = await ref.read(beecountProviderProvider.future);
        } catch (e) {
          logger.warning('Login', '获取 CloudProvider 失败: $e');
        }

        if (provider != null) {
          logger.info('Login', '在线模式，按数据表维度拉取数据');

          final syncEngine = BeeCountSyncEngine(db: db, provider: provider);
          syncEngine.start();

          try {
            final initialSyncService = BeeCountInitialSyncService(
              db: db,
              provider: provider,
              sync: syncEngine,
            );

            await initialSyncService.run();

            final ledgers = await db.select(db.ledgers).get();
            final accounts = await db.select(db.accounts).get();
            final categories = await db.select(db.categories).get();

            final hasLedgers = ledgers.isNotEmpty;
            final hasAccounts = accounts.isNotEmpty;
            final hasCategories = categories.isNotEmpty;

            if (!hasLedgers) {
              logger.info('Login', '服务器没有账本数据，初始化默认账本');
              await SeedService.createDefaultLedger(db, l10n, 'CNY');
              final ledgers = await db.select(db.ledgers).get();
              for (final r in ledgers) {
                logger.info('Login', '同步账本 ${r.name} ID: ${r.id}');
                await syncEngine.enqueueUpsert('ledgers', r.id);
              }
            } else {
              logger.info('Login', '服务器已有账本数据，不需要初始化默认账本');
            }

            if (!hasAccounts) {
              logger.info('Login', '服务器没有账户数据，初始化默认账户');
              final ledgers = await db.select(db.ledgers).get();
              if (ledgers.isNotEmpty) {
                await SeedService.createDefaultAccounts(
                    db, ledgers.first.id, l10n, 'CNY');
              }
              final accounts = await db.select(db.accounts).get();
              for (final r in accounts) {
                logger.info('Login', '同步账户 ${r.name} ID: ${r.id}');
                await syncEngine.enqueueUpsert('accounts', r.id);
              }
            } else {
              logger.info('Login', '服务器已有账户数据，不需要初始化默认账户');
            }

            if (!hasCategories) {
              logger.info('Login', '服务器没有分类数据，初始化默认分类（二级分类模式）');
              await SeedService.createHierarchicalCategories(db, l10n);
              final categories = await db.select(db.categories).get();
              for (final r in categories) {
                logger.info('Login', '同步分类 ${r.name} ID: ${r.id}');
                await syncEngine.enqueueUpsert('categories', r.id);
              }
            } else {
              logger.info('Login', '服务器已有分类数据，不需要初始化默认分类');
            }

            await SeedService.createTransferCategory(db, l10n);
            await syncEngine.flush();
          } finally {
            syncEngine.dispose();
          }
        } else {
          logger.info('Login', 'Provider 为空，初始化默认本地数据（二级分类模式）');
          await db.ensureSeed(
            l10n: l10n,
            currency: 'CNY',
            useHierarchicalCategories: true, // 固定为二级分类模式
            skipCategories: false,
          );
        }
      } else {
        logger.info('Login', '离线模式，初始化默认本地数据（二级分类模式）');
        await db.ensureSeed(
          l10n: l10n,
          currency: 'CNY',
          useHierarchicalCategories: true, // 固定为二级分类模式
          skipCategories: false,
        );
      }

      // 设置当前账本为第一个有效账本
      final ledgers = await db.select(db.ledgers).get();
      if (ledgers.isNotEmpty) {
        final firstLedgerId = ledgers.first.id;
        ref.read(currentLedgerIdProvider.notifier).state = firstLedgerId;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('current_ledger_id', firstLedgerId);
        logger.info('Login', '设置当前账本 ID: $firstLedgerId');
      }
      ref.read(shouldShowLoginProvider.notifier).state = false;
      ref.read(appInitStateProvider.notifier).state = AppInitState.ready;
      
      // 显式跳转到主应用页面
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
          title: l10n.commonError, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _saveCredentials(String email, String password) async {
    // Only save credentials when in Supabase or BeeCount mode
    try {
      final cloudConfig = await ref.read(activeCloudConfigProvider.future);
      final store = ref.read(cloudServiceStoreProvider);

      // Create updated config with or without credentials based on checkbox
      CloudServiceConfig updatedConfig;
      updatedConfig = CloudServiceConfig(
        type: CloudBackendType.beecount,
        name: cloudConfig.name,
        beecountServerUrl: cloudConfig.beecountServerUrl,
        beecountUsername: email,
        beecountPassword: password,
      );

      await store.saveOnly(updatedConfig);
      ref.invalidate(supabaseConfigProvider);
      ref.invalidate(beecountConfigProvider);
      ref.invalidate(activeCloudConfigProvider);

      logger.info('auth', '账号密码保存状态：已保存');
    } catch (e, st) {
      logger.error('auth', '保存账号密码失败', e, st);
    }
  }
}
