import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../ui/ui.dart';

/// 账户选择器数据模型
class AccountOption {
  final int? id;
  final String name;
  final String type;
  final IconData icon;

  AccountOption({
    this.id,
    required this.name,
    required this.type,
    required this.icon,
  });
}

/// 账户选择器组件（使用滚轮样式）
class AccountPicker extends ConsumerStatefulWidget {
  final int? selectedAccountId;
  final bool allowNull;

  const AccountPicker({
    super.key,
    this.selectedAccountId,
    this.allowNull = true,
  });

  @override
  ConsumerState<AccountPicker> createState() => _AccountPickerState();

  /// 显示账户选择器底部弹窗
  static Future<int?> show(
    BuildContext context, {
    int? selectedAccountId,
    bool allowNull = true,
  }) async {
    return showModalBottomSheet<int?>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => AccountPicker(
        selectedAccountId: selectedAccountId,
        allowNull: allowNull,
      ),
    );
  }
}

class _AccountPickerState extends ConsumerState<AccountPicker> {
  FixedExtentScrollController? _controller;
  int _selectedIndex = 0;
  List<AccountOption> _options = [];
  /// 账户列表变化时需重建选项与滚轮控制器（不能只做一次初始化，否则流稍后推数据时列表不全）。
  String? _lastOptionsSignature;

  IconData _getIconForType(String type) {
    switch (type) {
      case 'cash':
        return Icons.payments_outlined;
      case 'bank_card':
        return Icons.credit_card;
      case 'credit_card':
        return Icons.credit_score;
      case 'alipay':
        return Icons.currency_yuan;
      case 'wechat':
        return Icons.chat;
      case 'other':
        return Icons.account_balance_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _getTypeLabel(BuildContext context, String type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case 'cash':
        return l10n.accountTypeCash;
      case 'bank_card':
        return l10n.accountTypeBankCard;
      case 'credit_card':
        return l10n.accountTypeCreditCard;
      case 'alipay':
        return l10n.accountTypeAlipay;
      case 'wechat':
        return l10n.accountTypeWechat;
      case 'other':
        return l10n.accountTypeOther;
      default:
        return type;
    }
  }

  String _optionsSignature(List<Account> accounts) {
    final parts = <String>[];
    for (final a in accounts) {
      if (a.type == 'receivable' || a.type == 'payable') continue;
      parts.add('${a.id}:${a.name}:${a.type}:${a.currency}');
    }
    parts.sort();
    return '${widget.allowNull}|${parts.join(";")}';
  }

  void _syncOptions(List<Account> accounts) {
    final sig = _optionsSignature(accounts);
    if (sig == _lastOptionsSignature && _controller != null) return;
    _lastOptionsSignature = sig;

    _options = [];

    if (widget.allowNull) {
      _options.add(AccountOption(
        id: null,
        name: AppLocalizations.of(context).accountNone,
        type: 'none',
        icon: Icons.remove,
      ));
    }

    for (final account in accounts) {
      if (account.type == 'receivable' || account.type == 'payable') {
        continue;
      }
      _options.add(AccountOption(
        id: account.id,
        name: account.name,
        type: account.type,
        icon: _getIconForType(account.type),
      ));
    }

    _selectedIndex = _options.indexWhere(
      (option) => option.id == widget.selectedAccountId,
    );
    if (_selectedIndex < 0) _selectedIndex = 0;
    if (_options.isNotEmpty) {
      _selectedIndex = _selectedIndex.clamp(0, _options.length - 1);
    }

    final previous = _controller;
    _controller =
        _options.isEmpty ? null : FixedExtentScrollController(initialItem: _selectedIndex);
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous.dispose();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // v1.15.0: 获取当前账本币种
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currentCurrency = currentLedgerAsync.asData?.value?.currency ?? 'CNY';

    // v1.15.0: 获取所有账户并按币种筛选
    final allAccountsAsync = ref.watch(allAccountsStreamProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = theme.primaryColor;

    return allAccountsAsync.when(
      data: (allAccounts) {
        // v1.15.0: 只显示与当前账本同币种的账户
        final accounts = allAccounts.where((account) =>
          account.currency == currentCurrency
        ).toList();

        _syncOptions(accounts);

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部操作栏
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        l10n.commonCancel,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      l10n.accountSelectTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _options.isEmpty
                          ? null
                          : () {
                              final selected = _options[_selectedIndex];
                              Navigator.pop(context, selected.id);
                            },
                      child: Text(
                        l10n.commonOk,
                        style: TextStyle(
                          fontSize: 16,
                          color: _options.isEmpty
                              ? colorScheme.onSurface.withValues(alpha: 0.38)
                              : primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 滚轮选择器
              if (_controller != null)
                SizedBox(
                  key: ValueKey(_lastOptionsSignature),
                  height: 216,
                  child: CupertinoPicker(
                    itemExtent: 72,
                    scrollController: _controller!,
                    selectionOverlay: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: primaryColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                          bottom: BorderSide(
                            color: primaryColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    children: _options.map((option) {
                      return _buildAccountItem(
                        option,
                        primaryColor,
                        colorScheme,
                      );
                    }).toList(),
                  ),
                )
              else
                SizedBox(
                  height: 120,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        l10n.accountsEmptyMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => SizedBox(
        height: 200,
        child: Center(
          child: Text('${l10n.commonError}: $err'),
        ),
      ),
    );
  }

  Widget _buildAccountItem(
    AccountOption option,
    Color primaryColor,
    ColorScheme colorScheme,
  ) {
    final isNone = option.id == null;
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isNone
                  ? colorScheme.surfaceContainerHighest
                  : primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              option.icon,
              color: isNone ? onSurfaceVariant : primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  option.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isNone) ...[
                  const SizedBox(height: 4),
                  Text(
                    _getTypeLabel(context, option.type),
                    style: TextStyle(
                      fontSize: 14,
                      color: onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
