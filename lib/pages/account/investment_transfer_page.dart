import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../widgets/transaction/transfer_form.dart';
import '../../widgets/ui/ui.dart';

class InvestmentTransferPage extends ConsumerWidget {
  final int investmentAccountId;
  final bool transferIn;

  const InvestmentTransferPage({
    super.key,
    required this.investmentAccountId,
    required this.transferIn,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return BeeScaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: transferIn ? l10n.investTransferIn : l10n.investTransferOut,
            showBack: true,
          ),
          Expanded(
            child: TransferForm(
              onTransferComplete: () {
                if (context.mounted) Navigator.pop(context);
              },
              initialFromAccountId:
                  transferIn ? null : investmentAccountId,
              initialToAccountId: transferIn ? investmentAccountId : null,
            ),
          ),
        ],
      ),
    );
  }
}
