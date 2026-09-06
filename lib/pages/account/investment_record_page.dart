import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/invest_tx.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/ui/ui.dart';

enum InvestmentRecordKind { markToMarket, manual, dividend, edit }

class InvestmentRecordPage extends ConsumerStatefulWidget {
  final db.Account account;
  final InvestmentRecordKind kind;
  final db.Transaction? editing;

  const InvestmentRecordPage({
    super.key,
    required this.account,
    required this.kind,
    this.editing,
  });

  @override
  ConsumerState<InvestmentRecordPage> createState() =>
      _InvestmentRecordPageState();
}

class _InvestmentRecordPageState extends ConsumerState<InvestmentRecordPage> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late DateTime _date;
  late bool _isGain;
  bool _saving = false;
  double? _asOfBalance;

  bool get isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.editing;
    _date = tx?.happenedAt ?? DateTime.now();
    _noteController = TextEditingController(text: tx?.note ?? '');
    _isGain = tx == null || tx.type != InvestTx.loss;
    final initialAmount = widget.kind == InvestmentRecordKind.markToMarket
        ? null
        : tx?.amount;
    _amountController = TextEditingController(
      text: initialAmount == null ? '' : initialAmount.toStringAsFixed(2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAsOf());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  DateTime get _endExclusive =>
      DateTime(_date.year, _date.month, _date.day).add(const Duration(days: 1));

  Future<void> _refreshAsOf() async {
    if (widget.kind != InvestmentRecordKind.markToMarket &&
        widget.kind != InvestmentRecordKind.edit) {
      return;
    }
    if (widget.kind == InvestmentRecordKind.edit &&
        widget.editing?.investEvent != InvestTx.eventMarkToMarket) {
      return;
    }
    final repo = ref.read(repositoryProvider);
    final value = await repo.getAccountBalanceAsOf(
      widget.account.id,
      _endExclusive,
      excludeTxId: widget.editing?.id,
    );
    if (mounted) setState(() => _asOfBalance = value);
  }

  String _title(AppLocalizations l10n) {
    if (isEditing) return l10n.investEditTitle;
    switch (widget.kind) {
      case InvestmentRecordKind.markToMarket:
        return l10n.investMarkToMarket;
      case InvestmentRecordKind.manual:
        return l10n.investRecordPnl;
      case InvestmentRecordKind.dividend:
        return l10n.investDividend;
      case InvestmentRecordKind.edit:
        return l10n.investEditTitle;
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final raw = double.tryParse(_amountController.text.trim());
    if (raw == null || raw < 0) return;

    final repo = ref.read(repositoryProvider);

    setState(() => _saving = true);
    try {
      if (widget.kind == InvestmentRecordKind.markToMarket ||
          (widget.kind == InvestmentRecordKind.edit &&
              widget.editing?.investEvent == InvestTx.eventMarkToMarket)) {
        final asOf = _asOfBalance ??
            await repo.getAccountBalanceAsOf(
              widget.account.id,
              _endExclusive,
              excludeTxId: widget.editing?.id,
            );
        final delta = raw - asOf;
        if (delta.abs() < 0.0001) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.investNoDelta)));
          }
          return;
        }
        final type = delta > 0 ? InvestTx.gain : InvestTx.loss;
        final amount = delta.abs();
        final note = _noteController.text.trim().isEmpty
            ? '${l10n.investEventMark} ${raw.toStringAsFixed(2)}'
            : _noteController.text.trim();
        await _upsert(
          type: type,
          amount: amount,
          note: note,
          investEvent: InvestTx.eventMarkToMarket,
        );
      } else if (widget.kind == InvestmentRecordKind.dividend ||
          widget.editing?.investEvent == InvestTx.eventDividend) {
        if (raw == 0) return;
        await _upsert(
          type: InvestTx.gain,
          amount: raw,
          note: _noteController.text.trim().isEmpty
              ? l10n.investDividend
              : _noteController.text.trim(),
          investEvent: InvestTx.eventDividend,
        );
      } else {
        if (raw == 0) return;
        await _upsert(
          type: _isGain ? InvestTx.gain : InvestTx.loss,
          amount: raw,
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          investEvent: InvestTx.eventManual,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upsert({
    required String type,
    required double amount,
    String? note,
    required String investEvent,
  }) async {
    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);
    final happenedAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      DateTime.now().hour,
      DateTime.now().minute,
    );
    if (widget.editing != null) {
      await repo.updateTransaction(
        id: widget.editing!.id,
        type: type,
        amount: amount,
        note: note,
        happenedAt: happenedAt,
        accountId: widget.account.id,
        investEvent: investEvent,
      );
    } else {
      await repo.addTransaction(
        ledgerId: ledgerId,
        type: type,
        amount: amount,
        accountId: widget.account.id,
        happenedAt: happenedAt,
        note: note,
        investEvent: investEvent,
      );
    }
    ref.read(statsRefreshProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = ref.watch(primaryColorProvider);
    final showMark = widget.kind == InvestmentRecordKind.markToMarket ||
        widget.editing?.investEvent == InvestTx.eventMarkToMarket;
    final showManual = widget.kind == InvestmentRecordKind.manual ||
        (widget.kind == InvestmentRecordKind.edit &&
            widget.editing?.investEvent == InvestTx.eventManual);
    final amountLabel = showMark
        ? l10n.investMarketValue
        : (widget.kind == InvestmentRecordKind.dividend ||
                widget.editing?.investEvent == InvestTx.eventDividend)
            ? l10n.investDividend
            : l10n.investPnlAmountHint;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(title: _title(l10n), showBack: true),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              children: [
                AppListTile(
                  leading: Icons.event,
                  title: l10n.importFieldDate,
                  subtitle:
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                  onTap: () async {
                    final picked = await showWheelDatePicker(
                      context,
                      initial: _date,
                    );
                    if (picked != null) {
                      setState(() => _date = picked);
                      await _refreshAsOf();
                    }
                  },
                ),
                if (showMark && _asOfBalance != null) ...[
                  SizedBox(height: 8.0.scaled(context, ref)),
                  Text(
                    '${l10n.investMarketValue}: ${_asOfBalance!.toStringAsFixed(2)}',
                    style: TextStyle(color: BeeTokens.textSecondary(context)),
                  ),
                ],
                SizedBox(height: 12.0.scaled(context, ref)),
                TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: amountLabel,
                    hintText: showMark
                        ? l10n.investMarketValueHint
                        : widget.kind == InvestmentRecordKind.dividend
                            ? l10n.investDividendHint
                            : l10n.investPnlAmountHint,
                  ),
                ),
                if (showManual) ...[
                  SizedBox(height: 12.0.scaled(context, ref)),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: true, label: Text(l10n.investGain)),
                      ButtonSegment(
                          value: false, label: Text(l10n.investLoss)),
                    ],
                    selected: {_isGain},
                    onSelectionChanged: (s) =>
                        setState(() => _isGain = s.first),
                  ),
                ],
                SizedBox(height: 12.0.scaled(context, ref)),
                TextField(
                  controller: _noteController,
                  decoration: InputDecoration(labelText: l10n.importFieldNote),
                ),
                SizedBox(height: 24.0.scaled(context, ref)),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(l10n.commonSave),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
