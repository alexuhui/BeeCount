import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/db.dart';
import '../data/repositories/api/api_repository.dart';
import '../data/repositories/base_repository.dart';
import '../services/system/logger_service.dart';
import '../services/user_settings/user_setting_keys.dart';
import '../services/user_settings/user_settings_store.dart';
import 'beecount_server_providers.dart';
import 'database_scope_provider.dart';
import '../services/database/database_scopes.dart';

// 数据库Provider（按 [databaseScopeKeyProvider] 隔离多账号本地数据）
final databaseProvider = Provider<BeeDatabase>((ref) {
  final scope = ref.watch(databaseScopeKeyProvider);
  final db = BeeDatabase(scopeKey: scope);
  Future.microtask(() async {
    final prefs = await SharedPreferences.getInstance();
    await UserSettingsStore.importIfPending(db, scope, prefs);
  });
  ref.onDispose(() => db.close());
  return db;
});

final userSettingsStoreProvider = Provider<UserSettingsStore>((ref) {
  final scope = ref.watch(databaseScopeKeyProvider);
  return UserSettingsStore(
    ref.watch(databaseProvider),
    allowPrefsFallback: scope != DatabaseScopes.signedOut,
  );
});

// 仓储Provider - 根据 AppMode 自动切换实现
// 返回 BaseRepository 类型，确保类型安全
// LocalRepository (本地模式) 和 CloudRepository (云端模式) 都继承 BaseRepository
final repositoryProvider = Provider<BaseRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final api = ref.watch(beecountApiClientProvider);
  if (api == null) {
    throw StateError('未登录，无法访问账本数据');
  }
  logger.info('RepositoryProvider', '使用 ApiRepository（服务器为准）');
  return ApiRepository(db, api: api);
});

final dynamicRepositoryProvider = Provider<Object>((ref) {
  return ref.watch(repositoryProvider);
});

// 记住当前账本：启动时加载，切换时持久化
final currentLedgerIdProvider = StateProvider<int>((ref) => 1);

// 首页切换到 Stream 模式触发器（用户交互时触发）
final homeSwitchToStreamProvider = StateProvider<int>((ref) => 0);

/// 完整的交易展示数据（含分类、标签、附件数量、账户名称）
/// 用于首页列表一次性加载，避免二次查询闪烁
typedef TransactionDisplayItem = ({
  Transaction t,
  Category? category,
  List<Tag> tags,
  int attachmentCount,
  String? accountName,
  String? toAccountName,
});

// 缓存的完整交易数据Provider（含标签、附件、账户，用于首屏快速展示）
final cachedTransactionsProvider =
    StateProvider<List<TransactionDisplayItem>?>((ref) => null);

// 缓存的交易数据Provider（仅含分类，兼容旧版本）
final cachedTransactionsWithCategoryProvider =
    StateProvider<List<({Transaction t, Category? category})>?>((ref) => null);

/// 换账号 / 登出 / 切换本地库 scope 后调用：清空首页交易缓存与账本选择，避免仍显示上一账号数据。
/// 参数为 [Ref] 或 [WidgetRef]（二者均提供 `read`）。
void resetInMemoryDataForAccountSwitch(dynamic ref) {
  ref.read(cachedTransactionsProvider.notifier).state = null;
  ref.read(cachedTransactionsWithCategoryProvider.notifier).state = null;
  ref.read(currentLedgerIdProvider.notifier).state = 1;
  ref.read(homeSwitchToStreamProvider.notifier).state =
      ref.read(homeSwitchToStreamProvider) + 1;
}

// 获取当前账本的详细信息
final currentLedgerProvider = FutureProvider<Ledger?>((ref) async {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  return await repo.getLedgerById(ledgerId);
});

// 获取指定账本的详细信息
final ledgerByIdProvider =
    FutureProvider.family<Ledger?, int>((ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);

  return await repo.getLedgerById(ledgerId);
});

// 获取所有账本列表（Stream版本）
final ledgersStreamProvider = StreamProvider<List<Ledger>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchLedgers();
});

final _currentLedgerPersist = Provider<void>((ref) {
  () async {
    try {
      final store = ref.read(userSettingsStoreProvider);
      final saved = await store.getInt(UserSettingKeys.currentLedgerId);
      if (saved != null) {
        final st = ref.read(currentLedgerIdProvider);
        if (st != saved) {
          ref.read(currentLedgerIdProvider.notifier).state = saved;
        }
      }
    } catch (_) {}
  }();
  ref.listen<int>(currentLedgerIdProvider, (prev, next) async {
    try {
      final store = ref.read(userSettingsStoreProvider);
      await store.setInt(UserSettingKeys.currentLedgerId, next);
    } catch (_) {}
  });
});

// 当账本切换时，顺便触发一次设置页状态刷新（确保"我的"页及时反映）
final _ledgerChangeListener = Provider<void>((ref) {
  ref.read(_currentLedgerPersist);
});

// 确保监听器被激活
final appInitProvider = FutureProvider<void>((ref) async {
  // 读取以激活监听
  ref.read(_ledgerChangeListener);
});

// 分类Provider
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.getAllCategories();
});

// 分类与交易笔数组合Provider（响应式版本）
// 使用 autoDispose 在页面关闭时自动取消订阅
final categoriesWithCountProvider = StreamProvider.autoDispose<
    List<({Category category, int transactionCount})>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchCategoriesWithCount();
});

// 虚拟转账分类Provider（全局缓存，用于获取转账图标）
final transferCategoryProvider = FutureProvider<Category>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.getTransferCategory();
});

// 重复交易Provider（按账本过滤）
// 注意：此 provider 已废弃，请使用 allRecurringTransactionsProvider 并在业务层过滤
final recurringTransactionsProvider =
    FutureProvider.family<List<RecurringTransaction>, int>(
        (ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);
  final all = await repo.watchRecurringTransactionsByLedger(ledgerId).first;
  return all;
});

// 所有重复交易Provider（不限账本）
final allRecurringTransactionsProvider =
    StreamProvider.autoDispose<List<RecurringTransaction>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchAllRecurringTransactions();
});

// 账户Provider（按账本过滤）
final accountsStreamProvider =
    StreamProvider.family<List<Account>, int>((ref, ledgerId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchAccountsForLedger(ledgerId);
});

// v1.15.0: 所有账户Provider（不限账本）
final allAccountsStreamProvider = StreamProvider<List<Account>>((ref) {
  final repo = ref.watch(repositoryProvider);
  logger.info('AllAccountsStream', '使用的 Repository 类型: ${repo.runtimeType}');
  final stream = repo.watchAllAccounts();
  return stream;
});

// 获取单个账户信息
final accountByIdProvider =
    FutureProvider.family<Account?, int>((ref, accountId) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.getAccount(accountId);
});
