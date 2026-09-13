import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../utils/invest_tx.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/ui/ui.dart';
import '../../services/attachment_service.dart';
import '../attachment/attachment_preview_page.dart';
import '../tag/tag_detail_page.dart';

class TransactionDetailPage extends ConsumerWidget {
  final int transactionId;

  const TransactionDetailPage({
    super.key,
    required this.transactionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(_transactionDetailProvider(transactionId));

    return BeeScaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.transactionDetailTitle,
            showBack: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l10n.commonEdit,
                onPressed: () => _edit(context, ref, detailAsync.valueOrNull),
              ),
            ],
          ),
          Expanded(
            child: detailAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('${l10n.commonError}: $e'),
              ),
              data: (detail) {
                if (detail == null) {
                  return Center(child: Text(l10n.transactionNotFound));
                }
                return _DetailBody(detail: detail);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    _TransactionDetail? detail,
  ) async {
    if (detail == null) return;
    await TransactionEditUtils.editTransaction(
      context,
      ref,
      detail.tx,
      detail.category,
    );
    ref.invalidate(_transactionDetailProvider(transactionId));
  }
}

class _DetailBody extends ConsumerWidget {
  final _TransactionDetail detail;

  const _DetailBody({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tx = detail.tx;
    final isExpense = tx.type == 'expense' || tx.type == InvestTx.loss;
    final isTransfer = tx.type == 'transfer';
    final categoryName = CategoryUtils.getDisplayName(
      detail.category?.name ?? l10n.commonUncategorized,
      context,
    );
    final timeText = DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.happenedAt.toLocal());
    final amountColor = isTransfer
        ? BeeTokens.textPrimary(context)
        : isExpense
            ? BeeTokens.expenseColor(context, ref)
            : BeeTokens.incomeColor(context, ref);

    return ListView(
      padding: EdgeInsets.all(16.0.scaled(context, ref)),
      children: [
        SectionCard(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(16.0.scaled(context, ref)),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: CategoryIconWidget(
                    category: detail.category,
                    size: 26,
                  ),
                ),
                SizedBox(height: 12.0.scaled(context, ref)),
                AmountText(
                  value: isExpense ? -tx.amount : tx.amount,
                  signed: !isTransfer,
                  decimals: 2,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                ),
                SizedBox(height: 4.0.scaled(context, ref)),
                Text(
                  _typeLabel(l10n, tx.type),
                  style: TextStyle(
                    fontSize: 13,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 12.0.scaled(context, ref)),
        SectionCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _InfoRow(
                label: l10n.transactionDetailType,
                value: _typeLabel(l10n, tx.type),
              ),
              BeeTokens.cardDivider(context),
              _InfoRow(
                label: l10n.categoryNameLabel,
                value: isTransfer ? l10n.transferTitle : categoryName,
              ),
              BeeTokens.cardDivider(context),
              _InfoRow(
                label: l10n.transactionDetailTime,
                value: timeText,
              ),
              if (isTransfer) ...[
                BeeTokens.cardDivider(context),
                _InfoRow(
                  label: l10n.transferFromAccount,
                  value: detail.fromAccountName ?? '—',
                ),
                BeeTokens.cardDivider(context),
                _InfoRow(
                  label: l10n.transferToAccount,
                  value: detail.toAccountName ?? '—',
                ),
              ] else if (detail.accountName != null) ...[
                BeeTokens.cardDivider(context),
                _InfoRow(
                  label: l10n.accountNameLabel,
                  value: detail.accountName!,
                ),
              ],
              if (tx.note != null && tx.note!.isNotEmpty) ...[
                BeeTokens.cardDivider(context),
                _InfoRow(
                  label: l10n.transactionDetailNote,
                  value: tx.note!,
                ),
              ],
              if (detail.ledgerName != null && detail.ledgerName!.isNotEmpty) ...[
                BeeTokens.cardDivider(context),
                _InfoRow(
                  label: l10n.transactionDetailLedger,
                  value: detail.ledgerName!,
                ),
              ],
              if (tx.investEvent != null && tx.investEvent!.isNotEmpty) ...[
                BeeTokens.cardDivider(context),
                _InfoRow(
                  label: l10n.investActionsTitle,
                  value: _investEventLabel(l10n, tx.investEvent!),
                ),
              ],
            ],
          ),
        ),
        if (detail.tags.isNotEmpty) ...[
          SizedBox(height: 12.0.scaled(context, ref)),
          SectionCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.transactionDetailTags,
                  style: TextStyle(
                    fontSize: 13,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
                SizedBox(height: 8.0.scaled(context, ref)),
                TagChipList(
                  tags: detail.tags
                      .map((t) => (id: t.id, name: t.name, color: t.color))
                      .toList(),
                  onTagTap: (id, name) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TagDetailPage(tagId: id, tagName: name),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
        if (detail.attachments.isNotEmpty) ...[
          SizedBox(height: 12.0.scaled(context, ref)),
          SectionCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.transactionDetailAttachments,
                  style: TextStyle(
                    fontSize: 13,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
                SizedBox(height: 8.0.scaled(context, ref)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < detail.attachments.length; i++)
                      _AttachmentThumb(
                        fileName: detail.attachments[i].fileName,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AttachmentPreviewPage(
                                attachments: detail.attachments,
                                initialIndex: i,
                                transactionId: tx.id,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _typeLabel(AppLocalizations l10n, String type) {
    switch (type) {
      case 'income':
        return l10n.homeIncome;
      case 'expense':
        return l10n.homeExpense;
      case 'transfer':
        return l10n.transferTitle;
      case InvestTx.gain:
        return l10n.investGain;
      case InvestTx.loss:
        return l10n.investLoss;
      default:
        return type;
    }
  }

  String _investEventLabel(AppLocalizations l10n, String event) {
    switch (event) {
      case InvestTx.eventDividend:
        return l10n.investEventDividend;
      case InvestTx.eventMarkToMarket:
        return l10n.investEventMark;
      default:
        return l10n.investEventManual;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: BeeTokens.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentThumb extends ConsumerWidget {
  final String fileName;
  final VoidCallback onTap;

  const _AttachmentThumb({required this.fileName, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.read(attachmentServiceProvider).getAttachmentPath(fileName),
      builder: (context, snapshot) {
        final path = snapshot.data;
        return GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 72,
              height: 72,
              child: path != null && File(path).existsSync()
                  ? Image.file(File(path), fit: BoxFit.cover)
                  : ColoredBox(
                      color: BeeTokens.surfaceSecondary(context),
                      child: Icon(
                        Icons.image_outlined,
                        color: BeeTokens.textTertiary(context),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _TransactionDetail {
  final db.Transaction tx;
  final db.Category? category;
  final String? accountName;
  final String? fromAccountName;
  final String? toAccountName;
  final String? ledgerName;
  final List<db.Tag> tags;
  final List<db.TransactionAttachment> attachments;

  const _TransactionDetail({
    required this.tx,
    required this.category,
    required this.accountName,
    required this.fromAccountName,
    required this.toAccountName,
    required this.ledgerName,
    required this.tags,
    required this.attachments,
  });
}

final _transactionDetailProvider =
    FutureProvider.family.autoDispose<_TransactionDetail?, int>((ref, id) async {
  final repo = ref.watch(repositoryProvider);
  final tx = await repo.getTransactionById(id);
  if (tx == null) return null;

  final category = tx.categoryId != null
      ? await repo.getCategoryById(tx.categoryId!)
      : null;
  final tagsMap = await repo.getTagsForTransactions([id]);
  final tags = tagsMap[id] ?? [];
  final attachments = await repo.getAttachmentsByTransaction(id);
  final ledger = await repo.getLedgerById(tx.ledgerId);

  String? accountName;
  String? fromAccountName;
  String? toAccountName;
  if (tx.type == 'transfer') {
    if (tx.accountId != null) {
      fromAccountName = (await repo.getAccount(tx.accountId!))?.name;
    }
    if (tx.toAccountId != null) {
      toAccountName = (await repo.getAccount(tx.toAccountId!))?.name;
    }
  } else if (tx.accountId != null) {
    accountName = (await repo.getAccount(tx.accountId!))?.name;
  }

  var ledgerName = ledger?.name;
  if (ledgerName == 'Default Ledger') {
    ledgerName = null;
  }

  return _TransactionDetail(
    tx: tx,
    category: category,
    accountName: accountName,
    fromAccountName: fromAccountName,
    toAccountName: toAccountName,
    ledgerName: ledgerName,
    tags: tags,
    attachments: attachments,
  );
});
