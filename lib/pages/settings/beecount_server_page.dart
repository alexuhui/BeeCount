import 'package:beecount/pages/auth/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/beecount_server_providers.dart';
import '../../widgets/ui/ui.dart';

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
                    builder: (_) => WelcomePage(
                      index: 1,
                    ),
                  ),
                )
              },
              child: Text("前往注册/登录"),
            ),
          ],
          if (!offline) ...[
            FilledButton(
              onPressed: () async {
                final ok = await AppDialog.confirm(
                  context,
                  title: l10n.mineLogoutConfirmTitle,
                  message: l10n.mineLogoutConfirmMessage,
                  okLabel: l10n.commonConfirm,
                  cancelLabel: l10n.commonCancel,
                );
                if (ok == true) {
                  await ref.read(beecountAuthControllerProvider).signOut();

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WelcomePage(
                        index: 1,
                      ),
                    ),
                  );
                }
              },
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
}
