import 'dart:io';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart';
import '../l10n/app_localizations.dart';
import '../services/data/seed_service.dart';
import '../services/system/logger_service.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'db.g.dart';

// --- Tables ---

class Ledgers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  TextColumn get type => text().withDefault(const Constant('personal'))();  // personal / shared
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ledgerId => integer()(); // 保留用于v2迁移，后续会移除
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('cash'))();
  TextColumn get currency =>
      text().withDefault(const Constant('CNY'))(); // v1.15.0新增：币种
  RealColumn get initialBalance => real().withDefault(const Constant(0.0))();
  DateTimeColumn get createdAt =>
      dateTime().nullable()(); // v1.15.0: 改为可空，避免迁移问题
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get kind => text()(); // expense / income
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder =>
      integer().withDefault(const Constant(0))(); // 排序顺序，数字越小越靠前
  IntColumn get parentId => integer().nullable()(); // 父分类ID，null 表示一级分类
  IntColumn get level =>
      integer().withDefault(const Constant(1))(); // 层级：1=一级，2=二级
  // v13: 自定义图标支持
  TextColumn get iconType =>
      text().withDefault(const Constant('material'))(); // material / custom / community
  TextColumn get customIconPath => text().nullable()(); // 自定义图标本地路径
  TextColumn get communityIconId => text().nullable()(); // 社区图标ID（预留）
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ledgerId => integer()();
  TextColumn get type => text()(); // expense / income / transfer
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().nullable()();
  IntColumn get accountId => integer().nullable()();
  IntColumn get toAccountId => integer().nullable()();
  DateTimeColumn get happenedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get note => text().nullable()();
  IntColumn get recurringId => integer().nullable()(); // 关联到重复交易模板
  BoolColumn get excludeFromStats =>
      boolean().withDefault(const Constant(false))(); // v1.17.1: 是否排除在统计之外
  IntColumn get receivableId => integer().nullable()(); // v1.17.1: 关联的应收款ID
  IntColumn get payableId => integer().nullable()(); // v1.17.1: 关联的应付款ID
  IntColumn get receivablePaymentId => integer().nullable()(); // v1.19.0: 关联的应收款收款记录ID
  IntColumn get payablePaymentId => integer().nullable()(); // v1.19.0: 关联的应付款还款记录ID
}

class RecurringTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ledgerId => integer()();
  TextColumn get type => text()(); // expense / income / transfer
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().nullable()(); // 转账时为null
  IntColumn get accountId => integer().nullable()();
  IntColumn get toAccountId => integer().nullable()(); // 转账的目标账户
  TextColumn get note => text().nullable()();

  // 重复规则
  TextColumn get frequency => text()(); // daily / weekly / monthly / yearly
  IntColumn get interval =>
      integer().withDefault(const Constant(1))(); // 间隔（每1天、每2周等）
  IntColumn get dayOfMonth => integer().nullable()(); // 月的第几天（1-31）
  IntColumn get dayOfWeek => integer().nullable()(); // 周几（1=周一, 7=周日）
  IntColumn get monthOfYear => integer().nullable()(); // 哪个月（1-12，用于yearly）

  // 时间范围
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()(); // 为空表示永久
  DateTimeColumn get lastGeneratedDate =>
      dateTime().nullable()(); // 最后一次生成交易的日期

  // 状态
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// AI 对话表
class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  @Deprecated('对话已改为全局，不再与账本关联')
  IntColumn get ledgerId => integer().nullable()();
  TextColumn get title => text().withDefault(const Constant('AI对话'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// AI 消息表
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId => integer()();
  TextColumn get role => text()(); // 'user' | 'assistant'
  TextColumn get content => text()();
  TextColumn get messageType => text()(); // 'text' | 'bill_card'
  TextColumn get metadata => text().nullable()(); // JSON (BillInfo 数据)
  IntColumn get transactionId => integer().nullable()(); // 关联的交易ID(撤销用)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 标签表
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();                    // 标签名称
  TextColumn get color => text().nullable()();        // 颜色值（如 #FF5722）
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();  // 排序
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 交易-标签关联表
class TransactionTags extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer()();         // 交易ID
  IntColumn get tagId => integer()();                 // 标签ID
}

// 交易附件表
class TransactionAttachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer()(); // 关联的交易ID
  TextColumn get fileName => text()();        // 文件名（不含路径）
  TextColumn get originalName => text().nullable()(); // 原始文件名
  IntColumn get fileSize => integer().nullable()();   // 文件大小（bytes）
  IntColumn get width => integer().nullable()();      // 图片宽度
  IntColumn get height => integer().nullable()();     // 图片高度
  IntColumn get sortOrder => integer().withDefault(const Constant(0))(); // 排序序号
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 预算表
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 关联账本ID
  IntColumn get ledgerId => integer()();

  // /// 预算类型：total-总预算, category-分类预算
  // TextColumn get type => text().withDefault(const Constant('total'))();

  /// 年份
  IntColumn get year => integer()();

  /// 月份
  IntColumn get month => integer()();

  /// 关联分类ID（仅分类预算有值）
  IntColumn get categoryId => integer().nullable()();

  /// 预算金额
  RealColumn get amount => real()();

  // /// 预算周期：monthly-月度, weekly-周度, yearly-年度
  // TextColumn get period => text().withDefault(const Constant('monthly'))();

  // /// 周期起始日（1-31，月度预算；1-7，周度预算）
  // IntColumn get startDay => integer().withDefault(const Constant(1))();

  /// 是否启用
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 更新时间
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// 是否提示用户支付
  BoolColumn get prompt => boolean().withDefault(const Constant(false))();

  /// 提示日期
  IntColumn get promptDay => integer().nullable()();

  /// 是否不再提示（用户已支付）
  BoolColumn get ignored => boolean().nullable()();
}

