import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'accounts_section.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.accountsTitle,
            showBack: true,
            actions: [
              IconButton(
                onPressed: () => openAddAccount(context, ref),
                icon: const Icon(Icons.add),
                tooltip: l10n.accountAddTooltip,
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 8.0.scaled(context, ref),
              ),
              children: [
                const SectionCard(
                  margin: EdgeInsets.zero,
                  child: AccountsBody(),
                ),
                SizedBox(height: bottomPadding),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
