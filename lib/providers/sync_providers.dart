import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ledger_display_item.dart';
import '../services/system/logger_service.dart';
import '../services/api/api_service.dart';

// ====== 账本相关 ======

/// 刷新账本列表的触发器
final ledgerListRefreshProvider = StateProvider<int>((ref) => 0);

/// 账本列表（从服务器获取）
final allLedgersProvider = FutureProvider<List<LedgerDisplayItem>>((ref) async {
  // 监听刷新触发器
  ref.watch(ledgerListRefreshProvider);

  try {
    // 从服务器获取账本列表
    final response = await ApiService.getLedgers();
    final ledgers = response['ledgers'] as List<dynamic>;

    final result = <LedgerDisplayItem>[];
    for (final ledger in ledgers) {
      final ledgerMap = ledger as Map<String, dynamic>;
      result.add(LedgerDisplayItem.fromLocal(
        id: ledgerMap['id'] as int,
        name: ledgerMap['name'] as String,
        currency: ledgerMap['currency'] as String,
        createdAt: DateTime.parse(ledgerMap['created_at'] as String),
        transactionCount: 0, // 暂时设为0，后续可以从服务器获取
        balance: 0.0, // 暂时设为0，后续可以从服务器获取
      ));
    }

    return result;
  } catch (e, stackTrace) {
    logger.error('AllLedgers', '获取账本列表失败', e, stackTrace);
    return [];
  }
});

/// 本地账本列表（兼容旧代码，实际从服务器获取）
final localLedgersProvider = FutureProvider<List<LedgerDisplayItem>>((ref) async {
  // 直接使用 allLedgersProvider，因为所有数据都从服务器获取
  return ref.watch(allLedgersProvider.future);
});

/// 远程账本列表（兼容旧代码，实际从服务器获取）
final remoteLedgersProvider = FutureProvider<List<LedgerDisplayItem>>((ref) async {
  // 直接使用 allLedgersProvider，因为所有数据都从服务器获取
  return ref.watch(allLedgersProvider.future);
});
