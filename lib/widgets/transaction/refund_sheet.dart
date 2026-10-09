import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/api/beecount_api_exception.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/refund_tx.dart';
import '../biz/account_picker.dart';
import '../ui/ui.dart';

/// 记一笔退款，或修改已有退款。成功时返回 true。
Future<bool?> showRefundSheet({
  required BuildContext context,
  required int originalId,
  required double originalAmount,
  required double alreadyRefunded,
  required int? originalAccountId,
  Transaction? editing,
}) {
  return _showLinkedSheet(
    context: context,
    reimbursement: false,
    originalId: originalId,
    originalAmount: originalAmount,
    alreadyRefunded: alreadyRefunded,
    originalAccountId: originalAccountId,
    editing: editing,
  );
}

/// 记一笔报销，或修改已有报销。金额可以高于原支出。成功时返回 true。
Future<bool?> showReimburseSheet({
  required BuildContext context,
  required int originalId,
  required double originalAmount,
  required double alreadyReimbursed,
  required int? originalAccountId,
  Transaction? editing,
}) {
  return _showLinkedSheet(
    context: context,
    reimbursement: true,
    originalId: originalId,
    originalAmount: originalAmount,
    alreadyRefunded: alreadyReimbursed,
    originalAccountId: originalAccountId,
    editing: editing,
  );
}

