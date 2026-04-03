import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ui/ui.dart';
import '../../utils/transaction_edit_utils.dart';
import '../account/account_detail_page.dart' show receivableStatsProvider, receivableBalanceProvider, payableStatsProvider, payableBalanceProvider;


class PaymentEditPage extends ConsumerStatefulWidget {
  final db.Account account;
  final db.Receivable? receivable;
  final db.Payable? payable;
  final db.ReceivablePayment? existingPayment;
  final db.PayablePayment? existingPayablePayment;

  const PaymentEditPage({
    super.key,
    required this.account,
    this.receivable,
    this.payable,
    this.existingPayment,
    this.existingPayablePayment,
  });

  @override
  ConsumerState<PaymentEditPage> createState() => _PaymentEditPageState();
}

class _PaymentEditPageState extends ConsumerState<PaymentEditPage> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _paymentDate = DateTime.now();
  db.Account? _selectedAccount;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.existingPayment != null) {
      // 编辑应收款付款记录
      final payment = widget.existingPayment!;
      _amountController.text = payment.amount.toString();
      _noteController.text = payment.note ?? '';
      _paymentDate = payment.paymentDate;
      if (payment.accountId != null) {
        _selectedAccount = ref.read(accountByIdProvider(payment.accountId!)).value;
      }
    } else if (widget.existingPayablePayment != null) {
      // 编辑应付款付款记录
      final payment = widget.existingPayablePayment!;
      _amountController.text = payment.amount.toString();
      _noteController.text = payment.note ?? '';
      _paymentDate = payment.paymentDate;
      if (payment.accountId != null) {
        _selectedAccount = ref.read(accountByIdProvider(payment.accountId!)).value;
      }
    } else {
      // 新建付款记录，默认选择关联账户
      _selectedAccount = widget.account;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _selectAccount() async {
    final repo = ref.read(repositoryProvider);
    final allAccounts = await repo.getAllAccounts();
    
    // 过滤掉应收/应付类型的账户
    final validAccounts = allAccounts.where((a) => 
      a.type != 'receivable' && a.type != 'payable'
    ).toList();
    
    if (validAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的账户')),
      );
      return;
    }
    
    // 显示账户选择对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择账户'),
        content: SingleChildScrollView(
          child: Column(
            children: validAccounts.map((account) {
              return ListTile(
                title: Text(account.name),
                subtitle: Text('${account.type} · ${account.currency}'),
                onTap: () {
                  Navigator.of(context).pop(account);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    ).then((result) {
      if (result != null && result is db.Account) {
        setState(() {
          _selectedAccount = result;
        });
      }
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    
    if (picked != null) {
      setState(() {
        _paymentDate = picked;
      });
    }
  }

  Future<void> _savePayment() async {
    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入付款金额')),
      );
      return;
    }

    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的付款金额')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final repo = ref.read(repositoryProvider);
      final currentLedger = await ref.read(currentLedgerProvider.future);
      
      if (widget.receivable != null) {
        // 应收款付款
        if (widget.existingPayment != null) {
          // 更新现有付款记录
          await repo.updateReceivablePayment(
            id: widget.existingPayment!.id,
            amount: amount,
            paymentDate: _paymentDate,
            accountId: _selectedAccount?.id,
            note: _noteController.text.trim(),
          );
        } else {
          // 创建新付款记录
          await repo.createReceivablePayment(
            receivableId: widget.receivable!.id,
            amount: amount,
            paymentDate: _paymentDate,
            accountId: _selectedAccount?.id,
            note: _noteController.text.trim(),
          );
        }
        
        // 如果选择了账户，创建收款交易记录
        if (_selectedAccount != null && currentLedger != null) {
          await repo.addTransaction(
            ledgerId: currentLedger.id,
            type: 'income',
            amount: amount,
            accountId: _selectedAccount!.id,
            happenedAt: _paymentDate,
            note: _noteController.text.trim().isNotEmpty 
                ? '收${widget.receivable!.borrowerName}款: ${_noteController.text.trim()}' 
                : '收${widget.receivable!.borrowerName}款',
          );
        }
        
        // 刷新应收款统计数据
        ref.invalidate(receivableStatsProvider(widget.account.id));
        ref.invalidate(receivableBalanceProvider(widget.account.id));
      } else if (widget.payable != null) {
        // 应付款付款
        if (widget.existingPayablePayment != null) {
          // 更新现有付款记录
          await repo.updatePayablePayment(
            id: widget.existingPayablePayment!.id,
            amount: amount,
            paymentDate: _paymentDate,
            accountId: _selectedAccount?.id,
            note: _noteController.text.trim(),
          );
        } else {
          // 创建新付款记录
          await repo.createPayablePayment(
            payableId: widget.payable!.id,
            amount: amount,
            paymentDate: _paymentDate,
            accountId: _selectedAccount?.id,
            note: _noteController.text.trim(),
          );
        }
        
        // 如果选择了账户，创建付款交易记录
        if (_selectedAccount != null && currentLedger != null) {
          await repo.addTransaction(
            ledgerId: currentLedger.id,
            type: 'expense',
            amount: amount,
            accountId: _selectedAccount!.id,
            happenedAt: _paymentDate,
            note: _noteController.text.trim().isNotEmpty 
                ? '付${widget.payable!.payeeName}款: ${_noteController.text.trim()}' 
                : '付${widget.payable!.payeeName}款',
          );
        }
        
        // 刷新应付款统计数据
        ref.invalidate(payableStatsProvider(widget.account.id));
        ref.invalidate(payableBalanceProvider(widget.account.id));
      }

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReceivable = widget.receivable != null;
    final title = isReceivable ? '记录收款' : '记录付款';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _savePayment,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 金额输入
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '金额',
                prefixText: '¥ ',
              ),
            ),
            const SizedBox(height: 16),

            // 日期选择
            InkWell(
              onTap: _selectDate,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('日期'),
                    Text(
                      '${_paymentDate.year}-${_paymentDate.month.toString().padLeft(2, '0')}-${_paymentDate.day.toString().padLeft(2, '0')}',
                      style: TextStyle(color: BeeTokens.textSecondary(context)),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),

            // 账户选择（可选）
            InkWell(
              onTap: _selectAccount,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('账户（可选）'),
                        if (_selectedAccount == null) ...[
                          SizedBox(width: 8),
                          Text(
                            '(历史账目，不记账)',
                            style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        if (_selectedAccount != null) ...[
                          Text(
                            _selectedAccount!.name,
                            style: TextStyle(color: BeeTokens.textSecondary(context)),
                          ),
                          SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _selectedAccount = null;
                              });
                            },
                          ),
                        ] else ...[
                          Icon(Icons.add_circle_outline, color: BeeTokens.textTertiary(context)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),

            // 备注
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: '备注',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
