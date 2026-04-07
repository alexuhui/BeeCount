import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db.dart' as db;
import '../../providers.dart';
import '../../providers/theme_providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/account_picker.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';

class PaymentAddDialog extends ConsumerStatefulWidget {
  final int? receivableId;
  final int? payableId;
  final double initialAmount;

  const PaymentAddDialog({
    super.key,
    this.receivableId,
    this.payableId,
    required this.initialAmount,
  }) : assert(receivableId != null || payableId != null);

  @override
  ConsumerState<PaymentAddDialog> createState() => _PaymentAddDialogState();
}

class _PaymentAddDialogState extends ConsumerState<PaymentAddDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _interestController;
  late final TextEditingController _noteController;
  DateTime _happenedAt = DateTime.now();
  db.Account? _selectedAccount;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.initialAmount.toStringAsFixed(2));
    _interestController = TextEditingController(text: '0.00');
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _interestController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _happenedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _happenedAt = picked);
    }
  }

  Future<void> _selectAccount() async {
    final accountId = await AccountPicker.show(context);
    if (accountId != null) {
      final repo = ref.read(repositoryProvider);
      final account = await repo.getAccount(accountId);
      if (account != null) {
        setState(() => _selectedAccount = account);
      }
    }
  }

  void _submit() async {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final interest = double.tryParse(_interestController.text) ?? 0.0;
    final note = _noteController.text.trim();

    if (amount <= 0 && interest <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的金额或利息')),
      );
      return;
    }

    if (_selectedAccount == null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text('未选择账户，该笔记录将不会影响账户余额，仅做记录。是否继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final repo = ref.read(repositoryProvider);
    try {
      if (widget.receivableId != null) {
        await repo.addReceivablePayment(
          receivableId: widget.receivableId!,
          amount: amount,
          interestAmount: interest,
          happenedAt: _happenedAt,
          accountId: _selectedAccount?.id,
          note: note.isEmpty ? null : note,
        );
      } else {
        await repo.addPayablePayment(
          payableId: widget.payableId!,
          amount: amount,
          interestAmount: interest,
          happenedAt: _happenedAt,
          accountId: _selectedAccount?.id,
          note: note.isEmpty ? null : note,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记录成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记录失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = ref.watch(primaryColorProvider);
    final isReceivable = widget.receivableId != null;

    return AlertDialog(
      title: Text(isReceivable ? '记录收款' : '记录还款'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: '本金金额', prefixText: '¥'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: _interestController,
              decoration: const InputDecoration(labelText: '利息金额', prefixText: '¥'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('发生日期'),
              subtitle: Text('${_happenedAt.year}-${_happenedAt.month}-${_happenedAt.day}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('账户'),
              subtitle: Text(_selectedAccount?.name ?? '不入账 (仅记录)'),
              trailing: const Icon(Icons.account_balance_wallet),
              onTap: _selectAccount,
            ),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: '备注 (可选)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
          child: const Text('提交'),
        ),
      ],
    );
  }
}

Future<bool?> showPaymentAddDialog({
  required BuildContext context,
  int? receivableId,
  int? payableId,
  required double initialAmount,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => PaymentAddDialog(
      receivableId: receivableId,
      payableId: payableId,
      initialAmount: initialAmount,
    ),
  );
}
