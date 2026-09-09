import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db.dart' as db;
import '../../providers.dart';
import '../../providers/theme_providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/section_card.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../account/account_detail_page.dart' show payablePaymentsProvider, accountByIdProvider, allAccountStatsProvider, allAccountsTotalStatsProvider;
import 'payable_edit_page.dart';
import 'payment_add_dialog.dart';

class PayableRecordDetailPage extends ConsumerWidget {
  final db.Payable payable;
  final String currencyCode;

  const PayableRecordDetailPage({
    super.key,
    required this.payable,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(payablePaymentsProvider(payable.id));
    final primaryColor = ref.watch(primaryColorProvider);

    return BeeScaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: '应付款详情',
            subtitle: payable.payeeName,
            showBack: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editPayable(context, ref),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              children: [
                _buildOverviewCard(context, ref, paymentsAsync.value ?? []),
                SizedBox(height: 16.0.scaled(context, ref)),
                _buildPaymentHistory(context, ref, paymentsAsync),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, ref, primaryColor, paymentsAsync.value ?? []),
    );
  }

  Widget _buildOverviewCard(BuildContext context, WidgetRef ref, List<db.PayablePayment> payments) {
    final paidAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);
    final remaining = payable.amount - paidAmount;

    return SectionCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(16.0.scaled(context, ref)),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatItem(label: '总额', value: payable.amount, currencyCode: currencyCode),
                _StatItem(label: '已还', value: paidAmount, currencyCode: currencyCode, color: Colors.green),
                _StatItem(label: '待还', value: remaining, currencyCode: currencyCode, color: remaining > 0 ? Colors.orange : Colors.grey),
              ],
            ),
            if (payable.note != null && payable.note!.isNotEmpty) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '备注: ${payable.note}',
                  style: TextStyle(fontSize: 13, color: BeeTokens.textSecondary(context)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistory(BuildContext context, WidgetRef ref, AsyncValue<List<db.PayablePayment>> paymentsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4.0.scaled(context, ref), bottom: 8.0.scaled(context, ref)),
          child: Text(
            '还款记录',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BeeTokens.textPrimary(context)),
          ),
        ),
        paymentsAsync.when(
          data: (payments) {
            if (payments.isEmpty) {
              return SectionCard(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(32.0.scaled(context, ref)),
                  child: Center(child: Text('暂无还款记录', style: TextStyle(color: BeeTokens.textTertiary(context)))),
                ),
              );
            }
            return SectionCard(
              margin: EdgeInsets.zero,
              child: Column(
                children: payments.asMap().entries.map((entry) {
                  final index = entry.key;
                  final p = entry.value;
                  return Column(
                    children: [
                      if (index > 0) BeeTokens.cardDivider(context),
                      _PaymentTile(payment: p, currencyCode: currencyCode),
                    ],
                  );
                }).toList(),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('加载失败: $err')),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, WidgetRef ref, Color primaryColor, List<db.PayablePayment> payments) {
    final paidAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);
    final remaining = payable.amount - paidAmount;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(16.0.scaled(context, ref)),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48.0.scaled(context, ref),
                child: ElevatedButton.icon(
                  onPressed: remaining <= 0 ? null : () => _addPayment(context, ref, remaining),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('记录还款', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editPayable(BuildContext context, WidgetRef ref) async {
    final account = await ref.read(accountByIdProvider(payable.accountId).future);
    if (account != null && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PayableEditPage(account: account, payable: payable),
        ),
      );
      // 返回后刷新
      Navigator.pop(context);
    }
  }

  void _addPayment(BuildContext context, WidgetRef ref, double remaining) async {
    final success = await showPaymentAddDialog(
      context: context,
      payableId: payable.id,
      initialAmount: remaining,
    );
    if (success == true) {
      ref.invalidate(payablePaymentsProvider(payable.id));
      // 触发账户页刷新
      ref.invalidate(allAccountStatsProvider);
      ref.invalidate(allAccountsTotalStatsProvider);
    }
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final double value;
  final String currencyCode;
  final Color? color;

  const _StatItem({required this.label, required this.value, required this.currencyCode, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: BeeTokens.textSecondary(context))),
        const SizedBox(height: 4),
        AmountText(
          value: value,
          signed: false,
          currencyCode: currencyCode,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color ?? BeeTokens.textPrimary(context)),
        ),
      ],
    );
  }
}

class _PaymentTile extends ConsumerWidget {
  final db.PayablePayment payment;
  final String currencyCode;

  const _PaymentTile({required this.payment, required this.currencyCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = payment.accountId != null ? ref.watch(accountByIdProvider(payment.accountId!)) : null;

    return ListTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${payment.happenedAt.year}-${payment.happenedAt.month}-${payment.happenedAt.day}',
              style: const TextStyle(fontSize: 14)),
          AmountText(
            value: payment.amount,
            signed: false,
            currencyCode: currencyCode,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (payment.interestAmount > 0)
            Text('包含利息: ¥${payment.interestAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Colors.green)),
          Text('账户: ${accountAsync?.value?.name ?? '不入账'}',
              style: TextStyle(fontSize: 12, color: BeeTokens.textSecondary(context))),
          if (payment.note != null)
            Text('备注: ${payment.note}',
                style: TextStyle(fontSize: 12, color: BeeTokens.textTertiary(context))),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () => _deletePayment(context, ref),
      ),
    );
  }

  void _deletePayment(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这笔还款记录吗？相关的账户交易也会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(repositoryProvider).deletePayablePayment(payment.id);
      ref.invalidate(payablePaymentsProvider(payment.payableId));
      ref.invalidate(allAccountStatsProvider);
      ref.invalidate(allAccountsTotalStatsProvider);
    }
  }
}