/// 应收款记录表
class Receivables extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 关联账户ID（应收款账户）
  IntColumn get accountId => integer()();

  /// 借款人名称
  TextColumn get borrowerName => text()();

  /// 金额
  RealColumn get amount => real()();

  /// 借款日期
  DateTimeColumn get borrowDate => dateTime()();

  /// 备注
  TextColumn get note => text().nullable()();

  /// 借款账户ID（借款时扣款的账户）
  IntColumn get fromAccountId => integer()();

  /// 是否已收款
  BoolColumn get isReceived => boolean().withDefault(const Constant(false))();

  /// 收款日期
  DateTimeColumn get receiveDate => dateTime().nullable()();

  /// 收款账户ID（收回借款时入账的账户）
  IntColumn get toAccountId => integer().nullable()();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 更新时间
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 应付款记录表
class Payables extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 关联账户ID（应付款账户）
  IntColumn get accountId => integer()();

  /// 收款人名称
  TextColumn get payeeName => text()();

  /// 金额
  RealColumn get amount => real()();

  /// 日期
  DateTimeColumn get payDate => dateTime()();

  /// 备注
  TextColumn get note => text().nullable()();

  /// 入账账户ID（钱转入到了哪里）
  IntColumn get toAccountId => integer()();

  /// 是否已还款
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();

  /// 还款日期
  DateTimeColumn get paidDate => dateTime().nullable()();

  /// 还款账户ID
  IntColumn get fromAccountId => integer().nullable()();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 更新时间
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 应收款收款记录表
class ReceivablePayments extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 关联应收款ID
  IntColumn get receivableId => integer()();

  /// 本金金额
  RealColumn get amount => real()();

  /// 利息金额
  RealColumn get interestAmount => real().withDefault(const Constant(0.0))();

  /// 收款日期
  DateTimeColumn get happenedAt => dateTime()();

  /// 收款账户ID（入账账户，可为空表示仅记录不入账）
  IntColumn get accountId => integer().nullable()();

  /// 备注
  TextColumn get note => text().nullable()();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 应付款还款记录表
class PayablePayments extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 关联应付款ID
  IntColumn get payableId => integer()();

  /// 本金金额
  RealColumn get amount => real()();

  /// 利息金额
  RealColumn get interestAmount => real().withDefault(const Constant(0.0))();

  /// 还款日期
  DateTimeColumn get happenedAt => dateTime()();

  /// 还款账户ID（扣款账户，可为空表示仅记录不入账）
  IntColumn get accountId => integer().nullable()();

  /// 备注
  TextColumn get note => text().nullable()();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [
  Ledgers,
  Accounts,
  Categories,
  Transactions,
  RecurringTransactions,
  Conversations,
  Messages,
  Tags,
  TransactionTags,
  Budgets,
  TransactionAttachments,
  Receivables,
  Payables,
  ReceivablePayments,
  PayablePayments,
])
class BeeDatabase extends _$BeeDatabase {
  BeeDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await customStatement('''
            CREATE TABLE IF NOT EXISTS sync_queue_items (
              entity TEXT NOT NULL,
              local_id INTEGER NOT NULL,
              action TEXT NOT NULL,
              payload TEXT,
              retry_count INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              PRIMARY KEY (entity, local_id)
            );
          ''');
          await customStatement('''
            CREATE TABLE IF NOT EXISTS sync_id_maps (
              entity TEXT NOT NULL,
              local_id INTEGER NOT NULL,
              remote_id INTEGER NOT NULL,
              updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              PRIMARY KEY (entity, local_id)
            );
          ''');
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            // 添加 sortOrder 字段（使用原始 SQL，因为此时代码还未生成）
            await customStatement(
                'ALTER TABLE categories ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;');

