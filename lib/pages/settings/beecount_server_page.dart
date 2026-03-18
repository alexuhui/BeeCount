import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/beecount_server_providers.dart';
import '../../services/system/logger_service.dart';
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
  bool _isRegister = false;
  bool _submitting = false;

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
    final sessionAsync = ref.watch(beecountSessionProvider);
    final pendingAsync = ref.watch(beecountPendingSyncCountProvider);
    final syncEngine = ref.watch(beecountSyncEngineProvider);

    final offline = offlineAsync.asData?.value ?? false;
    final session = sessionAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cloudCustomBeeCountTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: offline,
            title: Text(l10n.mineCloudServiceOffline),
            onChanged: _submitting
                ? null
                : (v) async {
                    if (v) {
                      await ref.read(beecountAuthControllerProvider).useOfflineMode();
                    } else {
                      await ref.read(beecountOfflineModeSetterProvider).set(false);
                    }
                  },
          ),
          const SizedBox(height: 12),
          if (!offline) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _serverUrlController,
                      enabled: !_submitting && session == null,
                      decoration: InputDecoration(
                        labelText: l10n.cloudBeeCountServerUrlLabel,
                        hintText: l10n.cloudBeeCountServerUrlHint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _usernameController,
                      enabled: !_submitting && session == null,
                      decoration: InputDecoration(labelText: l10n.authEmail),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      enabled: !_submitting && session == null,
                      obscureText: true,
                      decoration: InputDecoration(labelText: l10n.authPassword),
                    ),
                    const SizedBox(height: 16),
                    if (session == null)
                      FilledButton(
                        onPressed: _submitting ? null : () => _submit(context),
                        child: Text(_isRegister ? l10n.authSignup : l10n.authLogin),
                      )
                    else
                      FilledButton(
                        onPressed: _submitting
                            ? null
                            : () async {
                                final ok = await AppDialog.confirm(
                                  context,
                                  title: l10n.mineLogoutConfirmTitle,
                                  message: l10n.mineLogoutConfirmMessage,
                                  okLabel: l10n.commonConfirm,
                                  cancelLabel: l10n.commonCancel,
                                );
                                if (ok == true) {
                                  await ref.read(beecountAuthControllerProvider).signOut();
                                }
                              },
                        child: Text(l10n.mineLogoutConfirmTitle),
                      ),
                    if (session == null)
                      TextButton(
                        onPressed: _submitting ? null : () => setState(() => _isRegister = !_isRegister),
                        child: Text(_isRegister ? l10n.authLogin : l10n.authSignup),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('${l10n.mineLoggedInEmail}: ${session.username}'),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          pendingAsync.when(
            data: (n) => ListTile(
              title: const Text('同步队列'),
              subtitle: Text('待同步: $n'),
              trailing: FilledButton(
                onPressed: (syncEngine == null || _submitting) ? null : () => syncEngine.flush(),
                child: const Text('立即同步'),
              ),
            ),
            loading: () => const ListTile(title: Text('同步队列'), subtitle: Text('加载中...')),
            error: (e, _) => ListTile(title: const Text('同步队列'), subtitle: Text(e.toString())),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final serverUrl = _serverUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      await AppDialog.error(context, title: l10n.commonError, message: '请填写服务器地址、账号与密码');
      return;
    }

    setState(() => _submitting = true);
    try {
      final auth = ref.read(beecountAuthControllerProvider);
      if (_isRegister) {
        await auth.signUp(serverUrl: serverUrl, username: username, password: password);
      } else {
        await auth.signIn(serverUrl: serverUrl, username: username, password: password);
      }
    } catch (e, st) {
      logger.error('BeeCountServerPage', '登录/注册失败', e, st);
      if (!mounted) return;
      await AppDialog.error(context, title: l10n.commonError, message: e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
