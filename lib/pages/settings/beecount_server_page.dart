import 'package:beecount/pages/auth/login_page.dart';
import 'package:flutter/material.dart';
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
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessionAsync = ref.watch(beecountSessionProvider);
    final session = sessionAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cloudCustomBeeCountTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            session == null
                ? l10n.mineSyncNotLoggedIn
                : '${l10n.mineLoggedInEmail}: ${session.username}',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _handleSignOut(context, ref),
            child: Text(l10n.mineLogoutConfirmTitle),
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
        content: const Text('退出后需要重新登录才能记账。确定退出？'),
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
      await LocalStorageUtils.setAppStatus(LocalStorageUtils.appStatusNone);

      Future.microtask(() {
        if (!mounted) return;
        ref.invalidate(beecountSessionProvider);
        ref.invalidate(loginCheckProvider);
        ref.invalidate(appInitStateProvider);
        ref.read(shouldShowLoginProvider.notifier).state = true;
        ref.read(appInitStateProvider.notifier).state = AppInitState.splash;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      });
    } catch (e) {
      logger.error('BeeCountServerPage', '退出失败: $e');
    }
  }
}
