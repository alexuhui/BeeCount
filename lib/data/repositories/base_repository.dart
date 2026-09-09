import 'ledger_repository.dart';
import 'transaction_repository.dart';
import 'category_repository.dart';
import 'account_repository.dart';
import 'statistics_repository.dart';
import 'recurring_transaction_repository.dart';
import 'ai_repository.dart';
import 'tag_repository.dart';
import 'budget_repository.dart';
import 'attachment_repository.dart';
import 'receivable_payable_repository.dart';

/// 基础 Repository 抽象类
/// 组合所有 Repository 接口，用于类型约束
/// 线上实现为 [ApiRepository]（登录后账本数据走服务器）。
abstract class BaseRepository
    implements
        LedgerRepository,
        TransactionRepository,
        CategoryRepository,
        AccountRepository,
        StatisticsRepository,
        RecurringTransactionRepository,
        AIRepository,
        TagRepository,
        BudgetRepository,
        AttachmentRepository,
        ReceivablePayableRepository {
  /// 清空所有本地数据
  /// 注意：此操作会删除所有账本、交易、分类、账户等数据，不可恢复
  Future<void> clearAllData();
}
