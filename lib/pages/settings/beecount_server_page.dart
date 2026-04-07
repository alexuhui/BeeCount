import 'package:beecount/pages/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/all_providers.dart';
import '../../providers/beecount_server_providers.dart';
import '../../services/system/logger_service.dart';
import '../../utils/local_storage_utils.dart';

class BeeCountServerPage extends ConsumerStatefulWidget {
  const BeeCountServerPage({super.key});

  @override
  ConsumerState<BeeCountServerPage> createState() => _BeeCountServerPageState();
}

class _BeeCountServerPageState extends ConsumerState<BeeCountServerPage> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offlineAsync = ref.watch(beecountOfflineModeProvider);
    ref.watch(beecountSessionProvider);
    final pendingAsync = ref.watch(beecountPendingSyncCountProvider);
    final syncEngine = ref.watch(beecountSyncEngineProvider);

    final offline = offlineAsync.asData?.value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cloudCustomBeeCountTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 当前模式
          Text(
            "当前模式是：${offline ? "离线模式" : "在线模式"}",
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 12),
          if (offline) ...[
            FilledButton(
              onPressed: () => {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LoginPage(),
                  ),
                )
              },
              child: Text("前往注册/登录"),
            ),
          ],
          if (!offline) ...[
            FilledButton(
              onPressed: () => _handleSignOut(context, ref),
              child: Text(l10n.mineLogoutConfirmTitle),
            ),
          ],
          const SizedBox(height: 12),

          if (!offline)
            pendingAsync.when(
              data: (n) => ListTile(
                title: const Text('同步队列'),
                subtitle: Text('待同步: $n'),
                trailing: FilledButton(
                  onPressed:
                      (syncEngine == null) ? null : () => syncEngine.flush(),
                  child: const Text('立即同步'),
                ),
              ),
              loading: () =>
                  const ListTile(title: Text('同步队列'), subtitle: Text('加载中...')),
              error: (e, _) => ListTile(
                  title: const Text('同步队列'), subtitle: Text(e.toString())),
            ),
        ],
      ),
    );
  }

  void _handleSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text(
            '退出后当前账号的本地数据仍保留在本机（按账号隔离）。下次用同一账号登录可继续使用。确定退出？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(beecountAuthControllerProvider).signOut();
      logger.info('BeeCountServerPage', '已退出登录（本地库未删除）');

      LocalStorageUtils.setAppStatus(LocalStorageUtils.appStatusNone);

      // 延迟执行状态更新和导航，避免在 build 阶段调用 setState
      Future.microtask(() {
        if (!mounted) return;
        ref.invalidate(beecountOfflineModeProvider);
        ref.invalidate(beecountSessionProvider);
        ref.invalidate(beecountProviderProvider);
        ref.invalidate(loginCheckProvider);
        ref.invalidate(appInitStateProvider);
        ref.read(shouldShowLoginProvider.notifier).state = true;
        ref.read(appInitStateProvider.notifier).state = AppInitState.splash;

        // 使用 pushAndRemoveUntil 强制导航到登录页面
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      });
    } catch (e) {
      logger.error('BeeCountServerPage', '清空数据失败: $e');
    }
  }
}
