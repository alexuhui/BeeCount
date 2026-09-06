import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ui/ui.dart';
import 'accounts_section.dart';

class AccountSettingsPage extends ConsumerWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final groupByType =
        ref.watch(accountsGroupByTypeProvider).valueOrNull ?? false;
    final accounts =
        ref.watch(allAccountsStreamProvider).asData?.value ?? const [];

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.accountSettingsTitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 8),
                DefaultAccountSelector(
                  accounts: accounts,
                  primaryColor: primaryColor,
                  type: 'expense',
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: BeeTokens.divider(context),
                ),
                DefaultAccountSelector(
                  accounts: accounts,
                  primaryColor: primaryColor,
                  type: 'income',
                ),
                Divider(
                  height: 1,
                  color: BeeTokens.divider(context),
                ),
                SwitchListTile(
                  title: Text(l10n.accountGroupByTypeTitle),
                  subtitle: Text(l10n.accountGroupByTypeDesc),
                  value: groupByType,
                  onChanged: (value) async {
                    await ref
                        .read(accountsGroupByTypeSetterProvider)
                        .setEnabled(value);
                    ref.invalidate(accountsGroupByTypeProvider);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openAccountSettings(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const AccountSettingsPage(),
    ),
  );
}