Future<bool?> _showLinkedSheet({
  required BuildContext context,
  required bool reimbursement,
  required int originalId,
  required double originalAmount,
  required double alreadyRefunded,
  required int? originalAccountId,
  Transaction? editing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BeeTokens.surfaceSheet(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _LinkedCreditSheet(
      reimbursement: reimbursement,
      originalId: originalId,
      originalAmount: originalAmount,
      alreadyRefunded: alreadyRefunded,
      originalAccountId: originalAccountId,
      editing: editing,
    ),
  );
}

class _LinkedCreditSheet extends ConsumerStatefulWidget {
  final bool reimbursement;
  final int originalId;
  final double originalAmount;
  final double alreadyRefunded;
  final int? originalAccountId;
  final Transaction? editing;

  const _LinkedCreditSheet({
    required this.reimbursement,
    required this.originalId,
    required this.originalAmount,
    required this.alreadyRefunded,
    required this.originalAccountId,
    this.editing,
  });

  @override
  ConsumerState<_LinkedCreditSheet> createState() => _LinkedCreditSheetState();
}

class _LinkedCreditSheetState extends ConsumerState<_LinkedCreditSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _reasonCtrl;
  late DateTime _happenedAt;
  late int? _accountId;
  bool _saving = false;
  String? _error;

  bool get _reimburse => widget.reimbursement;

  double get _remaining => RefundTx.remaining(
        original: widget.originalAmount,
        refunded: widget.alreadyRefunded,
      );

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final initial = editing != null
        ? RefundTx.roundMoney(editing.amount)
        : (_reimburse || _remaining <= 0
            ? RefundTx.roundMoney(widget.originalAmount)
            : _remaining);
    _amountCtrl = TextEditingController(text: _formatAmount(initial));
    _reasonCtrl = TextEditingController(text: editing?.note ?? '');
    _happenedAt = editing?.happenedAt.toLocal() ?? DateTime.now();
    _accountId = editing?.accountId ?? widget.originalAccountId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _formatAmount(double value) {
    final s = RefundTx.roundMoney(value).toStringAsFixed(2);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  String _formatDateTime(DateTime d) {
    final local = d.toLocal();
    final date =
        '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  Future<void> _pickDateTime() async {
    final date = await showWheelDatePicker(context, initial: _happenedAt);
    if (date == null || !mounted) return;
    final time = await showWheelTimePicker(
      context,
      initial: TimeOfDay.fromDateTime(_happenedAt),
    );
    if (!mounted) return;
    setState(() {
      final picked = time ?? TimeOfDay.fromDateTime(_happenedAt);
      _happenedAt = DateTime(
        date.year,
        date.month,
        date.day,
        picked.hour,
        picked.minute,
        _happenedAt.second,
      );
    });
  }

  Future<void> _pickAccount() async {
    final picked = await AccountPicker.showPicked(
      context,
      selectedAccountId: _accountId,
    );
    if (picked == null || !mounted) return;
    setState(() => _accountId = picked.accountId);
  }

  String _errorText(Object error, AppLocalizations l10n) {
    if (error is BeeCountApiException && error.body != null) {
      try {
        final decoded = jsonDecode(error.body!);
        if (decoded is Map && decoded['error'] is String) {
          return decoded['error'] as String;
        }
      } catch (_) {}
    }
    final raw = error.toString();
    if (raw.contains('超过可退')) return l10n.refundExceeds;
    if (raw.contains('大于 0')) return l10n.refundInvalidAmount;
    return raw;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = l10n.refundInvalidAmount);
      return;
    }
    final linkedTotal = widget.alreadyRefunded + amount;
    if (linkedTotal > widget.originalAmount + 0.009) {
      final confirmed = await AppDialog.confirm<bool>(
            context,
            title: _reimburse ? l10n.reimburseOverTitle : l10n.refundOverTitle,
            message:
                _reimburse ? l10n.reimburseOverMessage : l10n.refundOverMessage,
          ) ??
          false;
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(repositoryProvider);
    final reason = _reasonCtrl.text.trim();
    final note = reason.isEmpty ? null : reason;
    try {
      if (_reimburse) {
        if (widget.editing == null) {
          await repo.addReimbursement(
            originalId: widget.originalId,
            amount: amount,
            happenedAt: _happenedAt,
            reason: note,
            accountId: _accountId,
          );
        } else {
          await repo.updateReimbursement(
            id: widget.editing!.id,
            amount: amount,
            happenedAt: _happenedAt,
            reason: note,
            accountId: _accountId,
          );
        }
      } else if (widget.editing == null) {
        await repo.addRefund(
          originalId: widget.originalId,
          amount: amount,
          happenedAt: _happenedAt,
          reason: note,
          accountId: _accountId,
        );
      } else {
        await repo.updateRefund(
          id: widget.editing!.id,
          amount: amount,
          happenedAt: _happenedAt,
          reason: note,
          accountId: _accountId,
        );
      }
      final ledgerId = ref.read(currentLedgerIdProvider);
      PostProcessor.sync(ref, ledgerId: ledgerId);
      ref.invalidate(countsForLedgerProvider(ledgerId));
      ref.read(statsRefreshProvider.notifier).state++;
      if (!mounted) return;
      final saved = widget.editing == null
          ? (_reimburse ? l10n.reimburseSaved : l10n.refundSaved)
          : (_reimburse ? l10n.reimburseUpdated : l10n.refundUpdated);
      showToast(context, saved);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = _errorText(e, l10n));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final editing = widget.editing;
    if (editing == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
          context,
          title: _reimburse ? l10n.reimburseDelete : l10n.refundDelete,
          message: l10n.deleteConfirmMessage,
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).deleteTransaction(editing.id);
      final ledgerId = ref.read(currentLedgerIdProvider);
      PostProcessor.sync(ref, ledgerId: ledgerId);
      ref.invalidate(countsForLedgerProvider(ledgerId));
      ref.read(statsRefreshProvider.notifier).state++;
      if (!mounted) return;
      showToast(
        context,
        _reimburse ? l10n.reimburseDeleted : l10n.refundDeleted,
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, l10n));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final primary = Theme.of(context).colorScheme.primary;
    final accounts = ref.watch(allAccountsStreamProvider).asData?.value ?? [];
    final accountName = _accountId == null
        ? l10n.accountNone
        : accounts
                .where((account) => account.id == _accountId)
                .map((account) => account.name)
                .firstOrNull ??
            l10n.accountNone;
    final fillAmount = _reimburse ? widget.originalAmount : _remaining;
    final hint = _accountId == null
        ? (_reimburse ? l10n.reimburseNoAccount : l10n.refundNoAccount)
        : (_reimburse ? l10n.reimburseHint : l10n.refundHint);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _reimburse ? l10n.reimburseTitle : l10n.refundTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context),
                        ),
                  ),
                ),
                Text(
                  _reimburse
                      ? '${l10n.reimburseOriginalLabel} ${_formatAmount(widget.originalAmount)}'
                      : '${l10n.refundRemainingLabel} ${_formatAmount(_remaining)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: BeeTokens.textSecondary(context),
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: TextStyle(color: BeeTokens.textPrimary(context)),
              decoration: InputDecoration(
                labelText: _reimburse
                    ? l10n.reimburseAmountLabel
                    : l10n.refundAmountLabel,
                isDense: true,
                filled: true,
                fillColor: BeeTokens.surfaceInput(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: TextButton(
                  onPressed: fillAmount <= 0
                      ? null
                      : () {
                          setState(() {
                            _amountCtrl.text = _formatAmount(fillAmount);
                            _amountCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: _amountCtrl.text.length),
                            );
                          });
                        },
                  child: Text(
                    _reimburse ? l10n.reimburseFull : l10n.refundFull,
                  ),
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.refundAccountLabel),
              subtitle: Text(accountName),
              trailing: const Icon(Icons.account_balance_wallet_outlined),
              onTap: _pickAccount,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _reimburse ? l10n.reimburseTime : l10n.refundTime,
              ),
              subtitle: Text(_formatDateTime(_happenedAt)),
              trailing: const Icon(Icons.schedule),
              onTap: _pickDateTime,
            ),
            TextField(
              controller: _reasonCtrl,
              style: TextStyle(color: BeeTokens.textPrimary(context)),
              decoration: InputDecoration(
                labelText: _reimburse
                    ? l10n.reimburseReasonHint
                    : l10n.refundReasonHint,
                isDense: true,
                filled: true,
                fillColor: BeeTokens.surfaceInput(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.editing != null)
                  TextButton(
                    onPressed: _saving ? null : _delete,
                    child: Text(
                      _reimburse ? l10n.reimburseDelete : l10n.refundDelete,
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
