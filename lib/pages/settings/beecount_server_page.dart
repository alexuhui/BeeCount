import 'package:beecount/pages/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        title: const Text('本地数据清除'),
        content: const Text(
            '你当前是在线模式，退出操作将删除设备本地的所有账本、交易、分类等数据（不影响已上传服务器的数据）。确定要继续吗？'),
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
      logger.info('BeeCountServerPage', '已退出登录');

      final repository = ref.read(repositoryProvider);
      await repository.clearAllData();
      logger.info('BeeCountServerPage', '所有数据已清空');

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      logger.info('BeeCountServerPage', '已清除所有 SharedPreferences 数据');

      LocalStorageUtils.setAppStatus(LocalStorageUtils.appStatusNone);

      ref.invalidate(beecountOfflineModeProvider);
      ref.invalidate(beecountSessionProvider);
      ref.invalidate(beecountProviderProvider);
      ref.invalidate(loginCheckProvider);
      ref.invalidate(shouldShowLoginProvider);
      ref.invalidate(appInitStateProvider);

      // 退出当前页面
      Navigator.of(context).pop();
    } catch (e) {
      logger.error('BeeCountServerPage', '清空数据失败: $e');
    }
  }
}
