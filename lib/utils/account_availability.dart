import '../data/db.dart';

/// 账本可用账户：与账本币种相同的账户。账本不存在时返回空列表，避免 `.single` 抛错。
List<Account> accountsAvailableForLedger({
  required Ledger? ledger,
  required List<Account> allAccounts,
}) {
  if (ledger == null) return const [];
  return allAccounts.where((a) => a.currency == ledger.currency).toList();
}
