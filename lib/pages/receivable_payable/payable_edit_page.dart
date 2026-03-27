import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../data/db.dart' as db;
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';

/// 应付款记录编辑页面
class PayableEditPage extends ConsumerStatefulWidget {
  final db.Account account;
  final db.Payable? payable;

  const PayableEditPage({
    super.key,
    required this.account,
    this.payable,
  });

  @override
  ConsumerState<PayableEditPage> createState() => _PayableEditPageState();
}

class _PayableEditPageState extends ConsumerState<PayableEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _payeeNameController;
  late final TextEditingController _noteController;
  late double _amount;
  late DateTime _payDate;
  DateTime? _paidDate;
  int? _toAccountId;
  int? _fromAccountId;
  bool _isPaid = false;
  bool _saving = false;

  bool get isEditing => widget.payable != null;

  @override
  void initState() {
    super.initState();
    final p = widget.payable;
    _payeeNameController = TextEditingController(text: p?.payeeName ?? '');
    _noteController = TextEditingController(text: p?.note ?? '');
    _amount = p?.amount ?? 0;
    _payDate = p?.payDate ?? DateTime.now();
    _paidDate = p?.paidDate;
    _toAccountId = p?.toAccountId;
    _fromAccountId = p?.fromAccountId;
    _isPaid = p?.isPaid ?? false;
  }

  @override
  void dispose() {
    _payeeNameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: isEditing ? '编辑应付款' : '新增应付款',
            showBack: true,
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.0.scaled(context, ref),
                  vertical: 8.0.scaled(context, ref),
                ),
                children: [
                  _buildSectionCard(
                    context,
                    children: [
                      _buildTextField(
                        context,
                        controller: _payeeNameController,
                        label: '收款人',
                        hint: '请输入收款人名称',
                        icon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入收款人名称';
                          }
                          return null;
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      _buildAmountField(context, currencyCode),
                    ],
                  ),
                  SizedBox(height: 8.0.scaled(context, ref)),
                  _buildSectionCard(
                    context,
                    children: [
                      _buildDateField(
                        context,
                        label: '日期',
                        date: _payDate,
                        icon: Icons.calendar_today_outlined,
                        onDateSelected: (date) {
                          setState(() => _payDate = date);
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      _buildTextField(
                        context,
                        controller: _noteController,
                        label: '备注',
                        hint: '请输入备注（可选）',
                        icon: Icons.note_outlined,
                        required: false,
                      ),
                    ],
                  ),
                  SizedBox(height: 8.0.scaled(context, ref)),
                  accountsAsync.when(
                    data: (accounts) {
                      final otherAccounts = accounts.where((a) => 
                        a.id != widget.account.id && 
                        a.type != 'receivable' && 
                        a.type != 'payable'
                      ).toList();
                      return _buildSectionCard(
                        context,
                        children: [
                          _buildAccountSelector(
                            context,
                            accounts: otherAccounts,
                            selectedAccountId: _toAccountId,
                            label: '入账账户',
                            hint: '选择钱转入的账户',
                            icon: Icons.account_balance_outlined,
                            onAccountSelected: (accountId) {
                              setState(() => _toAccountId = accountId);
                            },
                          ),
                          BeeTokens.cardDivider(context),
                          _buildSwitchField(
                            context,
                            label: '已还款',
                            value: _isPaid,
                            onChanged: (value) {
                              setState(() => _isPaid = value);
                            },
                          ),
                          if (_isPaid) ...[
                            BeeTokens.cardDivider(context),
                            _buildDateField(
                              context,
                              label: '还款日期',
                              date: _paidDate ?? DateTime.now(),
                              icon: Icons.event_available_outlined,
                              onDateSelected: (date) {
                                setState(() => _paidDate = date);
                              },
                            ),
                            BeeTokens.cardDivider(context),
                            _buildAccountSelector(
                              context,
                              accounts: otherAccounts,
                              selectedAccountId: _fromAccountId,
                              label: '还款账户',
                              hint: '选择还款的账户',
                              icon: Icons.account_balance_wallet_outlined,
                              onAccountSelected: (accountId) {
                                setState(() => _fromAccountId = accountId);
                              },
                            ),
                          ],
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, stack) => Center(child: Text('加载账户失败: $err')),
                  ),
                  SizedBox(height: 24.0.scaled(context, ref)),
                  _buildSaveButton(context, primaryColor, l10n),
                  if (isEditing) ...[
                    SizedBox(height: 12.0.scaled(context, ref)),
                    _buildDeleteButton(context, l10n),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, {required List<Widget> children}) {
    return SectionCard(
      margin: EdgeInsets.zero,
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = true,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: EdgeInsets.all(16.0.scaled(context, ref)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: BeeTokens.textSecondary(context)),
          SizedBox(width: 12.0.scaled(context, ref)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
                SizedBox(height: 4.0.scaled(context, ref)),
                TextFormField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 16),
                  validator: validator,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountField(BuildContext context, String currencyCode) {
    final controller = TextEditingController(text: _amount > 0 ? _amount.toString() : '');
    return InkWell(
      onTap: () async {
        final result = await showDialog<double>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('金额'),
            content: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                hintText: '请输入金额',
                suffixText: currencyCode,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final value = double.tryParse(controller.text);
                  Navigator.pop(context, value);
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
        if (result != null && result > 0) {
          setState(() => _amount = result);
        }
      },
      child: Padding(
        padding: EdgeInsets.all(16.0.scaled(context, ref)),
        child: Row(
          children: [
            Icon(Icons.attach_money, size: 20, color: BeeTokens.textSecondary(context)),
            SizedBox(width: 12.0.scaled(context, ref)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '金额',
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  SizedBox(height: 4.0.scaled(context, ref)),
                  Text(
                    _amount > 0 ? '¥ ${_amount.toStringAsFixed(2)}' : '请输入金额',
                    style: TextStyle(
                      fontSize: 16,
                      color: _amount > 0
                          ? BeeTokens.textPrimary(context)
                          : BeeTokens.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: BeeTokens.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(
    BuildContext context, {
    required String label,
    required DateTime date,
    required IconData icon,
    required Function(DateTime) onDateSelected,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          onDateSelected(picked);
        }
      },
      child: Padding(
        padding: EdgeInsets.all(16.0.scaled(context, ref)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: BeeTokens.textSecondary(context)),
            SizedBox(width: 12.0.scaled(context, ref)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  SizedBox(height: 4.0.scaled(context, ref)),
                  Text(
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 16,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: BeeTokens.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSelector(
    BuildContext context, {
    required List<db.Account> accounts,
    required int? selectedAccountId,
    required String label,
    required String hint,
    required IconData icon,
    required Function(int) onAccountSelected,
  }) {
    final selectedAccount = selectedAccountId != null
        ? accounts.cast<db.Account?>().firstWhere(
              (a) => a?.id == selectedAccountId,
              orElse: () => null,
            )
        : null;

    return InkWell(
      onTap: () async {
        final result = await showModalBottomSheet<int>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      final isSelected = account.id == selectedAccountId;
                      return ListTile(
                        leading: Icon(
                          Icons.account_balance_wallet,
                          color: isSelected ? ref.watch(primaryColorProvider) : null,
                        ),
                        title: Text(account.name),
                        trailing: isSelected
                            ? Icon(Icons.check, color: ref.watch(primaryColorProvider))
                            : null,
                        onTap: () => Navigator.pop(context, account.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
        if (result != null) {
          onAccountSelected(result);
        }
      },
      child: Padding(
        padding: EdgeInsets.all(16.0.scaled(context, ref)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: BeeTokens.textSecondary(context)),
            SizedBox(width: 12.0.scaled(context, ref)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textSecondary(context),
                    ),
                  ),
                  SizedBox(height: 4.0.scaled(context, ref)),
                  Text(
                    selectedAccount?.name ?? hint,
                    style: TextStyle(
                      fontSize: 16,
                      color: selectedAccount != null
                          ? BeeTokens.textPrimary(context)
                          : BeeTokens.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: BeeTokens.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchField(
    BuildContext context, {
    required String label,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.all(16.0.scaled(context, ref)),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: BeeTokens.textSecondary(context)),
          SizedBox(width: 12.0.scaled(context, ref)),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: ref.watch(primaryColorProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context, Color primaryColor, AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 48.0.scaled(context, ref),
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[400],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
          ),
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                l10n.commonSave,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context, AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 48.0.scaled(context, ref),
      child: OutlinedButton(
        onPressed: _saving ? null : _delete,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0.scaled(context, ref)),
          ),
        ),
        child: Text(
          l10n.commonDelete,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_amount <= 0) {
      showToast(context, '请输入有效金额');
      return;
    }
    if (_toAccountId == null) {
      showToast(context, '请选择入账账户');
      return;
    }
    if (_isPaid && _fromAccountId == null) {
      showToast(context, '请选择还款账户');
      return;
    }

    setState(() => _saving = true);

    try {
      final repo = ref.read(repositoryProvider);
      final now = DateTime.now();

      if (isEditing) {
        await repo.updatePayable(
          id: widget.payable!.id,
          payeeName: _payeeNameController.text.trim(),
          amount: _amount,
          payDate: _payDate,
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          toAccountId: _toAccountId!,
          isPaid: _isPaid,
          paidDate: _isPaid ? _paidDate : null,
          fromAccountId: _isPaid ? _fromAccountId : null,
          updatedAt: now,
        );
      } else {
        await repo.createPayable(
          accountId: widget.account.id,
          payeeName: _payeeNameController.text.trim(),
          amount: _amount,
          payDate: _payDate,
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          toAccountId: _toAccountId!,
          isPaid: _isPaid,
          paidDate: _isPaid ? _paidDate : null,
          fromAccountId: _isPaid ? _fromAccountId : null,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条应付款记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _saving = true);

    try {
      final repo = ref.read(repositoryProvider);
      await repo.deletePayable(widget.payable!.id);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '删除失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
