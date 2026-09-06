import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import '../../data/db.dart';
import '../../styles/tokens.dart';
import '../../utils/lru_cache.dart';
import '../../providers.dart';
import '../../services/system/logger_service.dart';

/// 账户选择器组件
/// 横滑标签形式，支持 LRU 排序
class AccountSelector extends ConsumerStatefulWidget {
  final int? selectedAccountId;
  final ValueChanged<int?> onAccountSelected;
  final int ledgerId;

  const AccountSelector({
    super.key,
    required this.selectedAccountId,
    required this.onAccountSelected,
    required this.ledgerId,
  });

  @override
  ConsumerState<AccountSelector> createState() => _AccountSelectorState();
}

class _AccountSelectorState extends ConsumerState<AccountSelector> {
  List<int> _lruOrder = [];
  late LRUCache _lruCache;

  int? _initialSelectedAccountId;

  @override
  void initState() {
    super.initState();
    _initialSelectedAccountId = widget.selectedAccountId;
    _lruCache = LRUCache(key: 'account_lru_${widget.ledgerId}', maxSize: 20);
    _loadLru();
  }

  Future<void> _loadLru() async {
    final lruOrder = await _lruCache.getOrderedIds();
    if (mounted) {
      setState(() => _lruOrder = lruOrder);
    }
  }

  List<Account> _filterAccounts(List<Account> all, String? currency) {
    return all
        .where((a) =>
            (currency == null || a.currency == currency) &&
            a.type != 'receivable' &&
            a.type != 'payable')
        .toList();
  }

  List<Account> _getSortedAccounts(List<Account> accounts) {
    if (accounts.isEmpty) return [];

    final List<Account> sorted = [];

    if (_initialSelectedAccountId != null) {
      final selected =
          accounts.where((a) => a.id == _initialSelectedAccountId).firstOrNull;
      if (selected != null) {
        sorted.add(selected);
      }
    }

    for (final id in _lruOrder) {
      final account = accounts
          .where((a) => a.id == id && a.id != _initialSelectedAccountId)
          .firstOrNull;
      if (account != null && !sorted.contains(account)) {
        sorted.add(account);
      }
    }

    for (final account in accounts) {
      if (!sorted.contains(account)) {
        sorted.add(account);
      }
    }

    return sorted;
  }

  void _onAccountTap(int? accountId) {
    logger.debug(
        'AccountSelector', '点击账户: $accountId, 当前LRU顺序: $_lruOrder');
    widget.onAccountSelected(accountId);

    if (accountId != null) {
      _lruCache.recordUsage(accountId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final ledgerAsync = ref.watch(ledgerByIdProvider(widget.ledgerId));
    final accounts = _filterAccounts(
      accountsAsync.valueOrNull ?? const [],
      ledgerAsync.valueOrNull?.currency,
    );

    if (accountsAsync.isLoading && accounts.isEmpty) {
      return const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final sortedAccounts = _getSortedAccounts(accounts);

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: sortedAccounts.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = widget.selectedAccountId == null;
            return _buildAccountChip(
              label: '无账户',
              isSelected: isSelected,
              onTap: () => _onAccountTap(null),
            );
          }

          final account = sortedAccounts[index - 1];
          final isSelected = widget.selectedAccountId == account.id;

          return _buildAccountChip(
            label: account.name,
            isSelected: isSelected,
            onTap: () => _onAccountTap(account.id),
          );
        },
      ),
    );
  }

  Widget _buildAccountChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final primaryColor = ref.watch(primaryColorProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : BeeTokens.surfaceChip(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? Colors.white : BeeTokens.textSecondary(context),
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
