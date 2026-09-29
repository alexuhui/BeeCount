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
import '../ui/ui.dart';

/// 记一笔退款，或修改已有退款。成功时返回 true。
Future<bool?> showRefundSheet({
  required BuildContext context,
  required int originalId,
  required double originalAmount,
  required double alreadyRefunded,
  bool creditsAccount = true,
  Transaction? editing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BeeTokens.surfaceSheet(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => RefundSheet(
      originalId: originalId,
      originalAmount: originalAmount,
      alreadyRefunded: alreadyRefunded,
      creditsAccount: creditsAccount,
      editing: editing,
    ),
  );
}

class RefundSheet extends ConsumerStatefulWidget {
  final int originalId;
  final double originalAmount;
  final double alreadyRefunded;
  final bool creditsAccount;
  final Transaction? editing;

  const RefundSheet({
    super.key,
    required this.originalId,
    required this.originalAmount,
    required this.alreadyRefunded,
    required this.creditsAccount,
    this.editing,
  });

  @override
  ConsumerState<RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<RefundSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _reasonCtrl;
  late DateTime _happenedAt;
  bool _saving = false;
  String? _error;

  double get _remaining => RefundTx.remaining(
        original: widget.originalAmount,
        refunded: widget.alreadyRefunded,
      );

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final initial = editing == null
        ? _remaining
        : RefundTx.roundMoney(editing.amount);
    _amountCtrl = TextEditingController(text: _formatAmount(initial));
    _reasonCtrl = TextEditingController(text: editing?.note ?? '');
    _happenedAt = editing?.happenedAt.toLocal() ?? DateTime.now();
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
    if (amount > _remaining + 0.009) {
      setState(() => _error = l10n.refundExceeds);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(repositoryProvider);
    final reason = _reasonCtrl.text.trim();
    try {
      if (widget.editing == null) {
        await repo.addRefund(
          originalId: widget.originalId,
          amount: amount,
          happenedAt: _happenedAt,
          reason: reason.isEmpty ? null : reason,
        );
      } else {
        await repo.updateRefund(
          id: widget.editing!.id,
          amount: amount,
          happenedAt: _happenedAt,
          reason: reason.isEmpty ? null : reason,
        );
      }
      final ledgerId = ref.read(currentLedgerIdProvider);
      PostProcessor.sync(ref, ledgerId: ledgerId);
      ref.invalidate(countsForLedgerProvider(ledgerId));
      ref.read(statsRefreshProvider.notifier).state++;
      if (!mounted) return;
      showToast(
        context,
        widget.editing == null ? l10n.refundSaved : l10n.refundUpdated,
      );
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
          title: l10n.refundDelete,
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
      showToast(context, l10n.refundDeleted);
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
                    l10n.refundTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context),
                        ),
                  ),
                ),
                Text(
                  '${l10n.refundRemainingLabel} ${_formatAmount(_remaining)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.creditsAccount ? l10n.refundHint : l10n.refundNoAccount,
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
                labelText: l10n.refundAmountLabel,
                isDense: true,
                filled: true,
                fillColor: BeeTokens.surfaceInput(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: TextButton(
                  onPressed: _remaining <= 0
                      ? null
                      : () {
                          setState(() {
                            _amountCtrl.text = _formatAmount(_remaining);
                            _amountCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: _amountCtrl.text.length),
                            );
                          });
                        },
                  child: Text(l10n.refundFull),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.refundTime),
              subtitle: Text(_formatDateTime(_happenedAt)),
              trailing: const Icon(Icons.schedule),
              onTap: _pickDateTime,
            ),
            TextField(
              controller: _reasonCtrl,
              style: TextStyle(color: BeeTokens.textPrimary(context)),
              decoration: InputDecoration(
                labelText: l10n.refundReasonHint,
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
                    child: Text(l10n.refundDelete),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving || _remaining <= 0 ? null : _submit,
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
