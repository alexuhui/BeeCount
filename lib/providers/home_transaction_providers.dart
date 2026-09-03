import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/page_sizes.dart';
import '../data/db.dart';
import '../data/repositories/base_repository.dart';
import 'database_providers.dart';
import 'statistics_providers.dart';

class HomeTransactionPageState {
  const HomeTransactionPageState({
    this.items = const [],
    this.page = 0,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final List<({Transaction t, Category? category})> items;
  final int page;
  final int total;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get hasMore => items.length < total;

  HomeTransactionPageState copyWith({
    List<({Transaction t, Category? category})>? items,
    int? page,
    int? total,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return HomeTransactionPageState(
      items: items ?? this.items,
      page: page ?? this.page,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class HomeTransactionController extends StateNotifier<HomeTransactionPageState> {
  HomeTransactionController(this.repo, this.ledgerId)
      : super(const HomeTransactionPageState(loading: true)) {
    reload();
  }

  final BaseRepository repo;
  final int ledgerId;

  Future<void> reload() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await repo.fetchTransactionsPage(
        ledgerId: ledgerId,
        page: 1,
        pageSize: PageSizes.homeTransactions,
      );
      state = HomeTransactionPageState(
        items: page.items,
        page: 1,
        total: page.total,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true);
    try {
      final next = state.page + 1;
      final page = await repo.fetchTransactionsPage(
        ledgerId: ledgerId,
        page: next,
        pageSize: PageSizes.homeTransactions,
      );
      state = state.copyWith(
        items: [...state.items, ...page.items],
        page: next,
        total: page.total,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

final homeTransactionControllerProvider = StateNotifierProvider.autoDispose
    .family<HomeTransactionController, HomeTransactionPageState, int>(
        (ref, ledgerId) {
  ref.watch(statsRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  return HomeTransactionController(repo, ledgerId);
});
