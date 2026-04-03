import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../data/db.dart' as db;
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../account/account_detail_page.dart' show receivableStatsProvider, receivableBalanceProvider;
import '../../providers/statistics_providers.dart' show allAccountStatsProvider, allAccountsTotalStatsProvider;
import 'payment_edit_page.dart';

/// 应收款记录编辑页面
class ReceivableEditPage extends ConsumerStatefulWidget {
  final db.Account account;
  final db.Receivable? receivable;

  const ReceivableEditPage({
    super.key,
    required this.account,
    this.receivable,
  });

  @override
  ConsumerState<ReceivableEditPage> createState() => _ReceivableEditPageState();
}

class _ReceivableEditPageState extends ConsumerState<ReceivableEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _borrowerNameController;
  late final TextEditingController _noteController;
  late double _amount;
  late DateTime _borrowDate;
  DateTime? _receiveDate;
  int? _fromAccountId;
  int? _toAccountId;
  bool _isReceived = false;
  bool _saving = false;

  bool get isEditing => widget.receivable != null;

  @override
  void initState() {
    super.initState();
    final r = widget.receivable;
    _borrowerNameController = TextEditingController(text: r?.borrowerName ?? '');
    _noteController = TextEditingController(text: r?.note ?? '');
    _amount = r?.amount ?? 0;
    _borrowDate = r?.borrowDate ?? DateTime.now();
    _receiveDate = r?.receiveDate;
    _fromAccountId = r?.fromAccountId;
    _toAccountId = r?.toAccountId;
    _isReceived = r?.isReceived ?? false;
  }

  @override
  void dispose() {
    _borrowerNameController.dispose();
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
            title: isEditing ? '编辑应收款' : '新增应收款',
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
                  // 分批付款信息
                  if (isEditing) ...[
                    FutureBuilder<double>(
                      future: _getPaidAmount(),
                      builder: (context, snapshot) {
                        final paidAmount = snapshot.data ?? 0.0;
                        return _buildSectionCard(
                          context,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '已收金额',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: BeeTokens.textSecondary(context),
                                  ),
                                ),
                                Text(
                                  '¥ ${paidAmount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: BeeTokens.textPrimary(context),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12.0.scaled(context, ref)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '待收金额',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: BeeTokens.textSecondary(context),
                                  ),
                                ),
                                Text(
                                  '¥ ${(_amount - paidAmount).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _amount - paidAmount > 0 ? Colors.red : BeeTokens.textPrimary(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: 8.0.scaled(context, ref)),
                    _buildSectionCard(
                      context,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '收款记录',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _addPayment(),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('记录收款'),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12.0.scaled(context, ref),
                                  vertical: 4.0.scaled(context, ref),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8.0.scaled(context, ref)),
                        _buildPaymentList(),
                      ],
                    ),
                    SizedBox(height: 8.0.scaled(context, ref)),
                  ],
                  _buildSectionCard(
                    context,
                    children: [
                      _buildTextField(
                        context,
                        controller: _borrowerNameController,
                        label: '借款人',
                        hint: '请输入借款人名称',
                        icon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入借款人名称';
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
                        label: '借款日期',
                        date: _borrowDate,
                        icon: Icons.calendar_today_outlined,
                        onDateSelected: (date) {
                          setState(() => _borrowDate = date);
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
                            selectedAccountId: _fromAccountId,
                            label: '借款账户',
                            hint: '选择借款时扣款的账户',
                            icon: Icons.account_balance_wallet_outlined,
                            onAccountSelected: (accountId) {
                              setState(() => _fromAccountId = accountId);
                            },
                          ),
                          BeeTokens.cardDivider(context),
                          _buildSwitchField(
                            context,
                            label: '已收款',
                            value: _isReceived,
                            onChanged: (value) {
                              setState(() {
                                _isReceived = value;
                                if (value && _fromAccountId != null) {
                                  _toAccountId = _fromAccountId;
                                }
                              });
                            },
                          ),
                          if (_isReceived) ...[
                            BeeTokens.cardDivider(context),
                            _buildDateField(
                              context,
                              label: '收款日期',
                              date: _receiveDate ?? DateTime.now(),
                              icon: Icons.event_available_outlined,
                              onDateSelected: (date) {
                                setState(() => _receiveDate = date);
                              },
                            ),
                            BeeTokens.cardDivider(context),
                            _buildAccountSelector(
                              context,
                              accounts: otherAccounts,
                              selectedAccountId: _toAccountId,
                              label: '收款账户',
                              hint: '选择收款入账的账户',
                              icon: Icons.account_balance_outlined,
                              onAccountSelected: (accountId) {
                                setState(() => _toAccountId = accountId);
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
            title: const Text('借款金额'),
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
    required Function(int?) onAccountSelected,
  }) {
    final selectedAccount = selectedAccountId != null
        ? accounts.cast<db.Account?>().firstWhere(
              (a) => a?.id == selectedAccountId,
              orElse: () => null,
            )
        : null;

    return InkWell(
      onTap: () async {
        final result = await showModalBottomSheet<int?>(
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
                ListTile(
                  leading: const Icon(Icons.highlight_off),
                  title: const Text('不选账户'),
                  subtitle: Text(
                    '历史账目，不记账',
                    style: TextStyle(
                      fontSize: 12,
                      color: BeeTokens.textTertiary(context),
                    ),
                  ),
                  trailing: selectedAccountId == null
                      ? Icon(Icons.check, color: ref.watch(primaryColorProvider))
                      : null,
                  onTap: () => Navigator.pop(context, null),
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
        onAccountSelected(result);
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
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      if (selectedAccountId == null) ...[
                        SizedBox(width: 8),
                        Text(
                          '(可选)',
                          style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textTertiary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 4.0.scaled(context, ref)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedAccount?.name ?? (selectedAccountId == null ? '不选账户' : hint),
                          style: TextStyle(
                            fontSize: 16,
                            color: selectedAccount != null
                                ? BeeTokens.textPrimary(context)
                                : (selectedAccountId == null
                                    ? BeeTokens.textSecondary(context)
                                    : BeeTokens.textTertiary(context)),
                          ),
                        ),
                      ),
                      if (selectedAccountId != null) ...[
                        SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            onAccountSelected(null);
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (selectedAccountId == null)
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

    if (_fromAccountId == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认不选择借款账户'),
          content: const Text('您没有选择借款账户，这将不会从任何账户扣款。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (_isReceived && _toAccountId == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认不选择收款账户'),
          content: const Text('您没有选择收款账户，这将不会向任何账户入账。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _saving = true);

    try {
      final repo = ref.read(repositoryProvider);
      final currentLedger = await ref.read(currentLedgerProvider.future);
      final now = DateTime.now();

      if (isEditing) {
        await repo.updateReceivable(
          id: widget.receivable!.id,
          borrowerName: _borrowerNameController.text.trim(),
          amount: _amount,
          borrowDate: _borrowDate,
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          fromAccountId: _fromAccountId,
          isReceived: _isReceived,
          receiveDate: _isReceived ? _receiveDate : null,
          toAccountId: _isReceived ? _toAccountId : null,
          updatedAt: now,
        );

        if (currentLedger != null) {
          final borrowerName = _borrowerNameController.text.trim();
          final note = _noteController.text.trim();

          if (_fromAccountId != null) {
            final expenseNote = note.isNotEmpty 
                ? '借给$borrowerName: $note' 
                : '借给$borrowerName';
            final expenseTransactions = await repo.getTransactionsByNote(
              notePattern: '借给$borrowerName',
            );
            
            if (expenseTransactions.isNotEmpty) {
              await repo.updateTransaction(
                id: expenseTransactions.first.id,
                type: 'expense',
                amount: _amount,
                accountId: _fromAccountId!,
                happenedAt: _borrowDate,
                note: expenseNote,
              );
            } else {
              await repo.addTransaction(
                ledgerId: currentLedger.id,
                type: 'expense',
                amount: _amount,
                accountId: _fromAccountId!,
                happenedAt: _borrowDate,
                note: expenseNote,
              );
            }
          }

          if (_isReceived && _toAccountId != null) {
            final incomeNote = note.isNotEmpty 
                ? '收$borrowerName款: $note' 
                : '收$borrowerName款';
            final incomeTransactions = await repo.getTransactionsByNote(
              notePattern: '收$borrowerName款',
            );
            
            if (incomeTransactions.isNotEmpty) {
              await repo.updateTransaction(
                id: incomeTransactions.first.id,
                type: 'income',
                amount: _amount,
                accountId: _toAccountId!,
                happenedAt: _receiveDate ?? DateTime.now(),
                note: incomeNote,
              );
            } else {
              await repo.addTransaction(
                ledgerId: currentLedger.id,
                type: 'income',
                amount: _amount,
                accountId: _toAccountId!,
                happenedAt: _receiveDate ?? DateTime.now(),
                note: incomeNote,
              );
            }
          }
        }
      } else {
        await repo.createReceivable(
          accountId: widget.account.id,
          borrowerName: _borrowerNameController.text.trim(),
          amount: _amount,
          borrowDate: _borrowDate,
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          fromAccountId: _fromAccountId,
          isReceived: _isReceived,
          receiveDate: _isReceived ? _receiveDate : null,
          toAccountId: _isReceived ? _toAccountId : null,
        );
        
        // 如果选择了借款账户，创建支出交易记录
        if (_fromAccountId != null && currentLedger != null) {
          await repo.addTransaction(
            ledgerId: currentLedger.id,
            type: 'expense',
            amount: _amount,
            accountId: _fromAccountId!,
            happenedAt: _borrowDate,
            note: _noteController.text.trim().isNotEmpty 
                ? '借给${_borrowerNameController.text.trim()}: ${_noteController.text.trim()}' 
                : '借给${_borrowerNameController.text.trim()}',
          );
        }
        
        // 如果已收款且选择了收款账户，创建收入交易记录
        if (_isReceived && _toAccountId != null && currentLedger != null) {
          await repo.addTransaction(
            ledgerId: currentLedger.id,
            type: 'income',
            amount: _amount,
            accountId: _toAccountId!,
            happenedAt: _receiveDate ?? DateTime.now(),
            note: _noteController.text.trim().isNotEmpty 
                ? '收${_borrowerNameController.text.trim()}款: ${_noteController.text.trim()}' 
                : '收${_borrowerNameController.text.trim()}款',
          );
        }
      }

      ref.invalidate(receivableStatsProvider(widget.account.id));
      ref.invalidate(receivableBalanceProvider(widget.account.id));
      ref.invalidate(allAccountStatsProvider);
      ref.invalidate(allAccountsTotalStatsProvider);

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
        content: const Text('确定要删除这条应收款记录吗？'),
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
      await repo.deleteReceivable(widget.receivable!.id);

      ref.invalidate(receivableStatsProvider(widget.account.id));
      ref.invalidate(receivableBalanceProvider(widget.account.id));

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

  Future<double> _getPaidAmount() async {
    if (widget.receivable == null) return 0.0;
    final repo = ref.read(repositoryProvider);
    return await repo.getReceivablePaidAmount(widget.receivable!.id);
  }

  Widget _buildPaymentList() {
    if (widget.receivable == null) {
      return const Center(
        child: Text('暂无收款记录'),
      );
    }

    final paymentsAsync = ref.watch(receivablePaymentsProvider(widget.receivable!.id));
    return paymentsAsync.when(
      data: (payments) {
        if (payments.isEmpty) {
          return const Center(
            child: Text('暂无收款记录'),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: payments.length,
          itemBuilder: (context, index) {
            final payment = payments[index];
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 4.0.scaled(context, ref)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${payment.paymentDate.year}-${payment.paymentDate.month.toString().padLeft(2, '0')}-${payment.paymentDate.day.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 14,
                            color: BeeTokens.textSecondary(context),
                          ),
                        ),
                        if (payment.note != null && payment.note!.isNotEmpty) ...[
                          SizedBox(height: 4.0.scaled(context, ref)),
                          Text(
                            payment.note!,
                            style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '¥ ${payment.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                  SizedBox(width: 8.0.scaled(context, ref)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editPayment(payment),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                        onPressed: () => _deletePayment(payment),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('加载收款记录失败: $err')),
    );
  }

  void _editPayment(db.ReceivablePayment payment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentEditPage(
          account: widget.account,
          receivable: widget.receivable!,
          existingPayment: payment,
        ),
      ),
    );
  }

  Future<void> _deletePayment(db.ReceivablePayment payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条收款记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final repo = ref.read(repositoryProvider);
        await repo.deleteReceivablePayment(payment.id);
        // 刷新统计数据
        ref.invalidate(receivableStatsProvider(widget.account.id));
        ref.invalidate(receivableBalanceProvider(widget.account.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  void _addPayment() {
    if (widget.receivable == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentEditPage(
          account: widget.account,
          receivable: widget.receivable!,
        ),
      ),
    );
  }
}