            // 为现有分类设置默认的 sortOrder（按 id 顺序）
            await customStatement('''
          UPDATE categories
          SET sort_order = (
            SELECT COUNT(*)
            FROM categories AS c2
            WHERE c2.id <= categories.id
          ) - 1;
        ''');
          }
          if (from < 3) {
            // 创建重复交易表
            await migrator.createTable(recurringTransactions);

            // 为 transactions 表添加 recurring_id 字段
            await customStatement(
                'ALTER TABLE transactions ADD COLUMN recurring_id INTEGER;');
          }
          if (from < 4) {
            // 为 accounts 表添加 initial_balance 字段
            await customStatement(
                'ALTER TABLE accounts ADD COLUMN initial_balance REAL NOT NULL DEFAULT 0.0;');
          }
          if (from < 5) {
            // v5: 账户独立改造
            // 注意：数据迁移逻辑在 MigrationService 中统一处理
            // 这里只添加必要的字段

            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(accounts)').get();
            final hasCurrency =
                tableInfo.any((row) => row.data['name'] == 'currency');
            final hasCreatedAt =
                tableInfo.any((row) => row.data['name'] == 'created_at');
            final hasUpdatedAt =
                tableInfo.any((row) => row.data['name'] == 'updated_at');

            if (!hasCurrency) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN currency TEXT NOT NULL DEFAULT \'CNY\';');
            }

            if (!hasCreatedAt) {
              // SQLite 不支持非常量默认值，先添加可空字段，然后更新
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN created_at INTEGER;');
              await customStatement(
                  'UPDATE accounts SET created_at = strftime(\'%s\', \'now\') WHERE created_at IS NULL;');
            }

            if (!hasUpdatedAt) {
              await customStatement(
                  'ALTER TABLE accounts ADD COLUMN updated_at INTEGER;');
            }

            // 注意：不在onUpgrade中更新currency数据
            // 数据迁移统一由 MigrationService 处理，避免重复逻辑
          }
          if (from < 6) {
            // v6: 二级分类支持
            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(categories)').get();
            final hasParentId =
                tableInfo.any((row) => row.data['name'] == 'parent_id');
            final hasLevel =
                tableInfo.any((row) => row.data['name'] == 'level');

            if (!hasParentId) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN parent_id INTEGER;');
            }

            if (!hasLevel) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN level INTEGER NOT NULL DEFAULT 1;');
            }

            // 确保所有现有分类的 level 都为 1（一级分类）
            await customStatement(
                'UPDATE categories SET level = 1 WHERE level IS NULL OR level = 0;');
          }
          if (from < 7) {
            print('[DB Migration] 开始迁移到 v7: 周期账单支持转账');
            // v7: 周期账单支持转账
            // 需要将 category_id 改为可空，并添加 to_account_id 字段
            // SQLite 不支持修改列约束，所以需要重建表

            // 1. 创建新表
            print('[DB Migration] 步骤1: 创建新表');
            await customStatement('''
              CREATE TABLE IF NOT EXISTS recurring_transactions_new (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                ledger_id INTEGER NOT NULL,
                type TEXT NOT NULL,
                amount REAL NOT NULL,
                category_id INTEGER,
                account_id INTEGER,
                to_account_id INTEGER,
                note TEXT,
                frequency TEXT NOT NULL,
                interval INTEGER NOT NULL DEFAULT 1,
                day_of_month INTEGER,
                day_of_week INTEGER,
                month_of_year INTEGER,
                start_date INTEGER NOT NULL,
                end_date INTEGER,
                last_generated_date INTEGER,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
              );
            ''');

            // 2. 复制数据
            print('[DB Migration] 步骤2: 复制数据');
            await customStatement('''
              INSERT INTO recurring_transactions_new
              (id, ledger_id, type, amount, category_id, account_id, to_account_id, note,
               frequency, interval, day_of_month, day_of_week, month_of_year,
               start_date, end_date, last_generated_date, enabled, created_at, updated_at)
              SELECT id, ledger_id, type, amount, category_id, account_id,
                     NULL as to_account_id, note,
                     frequency, interval, day_of_month, day_of_week, month_of_year,
                     start_date, end_date, last_generated_date, enabled, created_at, updated_at
              FROM recurring_transactions;
            ''');

            // 3. 删除旧表
            print('[DB Migration] 步骤3: 删除旧表');
            await customStatement('DROP TABLE recurring_transactions;');

            // 4. 重命名新表
            print('[DB Migration] 步骤4: 重命名新表');
            await customStatement('ALTER TABLE recurring_transactions_new RENAME TO recurring_transactions;');
            print('[DB Migration] v7 迁移完成');
          }
          if (from < 8) {
            // v8: AI 对话助手
            print('[DB Migration] 开始迁移到 v8: AI 对话助手');
            await migrator.createTable(conversations);
            await migrator.createTable(messages);
            logger.info('DB', 'v8 迁移完成: AI Chat tables created');
            print('[DB Migration] v8 迁移完成');
          }
          if (from < 9) {
            // v9: 为 ledgers 表添加 type 字段（支持家庭账本）
            print('[DB Migration] 开始迁移到 v9: 添加 ledgers.type 字段');

            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(ledgers)').get();
            final hasType =
                tableInfo.any((row) => row.data['name'] == 'type');

            if (!hasType) {
              await customStatement(
                  'ALTER TABLE ledgers ADD COLUMN type TEXT NOT NULL DEFAULT \'personal\';');
              logger.info('DB', 'v9 迁移完成: ledgers.type 字段已添加');
            } else {
              logger.info('DB', 'v9 迁移跳过: ledgers.type 字段已存在');
            }

            print('[DB Migration] v9 迁移完成');
          }
          if (from < 10) {
            // v10: 添加标签功能
            print('[DB Migration] 开始迁移到 v10: 添加标签功能');

            // 创建 tags 表
            await migrator.createTable(tags);
            logger.info('DB', 'v10: tags 表已创建');

            // 创建 transaction_tags 关联表
            await migrator.createTable(transactionTags);
            logger.info('DB', 'v10: transaction_tags 表已创建');

            // 创建索引以提高查询性能
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_transaction_tags_transaction ON transaction_tags(transaction_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_transaction_tags_tag ON transaction_tags(tag_id)');
            logger.info('DB', 'v10: 索引已创建');

            print('[DB Migration] v10 迁移完成');
          }
          if (from < 11) {
            // v11: 添加预算功能
            print('[DB Migration] 开始迁移到 v11: 添加预算功能');

            // 创建 budgets 表
            await migrator.createTable(budgets);
            logger.info('DB', 'v11: budgets 表已创建');

            // 创建索引以提高查询性能
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_budgets_ledger ON budgets(ledger_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_budgets_category ON budgets(category_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_budgets_ledger_type ON budgets(ledger_id, type)');
            logger.info('DB', 'v11: 预算索引已创建');

            print('[DB Migration] v11 迁移完成');
          }
          if (from < 12) {
            // v12: 添加交易附件功能
            print('[DB Migration] 开始迁移到 v12: 添加交易附件功能');

            // 创建 transaction_attachments 表
            await migrator.createTable(transactionAttachments);
            logger.info('DB', 'v12: transaction_attachments 表已创建');

            // 创建索引以提高查询性能
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_attachments_transaction ON transaction_attachments(transaction_id)');
            logger.info('DB', 'v12: 附件索引已创建');

            print('[DB Migration] v12 迁移完成');
          }
          if (from < 13) {
            // v13: 分类自定义图标支持
            print('[DB Migration] 开始迁移到 v13: 分类自定义图标支持');

            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(categories)').get();
            final hasIconType =
                tableInfo.any((row) => row.data['name'] == 'icon_type');
            final hasCustomIconPath =
                tableInfo.any((row) => row.data['name'] == 'custom_icon_path');
            final hasCommunityIconId =
                tableInfo.any((row) => row.data['name'] == 'community_icon_id');

            if (!hasIconType) {
              await customStatement(
                  "ALTER TABLE categories ADD COLUMN icon_type TEXT NOT NULL DEFAULT 'material';");
              logger.info('DB', 'v13: icon_type 字段已添加');
            }

            if (!hasCustomIconPath) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN custom_icon_path TEXT;');
              logger.info('DB', 'v13: custom_icon_path 字段已添加');
            }

            if (!hasCommunityIconId) {
              await customStatement(
                  'ALTER TABLE categories ADD COLUMN community_icon_id TEXT;');
              logger.info('DB', 'v13: community_icon_id 字段已添加');
            }

            print('[DB Migration] v13 迁移完成');
          }
          if (from < 14) {
            // v14: 迁移转账记录到虚拟转账分类
            print('[DB Migration] 开始迁移到 v14: 迁移转账记录到虚拟转账分类');
            await SeedService.migrateTransferTransactions(this);
            logger.info('DB', 'v14 迁移完成: 转账记录已关联到虚拟转账分类');
            print('[DB Migration] v14 迁移完成');
          }

          if (from < 15) {
            // v15: 更新（新增/删除）预算表字段
            print('[DB Migration] 开始迁移到 v15: 更新（新增/删除）预算表字段');

            // 删除旧字段
            // await customStatement('ALTER TABLE budgets DROP COLUMN IF EXISTS type;');
            // logger.info('DB', 'v15: 删除旧字段 type');

            // await customStatement('ALTER TABLE budgets DROP COLUMN IF EXISTS period;');
            // logger.info('DB', 'v15: 删除旧字段 period');

            // await customStatement('ALTER TABLE budgets DROP COLUMN IF EXISTS start_day;');
            // logger.info('DB', 'v15: 删除旧字段 start_day');


            // 检查字段是否已存在，避免重复添加
            final tableInfo =
                await customSelect('PRAGMA table_info(budgets)').get();

            final hasYear = tableInfo.any((row) => row.data['name'] == 'year');
            final hasMonth = tableInfo.any((row) => row.data['name'] == 'month');
            final hasPrompt = tableInfo.any((row) => row.data['name'] == 'prompt');
            final hasPromptDay = tableInfo.any((row) => row.data['name'] == 'prompt_day');
            final hasIgnored = tableInfo.any((row) => row.data['name'] == 'ignored');

            // 添加新字段
            if(!hasYear){
              await customStatement('ALTER TABLE budgets ADD COLUMN year INTEGER NOT NULL DEFAULT 2026;');
              logger.info('DB', 'v15: 添加新字段 year');
            }
            if(!hasMonth){
              await customStatement('ALTER TABLE budgets ADD COLUMN month INTEGER NOT NULL DEFAULT 3;');
              logger.info('DB', 'v15: 添加新字段 month');
            }
            if(!hasPrompt){
              await customStatement('ALTER TABLE budgets ADD COLUMN prompt BOOLEAN NOT NULL DEFAULT false;');
              logger.info('DB', 'v15: 添加新字段 prompt');
            }
            if(!hasPromptDay){
              await customStatement('ALTER TABLE budgets ADD COLUMN prompt_day INTEGER;');
              logger.info('DB', 'v15: 添加新字段 prompt_day');
            }
            if(!hasIgnored){
              await customStatement('ALTER TABLE budgets ADD COLUMN ignored BOOLEAN;');
              logger.info('DB', 'v15: 添加新字段 ignored');
            }

            print('[DB Migration] v15 迁移完成');
          }
          if (from < 16) {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS sync_queue_items (
                entity TEXT NOT NULL,
                local_id INTEGER NOT NULL,
                action TEXT NOT NULL,
                payload TEXT,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                PRIMARY KEY (entity, local_id)
              );
            ''');
            await customStatement('''
              CREATE TABLE IF NOT EXISTS sync_id_maps (
                entity TEXT NOT NULL,
                local_id INTEGER NOT NULL,
                remote_id INTEGER NOT NULL,
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                PRIMARY KEY (entity, local_id)
              );
            ''');
          }
          if (from < 17) {
            // v17: 添加应收款/应付款表
            print('[DB Migration] 开始迁移到 v17: 添加应收款/应付款表');
            await migrator.createTable(receivables);
            await migrator.createTable(payables);
            logger.info('DB', 'v17: receivables 和 payables 表已创建');
            print('[DB Migration] v17 迁移完成');
          }
          if (from < 18) {
            // v18: 添加 Transactions.exclude_from_stats 字段
            print('[DB Migration] 开始迁移到 v18: 添加 Transactions.exclude_from_stats 等字段');
            final tableInfo = await customSelect('PRAGMA table_info(transactions)').get();
            final hasExcludeFromStats = tableInfo.any((row) => row.data['name'] == 'exclude_from_stats');
            if (!hasExcludeFromStats) {
              await customStatement('ALTER TABLE transactions ADD COLUMN exclude_from_stats INTEGER NOT NULL DEFAULT 0;');
            }
            final hasReceivableId = tableInfo.any((row) => row.data['name'] == 'receivable_id');
            if (!hasReceivableId) {
              await customStatement('ALTER TABLE transactions ADD COLUMN receivable_id INTEGER;');
            }
            final hasPayableId = tableInfo.any((row) => row.data['name'] == 'payable_id');
            if (!hasPayableId) {
              await customStatement('ALTER TABLE transactions ADD COLUMN payable_id INTEGER;');
            }
            logger.info('DB', 'v18 迁移完成: transactions 扩展字段已添加');
          }
          if (from < 19) {
            // v19: 添加应收应付的分次还款记录
            print('[DB Migration] 开始迁移到 v19: 添加 ReceivablePayments 和 PayablePayments 表');
            await migrator.createTable(receivablePayments);
            await migrator.createTable(payablePayments);
            
            // 为 transactions 表添加关联 payment 的字段
            final tableInfo = await customSelect('PRAGMA table_info(transactions)').get();
            final hasReceivablePaymentId = tableInfo.any((row) => row.data['name'] == 'receivable_payment_id');
            if (!hasReceivablePaymentId) {
              await customStatement('ALTER TABLE transactions ADD COLUMN receivable_payment_id INTEGER;');
            }
            final hasPayablePaymentId = tableInfo.any((row) => row.data['name'] == 'payable_payment_id');
            if (!hasPayablePaymentId) {
              await customStatement('ALTER TABLE transactions ADD COLUMN payable_payment_id INTEGER;');
            }
            
            logger.info('DB', 'v19 迁移完成: 应收应付分次还款记录表及关联字段已创建');
          }
        },
      );

  // Seed minimal data
  /// [l10n] 国际化对象，如果为null则使用英文作为默认语言
  /// [currency] 货币代码
  /// [useHierarchicalCategories] 是否使用二级分类
  ///
  /// 注意：此方法只应在真正的首次初始化时调用（欢迎页完成时）
  Future<void> ensureSeed({
    AppLocalizations? l10n,
    String currency = 'CNY',
    bool useHierarchicalCategories = false,
    bool skipCategories = false,
  }) async {
    logger.info('db', 'ensureSeed 被调用');
    logger.info('db', 'l10n 是否提供: ${l10n != null}');
    logger.info('db', '货币: $currency');
    logger.info('db', '使用二级分类: $useHierarchicalCategories');
    logger.info('db', '跳过分类创建: $skipCategories');

    // 如果没有提供l10n，使用Lookup创建默认的英文版本
    final effectiveL10n = l10n ?? lookupAppLocalizations(const Locale('en'));
    logger.info('db', '使用的语言环境: ${l10n != null ? "提供的l10n" : "默认英文"}');

    await SeedService.seedDatabase(
      this,
      effectiveL10n,
      currency: currency,
      useHierarchicalCategories: useHierarchicalCategories,
      skipCategories: skipCategories,
    );
    logger.info('db', '数据库初始化完成');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'beecount.sqlite'));

    // 开发环境：如果检测到锁文件，尝试删除（仅用于调试）
    try {
      final shmFile = File(p.join(dir.path, 'beecount.sqlite-shm'));
      final walFile = File(p.join(dir.path, 'beecount.sqlite-wal'));

      if (shmFile.existsSync() || walFile.existsSync()) {
        logger.warning('db', '检测到 SQLite 临时文件，可能存在锁定');
        // 注意：只在开发环境中记录，不自动删除，因为可能正在使用
      }
    } catch (e) {
      logger.debug('db', '检查锁文件时出错: $e');
    }

    return NativeDatabase.createInBackground(file);
  });
}

/// 开发工具：清除数据库锁文件（仅在应用完全关闭后使用）
Future<void> clearDatabaseLockFiles() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final shmFile = File(p.join(dir.path, 'beecount.sqlite-shm'));
    final walFile = File(p.join(dir.path, 'beecount.sqlite-wal'));

    if (shmFile.existsSync()) {
      await shmFile.delete();
      logger.info('db', '已删除 .sqlite-shm 文件');
    }

    if (walFile.existsSync()) {
      await walFile.delete();
      logger.info('db', '已删除 .sqlite-wal 文件');
    }

    logger.info('db', '数据库锁文件清理完成');
  } catch (e) {
    logger.error('db', '清理锁文件失败', e);
  }
}
