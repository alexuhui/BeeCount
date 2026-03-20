import 'package:beecount/data/db.dart';
import 'package:beecount/services/sync/beecount_sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/beecount_server_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/language_provider.dart';
import '../../providers/ui_state_providers.dart';
import '../../services/data/seed_service.dart';
import '../../services/system/logger_service.dart';
import '../../services/sync/beecount_initial_sync_service.dart';
import '../../widgets/ui/ui.dart';

class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  final PageController _pageController = PageController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  int _currentPage = 0;
  String _categoryMode = 'flat';
  bool _isSubmitting = false;
  bool _offlineSelected = false;
  bool _loggedIn = false;
  bool _isRegister = false;

  /// 服务器列表
  final serverUrls = [
    {'name': '测试服务器', 'ip': '172.25.26.17', 'port': 6060, 'scheme':'http://'},
    {'name': '线上服务器', 'ip': '43.139.239.34', 'port': 6060, 'scheme':'http://'},
  ];

  int _selectedServerIndex = 0;


  @override
  void dispose() {
    _pageController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canProceedFromLogin => _offlineSelected || _loggedIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final pages = [
      _buildLanguagePage(context, theme, l10n),
      _buildLoginPage(context, theme, l10n),
      _buildCategoryModePage(context, theme, l10n),
    ];

    return Scaffold(
      backgroundColor: theme.primaryColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Text(l10n.commonPrevious),
                    ),
                  const Spacer(),
                  if (_currentPage < pages.length - 1)
                    FilledButton(
                      onPressed: _isSubmitting
                          ? null
                          : (_currentPage == 1 && !_canProceedFromLogin)
                              ? null
                              : () {
                                  _pageController.nextPage(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeInOut,
                                  );
                                },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: theme.primaryColor,
                      ),
                      child: Text(l10n.commonNext),
                    )
                  else
                    FilledButton(
                      onPressed: _isSubmitting ? null : () => _finishWelcome(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: theme.primaryColor,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.commonFinish),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguagePage(BuildContext context, ThemeData theme, AppLocalizations l10n) {
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
      if (locale.languageCode == 'zh' && locale.countryCode == null) return '简体中文';
      if (locale.languageCode == 'zh' && locale.countryCode == 'TW') return '繁體中文';
      if (locale.languageCode == 'en') return 'English';
      return locale.toString();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SvgPicture.asset('assets/logo.svg', fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.welcomeTitle,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.welcomeDescription,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: availableLocales.map((locale) {
                final selected = currentLocale == locale;
                return ListTile(
                  title: Text(
                    nameForLocale(locale),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: selected ? const Icon(Icons.check, color: Colors.white) : null,
                  onTap: () => languageNotifier.setLanguage(locale),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginPage(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cloudCustomBeeCountTitle,
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
                : (_loggedIn ? l10n.mineSyncInSyncSimple : l10n.mineSyncNotLoggedIn),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
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
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  dropdownColor: Colors.black.withValues(alpha: 0.8),
                  onChanged: (!_isSubmitting && !_offlineSelected) ? (value) {
                    if (value != null) {
                      setState(() {
                        _selectedServerIndex = value;
                      });
                    }
                  } : null,
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
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                              color: Colors.white.withValues(alpha: 0.9)),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isSubmitting || _offlineSelected ? null : () => _submitAuth(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: theme.primaryColor,
                  ),
                  child: Text(_isRegister ? l10n.authSignup : l10n.authLogin),
                ),
                TextButton(
                  onPressed: _isSubmitting || _offlineSelected
                      ? null
                      : () => setState(() => _isRegister = !_isRegister),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Text(_isRegister ? l10n.authLogin : l10n.authSignup),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _isSubmitting ? null : () => _useOfflineAndNext(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
            ),
            child: Text(l10n.mineCloudServiceOffline),
          ),
        ],
      ),
    );
  }

  Future<void> _useOfflineAndNext(BuildContext context) async {
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
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } catch (e, st) {
      logger.error('WelcomeLogin', '离线模式切换失败', e, st);
      if (!mounted) return;
      await AppDialog.error(context, title: l10n.commonError, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitAuth(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final serverUrl = '${serverUrls[_selectedServerIndex]['scheme']}${serverUrls[_selectedServerIndex]['ip']}:${serverUrls[_selectedServerIndex]['port']}';
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      await AppDialog.error(context, title: l10n.commonError, message: '请填写服务器地址、账号与密码');
      return;
    }
    if (_isRegister) {
      final confirmPassword = _confirmPasswordController.text;
      if (confirmPassword.isEmpty || confirmPassword != password) {
        await AppDialog.error(context, title: l10n.commonError, message: '两次输入的密码不一致');
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final auth = ref.read(beecountAuthControllerProvider);
      logger.info("welcome", "登录/注册 :  ${_isRegister ? '注册' : '登录'} url : $serverUrl  账号 : $username 密码 : $password");
      if (_isRegister) {
        await auth.signUp(serverUrl: serverUrl, username: username, password: password);
      } else {
        await auth.signIn(serverUrl: serverUrl, username: username, password: password);
      }

      if (!mounted) return;
      setState(() {
        _offlineSelected = false;
        _loggedIn = true;
      });
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } catch (e, st) {
      logger.error('WelcomeLogin', '登录/注册失败', e, st);
      if (!mounted) return;
      await AppDialog.error(context, title: l10n.commonError, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildCategoryModePage(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    Widget modeTile({
      required String value,
      required String title,
      required String subtitle,
    }) {
      final selected = _categoryMode == value;
      return ListTile(
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
        ),
        trailing: selected ? const Icon(Icons.check, color: Colors.white) : null,
        onTap: () => setState(() => _categoryMode = value),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.welcomeCategoryModeTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.welcomeCategoryModeDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                modeTile(
                  value: 'flat',
                  title: l10n.welcomeCategoryModeFlatTitle,
                  subtitle: l10n.welcomeCategoryModeFlatDescription,
                ),
                modeTile(
                  value: 'hierarchical',
                  title: l10n.welcomeCategoryModeHierarchicalTitle,
                  subtitle: l10n.welcomeCategoryModeHierarchicalDescription,
                ),
                modeTile(
                  value: 'none',
                  title: l10n.welcomeCategoryModeNoneTitle,
                  subtitle: l10n.welcomeCategoryModeNoneDescription,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _finishWelcome(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('welcome_shown', true);
      await prefs.setString('selected_currency', 'CNY');
      await prefs.setString('category_mode', _categoryMode);
      await prefs.setString('app_mode', 'local');

      final db = ref.read(databaseProvider);
      
      // 检查是否是在线模式
      final providerAsync = ref.watch(beecountProviderProvider);
      if (providerAsync.hasValue && providerAsync.value != null) {
        final provider = providerAsync.value!;
        logger.info('WelcomeFinish', '在线模式，按数据表维度拉取数据');
        
        // 创建同步引擎
        final syncEngine = BeeCountSyncEngine(db: db, provider: provider);
        syncEngine.start();
        
        try {
          // 创建初始同步服务
          final initialSyncService = BeeCountInitialSyncService(
            db: db,
            provider: provider,
            sync: syncEngine,
          );
          
          // 运行同步服务，拉取并合并服务器数据
          await initialSyncService.run();
          
          // 检查每个数据表是否有服务器数据
          final ledgers = await db.select(db.ledgers).get();
          final accounts = await db.select(db.accounts).get();
          final categories = await db.select(db.categories).get();
          
          final hasLedgers = ledgers.isNotEmpty;
          final hasAccounts = accounts.isNotEmpty;
          final hasCategories = categories.isNotEmpty;
          
          // 如果服务器没有账本数据，初始化默认账本
          if (!hasLedgers) {
            logger.info('WelcomeFinish', '服务器没有账本数据，初始化默认账本');
            await SeedService.createDefaultLedger(db, l10n, 'CNY');
            // 同步默认账本到服务器
            final ledgers = await db.select(db.ledgers).get();
            for (final r in ledgers) {
              logger.info('WelcomeFinish', '同步账本 ${r.name} ID: ${r.id}');
              await syncEngine.enqueueUpsert('ledgers', r.id);
            }
          }else{
            logger.info('WelcomeFinish', '服务器已有账本数据，不需要初始化默认账本');
          }
          
          // 如果服务器没有账户数据，初始化默认账户
          if (!hasAccounts) {
            logger.info('WelcomeFinish', '服务器没有账户数据，初始化默认账户');
            final ledgers = await db.select(db.ledgers).get();
            if (ledgers.isNotEmpty) {
              await SeedService.createDefaultAccounts(db, ledgers.first.id, l10n, 'CNY');
            }
            // 同步默认账户到服务器
            final accounts = await db.select(db.accounts).get();
            for (final r in accounts) {
              logger.info('WelcomeFinish', '同步账户 ${r.name} ID: ${r.id}');
              await syncEngine.enqueueUpsert('accounts', r.id);
            }
          }else{
            logger.info('WelcomeFinish', '服务器已有账户数据，不需要初始化默认账户');
          }
          
          // 如果服务器没有分类数据，初始化默认分类
          if (!hasCategories && _categoryMode != 'none') {
            logger.info('WelcomeFinish', '服务器没有分类数据，初始化默认分类');
            if (_categoryMode == 'hierarchical') {
              await SeedService.createHierarchicalCategories(db, l10n);
            } else {
              await SeedService.createFlatCategories(db, l10n);
            }
            // 同步默认分类到服务器
            final categories = await db.select(db.categories).get();
            for (final r in categories) {
              logger.info('WelcomeFinish', '同步分类 ${r.name} ID: ${r.id}');
              await syncEngine.enqueueUpsert('categories', r.id);
            }
          }else{
            logger.info('WelcomeFinish', '服务器已有分类数据，不需要初始化默认分类');
          }
          
          // 确保创建虚拟转账分类
          await SeedService.createTransferCategory(db, l10n);
          await syncEngine.flush();

        } finally {
          syncEngine.dispose();
        }
      } else {
        logger.info('WelcomeFinish', '离线模式，初始化默认本地数据');
        // 离线模式，直接初始化默认本地数据
        await db.ensureSeed(
          l10n: l10n,
          currency: 'CNY',
          useHierarchicalCategories: _categoryMode == 'hierarchical',
          skipCategories: _categoryMode == 'none',
        );
      }

      ref.read(shouldShowWelcomeProvider.notifier).state = false;
    } catch (e, st) {
      logger.error('WelcomeFinish', '完成引导失败', e, st);
      if (!mounted) return;
      await AppDialog.error(context, title: l10n.commonError, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
