import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/page_sizes.dart';
import '../../data/db.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../utils/invest_tx.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/ui/ui.dart';

class RecycleBinPage extends ConsumerStatefulWidget {
  const RecycleBinPage({super.key});

  @override
  ConsumerState<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends ConsumerState<RecycleBinPage> {
  final List<DeletedTransactionRecord> _items = [];
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _markSeen() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    await RecycleBinSeenStore.markNow(ledgerId);
    ref.invalidate(recycleBinSummaryProvider);
    ref.invalidate(recycleBinHasNewProvider);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _page = 0;
        _items.clear();
      });
    } else {
      if (_loadingMore || _items.length >= _total) return;
      setState(() => _loadingMore = true);
    }
    try {
      final ledgerId = ref.read(currentLedgerIdProvider);
      final pageNum = reset ? 1 : _page + 1;
      final result = await ref.read(repositoryProvider).getDeletedTransactions(
            ledgerId: ledgerId,
            page: pageNum,
            pageSize: PageSizes.recycleBin,
          );
      if (!mounted) return;
      setState(() {
        _page = pageNum;
        _total = result.total;
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items);
        } else {
          _items.addAll(result.items);
        }
        _loading = false;
        _loadingMore = false;
      });
      await _markSeen();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      showToast(context, '${AppLocalizations.of(context).commonError}: $e');
    }
  }

  Future<void> _afterChange() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    ref.read(statsRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: ledgerId);
    ref.invalidate(recycleBinSummaryProvider);
    ref.invalidate(recycleBinHasNewProvider);
    await _load(reset: true);
  }

  int _daysLeft(DateTime deletedAt) {
    final expire = deletedAt.add(const Duration(days: 30));
    final left = expire.difference(DateTime.now());
    if (left.isNegative) return 0;
    return left.inDays;
  }

  Future<void> _restore(DeletedTransactionRecord item) async {
    try {
      await ref.read(repositoryProvider).restoreDeletedTransaction(item.transaction.id);
      if (!mounted) return;
      showToast(context, AppLocalizations.of(context).recycleBinRestored);
      await _afterChange();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '${AppLocalizations.of(context).commonError}: $e');
    }
  }

  Future<void> _deleteForever(DeletedTransactionRecord item) async {
    final l10n = AppLocalizations.of(context);
    final ok = await AppDialog.confirm<bool>(
          context,
          title: l10n.recycleBinDeleteForever,
          message: l10n.recycleBinDeleteForeverConfirm,
        ) ??
        false;
    if (!ok) return;
    try {
      await ref
          .read(repositoryProvider)
          .permanentlyDeleteTransaction(item.transaction.id);
      if (!mounted) return;
      showToast(context, l10n.recycleBinPermanentlyDeleted);
      await _afterChange();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '${l10n.commonError}: $e');
    }
  }

  Future<void> _emptyAll() async {
    final l10n = AppLocalizations.of(context);
    if (_items.isEmpty) return;
    final ok = await AppDialog.confirm<bool>(
          context,
          title: l10n.recycleBinEmptyAll,
          message: l10n.recycleBinEmptyAllConfirm,
        ) ??
        false;
    if (!ok) return;
    try {
      final ledgerId = ref.read(currentLedgerIdProvider);
      await ref.read(repositoryProvider).emptyRecycleBin(ledgerId: ledgerId);
      if (!mounted) return;
      showToast(context, l10n.recycleBinEmptied);
      await _afterChange();
    } catch (e) {
      if (!mounted) return;
      showToast(context, '${l10n.commonError}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoriesProvider).asData?.value ?? [];

    return BeeScaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.recycleBinTitle,
            showBack: true,
            actions: [
              if (_items.isNotEmpty)
                IconButton(
                  tooltip: l10n.recycleBinEmptyAll,
                  onPressed: _emptyAll,
                  icon: const Icon(Icons.delete_forever_outlined),
                ),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? AppEmpty(
                        text: l10n.recycleBinEmpty,
                        subtext: l10n.recycleBinEmptyHint,
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >=
                              n.metrics.maxScrollExtent - 240) {
                            _load();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _items.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _items.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              );
                            }
                            final item = _items[index];
                            final tx = item.transaction;
                            Category? category;
                            if (tx.categoryId != null) {
                              for (final c in categories) {
                                if (c.id == tx.categoryId) {
                                  category = c;
                                  break;
                                }
                              }
                            }
                            final categoryName = CategoryUtils.getDisplayName(
                              category?.name,
                              context,
                            );
                            final note = tx.note ?? '';
                            final isExpense = tx.type == 'expense' ||
                                tx.type == InvestTx.loss;
                            final isTransfer = tx.type == 'transfer';
                            final days = _daysLeft(item.deletedAt);
                            return Column(
                              children: [
                                TransactionListItem(
                                  icon: getCategoryIconData(
                                    category: category,
                                    categoryName: categoryName,
                                  ),
                                  category: category,
                                  title: note.isNotEmpty ? note : categoryName,
                                  categoryName:
                                      note.isNotEmpty ? null : categoryName,
                                  amount: tx.amount,
                                  isExpense: isExpense,
                                  isTransfer: isTransfer,
                                  happenedAt: tx.happenedAt,
                                  showFullDate: true,
                                  onTap: () {},
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          l10n.recycleBinDaysLeft(days),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: BeeTokens.textSecondary(
                                                context),
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => _restore(item),
                                        child: Text(l10n.recycleBinRestore),
                                      ),
                                      TextButton(
                                        onPressed: () => _deleteForever(item),
                                        child: Text(
                                          l10n.recycleBinDeleteForever,
                                          style: TextStyle(
                                            color: BeeTokens.error(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                BeeTokens.cardDivider(context),
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
