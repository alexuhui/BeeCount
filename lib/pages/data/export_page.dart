import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../../providers.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/db.dart';
import '../../widgets/ui/ui.dart';
import '../../utils/category_utils.dart';

class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});
  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  bool exporting = false;
  double progress = 0;
  String? savedPath;
  DateTime? startDate;
  DateTime? endDate;
  bool exportIncome = true;
  bool exportExpense = true;
  bool exportTransfer = true;
  bool exportInvestPnl = true;
  bool exportAccounts = true;
  bool exportReceivableList = true;
  bool exportPayableList = true;
  bool includeReceived = false;
  bool includePaid = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    startDate = DateTime(now.year, now.month, 1);
    endDate = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final l10n = AppLocalizations.of(context);
    return BeeScaffold(
      body: Column(
        children: [
          PrimaryHeader(title: l10n.exportTitle, showBack: true),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '支持按日期范围导出收入、支出、转账交易记录，也可以同时导出账户信息。'
                      '同时选择交易记录和账户信息时，将生成包含不同 Sheet 的 Excel 文件。',
                    ),
                    const SizedBox(height: 16),
                    // 日期范围选择
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('日期范围'),
                                const Spacer(),
                                FilledButton(
                                  onPressed: exporting ? null : _setCurrentYear,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('本年'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed:
                                      exporting ? null : _setCurrentMonth,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('本月'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed:
                                      exporting ? null : _setPreviousMonth,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('上月'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('开始日期'),
                                      const SizedBox(height: 8),
                                      FilledButton(
                                        onPressed: () async {
                                          final date =
                                              await showWheelDatePicker(
                                            context,
                                            initial: startDate!,
                                            minDate: DateTime(2000, 1, 1),
                                            maxDate: DateTime.now(),
                                          );
                                          if (date != null) {
                                            setState(() => startDate = date);
                                          }
                                        },
                                        child: Text(startDate != null
                                            ? DateFormat('yyyy-MM-dd')
                                                .format(startDate!)
                                            : ''),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('结束日期'),
                                      const SizedBox(height: 8),
                                      FilledButton(
                                        onPressed: () async {
                                          final date =
                                              await showWheelDatePicker(
                                            context,
                                            initial: endDate!,
                                            minDate: startDate ??
                                                DateTime(2000, 1, 1),
                                            maxDate: DateTime.now(),
                                          );
                                          if (date != null) {
                                            setState(() => endDate = date);
                                          }
                                        },
                                        child: Text(endDate != null
                                            ? DateFormat('yyyy-MM-dd')
                                                .format(endDate!)
                                            : ''),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Text('导出内容'),
                            ),
                            CheckboxListTile(
                              value: exportAccounts,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(
                                      () => exportAccounts = value ?? false),
                              title: const Text('账户信息'),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportReceivableList,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(() =>
                                      exportReceivableList = value ?? false),
                              title: Row(
                                children: [
                                  const Text('应收列表'),
                                  const Text('（'),
                                  Checkbox(
                                    value: includeReceived,
                                    onChanged: exporting
                                        ? null
                                        : (value) => setState(() =>
                                            includeReceived = value ?? false),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  const Text('含已收）'),
                                ],
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportPayableList,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(
                                      () => exportPayableList = value ?? false),
                              title: Row(
                                children: [
                                  const Text('应付列表'),
                                  const Text('（'),
                                  Checkbox(
                                    value: includePaid,
                                    onChanged: exporting
                                        ? null
                                        : (value) => setState(
                                            () => includePaid = value ?? false),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  const Text('含已付）'),
                                ],
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportIncome,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(
                                      () => exportIncome = value ?? false),
                              title: const Text('收入交易记录'),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportExpense,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(
                                      () => exportExpense = value ?? false),
                              title: const Text('支出交易记录'),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportTransfer,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(
                                      () => exportTransfer = value ?? false),
                              title: const Text('转账交易记录'),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportInvestPnl,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(
                                      () => exportInvestPnl = value ?? false),
                              title: Text(l10n.exportInvestPnlRecords),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed:
                          exporting ? null : () => _export(repo, ledgerId),
                      icon: const Icon(Icons.save_alt_outlined),
                      label: Text(Platform.isIOS
                          ? l10n.exportButtonIOS
                          : l10n.exportButtonAndroid),
                    ),
                    const SizedBox(height: 16),
                    if (exporting)
                      Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LinearProgressIndicator(
                                value: progress == 0 ? null : progress),
                          ),
                        ],
                      ),
                    if (savedPath != null) ...[
                      const SizedBox(height: 12),
                      Text(l10n.exportSavedTo(savedPath!)),
                    ],
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _export(BaseRepository repo, int ledgerId) async {
    try {
      final selectedTypes = <String>{
        if (exportIncome) 'income',
        if (exportExpense) 'expense',
        if (exportTransfer) 'transfer',
        if (exportInvestPnl) ...['invest_gain', 'invest_loss'],
      };
      final shouldExportReceivableData =
          exportReceivableList || exportPayableList;
      final shouldExportTransactions = selectedTypes.isNotEmpty;
      if (!shouldExportTransactions &&
          !exportAccounts &&
          !shouldExportReceivableData) {
        showToast(context, '请至少选择一项导出内容');
        return;
      }

      setState(() {
        exporting = true;
        progress = 0;
        savedPath = null;
      });
      String? directory;
      bool shareAfter = false;
      if (Platform.isIOS) {
        // iOS: 写入应用文档目录，然后使用系统分享
        final docDir = await getApplicationDocumentsDirectory();
        directory = docDir.path;
        shareAfter = true;
      } else if (Platform.isAndroid) {
        // Android: 使用系统保存入口获取写入授权，避免分区存储下直接写 Download 被拒绝。
      } else if (Platform.isWindows) {
        // Windows: 下载目录，
        final docDir = await getDownloadsDirectory();
        directory = docDir?.path ?? '';
        if (directory.isEmpty) {
          if (!mounted) return;
          setState(() => exporting = false);
          showToast(context, '无法获取下载目录');
          return;
        }
      } else {
        // 其他平台: 不支持导出
        if (mounted) {
          setState(() => exporting = false);
        }
        showToast(context, '不支持在${Platform.operatingSystem}上导出数据');
        return;
      }

      // 设置默认日期范围（如果未选择）
      final start =
          startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
      final end = endDate ??
          DateTime(
              DateTime.now().year, DateTime.now().month, DateTime.now().day);
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      final allTransactionsWithCategory =
          shouldExportTransactions || exportAccounts
              ? await repo.transactionsWithCategoryAll(ledgerId: ledgerId).first
              : <({Transaction t, Category? category})>[];

      List<({Transaction t, Category? category})> transactions = [];
      if (shouldExportTransactions) {
        transactions = allTransactionsWithCategory.where((tx) {
          final txDate = tx.t.happenedAt.toLocal();
          return selectedTypes.contains(tx.t.type) &&
              txDate.isAfter(start.subtract(const Duration(days: 1))) &&
              txDate.isBefore(end.add(const Duration(days: 1)));
        }).toList();
      }

      final accountsForExport = exportAccounts
          ? await repo.getAvailableAccountsForLedger(ledgerId)
          : <Account>[];
      final accountsForReceivable = shouldExportReceivableData
          ? await repo.getAvailableAccountsForLedger(ledgerId)
          : <Account>[];
      final allAccounts = <Account>[
        ...accountsForExport,
        ...accountsForReceivable,
      ];
      final accountIds = <int>{
        for (final account in allAccounts) account.id,
        for (final tx in transactions) ...[
          if (tx.t.accountId != null) tx.t.accountId!,
          if (tx.t.toAccountId != null) tx.t.toAccountId!,
        ],
      };
      final accountMap = <int, Account>{
        for (final account in allAccounts) account.id: account,
      };
      if (accountIds.isNotEmpty) {
        final accounts = await repo.getAccountsByIds(accountIds.toList());
        accountMap.addEntries(accounts.map((a) => MapEntry(a.id, a)));
      }

      final receivableData = shouldExportReceivableData
          ? await _loadReceivableListData(
              repo: repo,
              accounts: accountsForReceivable,
            )
          : (list: <Receivable>[], outstandingById: <int, double>{});
      final payableData = shouldExportReceivableData
          ? await _loadPayableListData(
              repo: repo,
              accounts: accountsForReceivable,
            )
          : (list: <Payable>[], outstandingById: <int, double>{});

      final exportSheets = <String, List<List<dynamic>>>{};
      if (shouldExportTransactions) {
        exportSheets['归类统计'] = await _buildCategorySummaryRows(
          repo: repo,
          transactions: transactions,
          start: start,
          end: end,
        );
      }
      if (exportAccounts) {
        exportSheets['账户信息'] = await _buildAccountRows(
          repo,
          accountsForExport,
          allTransactionsWithCategory.map((e) => e.t).toList(),
          start,
          end,
        );
      }
      if (exportReceivableList) {
        exportSheets['应收列表'] = _buildReceivableListRows(
          receivableData.list,
          receivableData.outstandingById,
          accountMap,
          includeReceived: includeReceived,
        );
      }
      if (exportPayableList) {
        exportSheets['应付列表'] = _buildPayableListRows(
          payableData.list,
          payableData.outstandingById,
          accountMap,
          includePaid: includePaid,
        );
      }
      if (shouldExportTransactions) {
        if (exportIncome) {
          exportSheets['收入记录'] = _buildTransactionRows(
            transactions.where((tx) => tx.t.type == 'income').toList(),
            accountMap,
          );
        }
        if (exportExpense) {
          exportSheets['支出记录'] = _buildTransactionRows(
            transactions.where((tx) => tx.t.type == 'expense').toList(),
            accountMap,
          );
        }
        if (exportTransfer) {
          exportSheets['转账记录'] = _buildTransactionRows(
            transactions.where((tx) => tx.t.type == 'transfer').toList(),
            accountMap,
          );
        }
        if (exportInvestPnl) {
          exportSheets['理财盈亏'] = _buildTransactionRows(
            transactions
                .where((tx) =>
                    tx.t.type == 'invest_gain' || tx.t.type == 'invest_loss')
                .toList(),
            accountMap,
          );
        }
      }

      final fileName = 'beecount_export_$ts.xlsx';
      final fileBytes = _buildXlsxBytes(exportSheets);
      const allowedExtensions = ['xlsx'];

      final path = await _saveFile(
        fileName: fileName,
        bytes: fileBytes,
        allowedExtensions: allowedExtensions,
        directory: directory,
      );
      if (path == null) {
        if (!mounted) return;
        setState(() {
          exporting = false;
          progress = 0;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        savedPath = path;
        exporting = false;
        progress = 1;
      });
      final l10nDialog = AppLocalizations.of(context);
      if (shareAfter) {
        // 触发分享面板
        await Share.shareXFiles([XFile(path)],
            text: l10nDialog.exportShareText);
        if (!mounted) return;
        await AppDialog.info(context,
            title: l10nDialog.exportSuccessTitle,
            message: l10nDialog.exportSuccessMessageIOS(path));
      } else {
        await AppDialog.info(context,
            title: l10nDialog.exportSuccessTitle,
            message: l10nDialog.exportSuccessMessageAndroid(path));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => exporting = false);
      final l10nError = AppLocalizations.of(context);
      await AppDialog.error(context,
          title: l10nError.exportFailedTitle, message: e.toString());
    }
  }

  Future<({List<Receivable> list, Map<int, double> outstandingById})>
      _loadReceivableListData({
    required BaseRepository repo,
    required List<Account> accounts,
  }) async {
    final byId = <int, Receivable>{};
    final outstandingById = <int, double>{};
    for (final account in accounts) {
      final list = await repo.getReceivablesByAccountId(account.id);
      for (final item in list) {
        byId[item.id] = item;
      }
      final outstanding =
          await repo.getReceivableOutstandingMapForAccount(account.id);
      outstandingById.addAll(outstanding);
    }
    final result = byId.values.toList()
      ..sort((a, b) {
        final name = a.borrowerName.compareTo(b.borrowerName);
        if (name != 0) return name;
        return b.borrowDate.compareTo(a.borrowDate);
      });
    return (list: result, outstandingById: outstandingById);
  }

  Future<({List<Payable> list, Map<int, double> outstandingById})>
      _loadPayableListData({
    required BaseRepository repo,
    required List<Account> accounts,
  }) async {
    final byId = <int, Payable>{};
    final outstandingById = <int, double>{};
    for (final account in accounts) {
      final list = await repo.getPayablesByAccountId(account.id);
      for (final item in list) {
        byId[item.id] = item;
      }
      final outstanding =
          await repo.getPayableOutstandingMapForAccount(account.id);
      outstandingById.addAll(outstanding);
    }
    final result = byId.values.toList()
      ..sort((a, b) {
        final name = a.payeeName.compareTo(b.payeeName);
        if (name != 0) return name;
        return b.payDate.compareTo(a.payDate);
      });
    return (list: result, outstandingById: outstandingById);
  }

  List<List<dynamic>> _buildTransactionRows(
    List<({Transaction t, Category? category})> transactions,
    Map<int, Account> accountMap,
  ) {
    final totalAmount =
        transactions.fold<double>(0.0, (sum, tx) => sum + tx.t.amount);
    return [
      ['交易ID', '时间', '类型', '金额', '分类', '账户', '转入账户', '备注'],
      for (final tx in transactions)
        [
          tx.t.id,
          _formatDateTime(tx.t.happenedAt),
          _transactionTypeLabel(tx.t.type),
          tx.t.amount.toStringAsFixed(2),
          _categoryLabel(tx.category),
          tx.t.accountId == null ? '' : accountMap[tx.t.accountId]?.name ?? '',
          tx.t.toAccountId == null
              ? ''
              : accountMap[tx.t.toAccountId]?.name ?? '',
          tx.t.note ?? '',
        ],
      ['', '', '合计', totalAmount.toStringAsFixed(2), '', '', '', ''],
    ];
  }

  List<List<dynamic>> _buildReceivableListRows(List<Receivable> receivables,
      Map<int, double> outstandingById, Map<int, Account> accountMap,
      {required bool includeReceived}) {
    final rows = <List<dynamic>>[
      ['借款人/出借人', 'ID', '应收账户', '借款日期', '应收金额', '已收回', '未收回', '状态', '备注'],
    ];
    var grandAmount = 0.0;
    var grandReceived = 0.0;
    var grandOutstanding = 0.0;
    String? currentBorrower;
    var groupAmount = 0.0;
    var groupReceived = 0.0;
    var groupOutstanding = 0.0;

    void closeGroupIfNeeded() {
      if (currentBorrower == null) return;
      rows.add([
        '',
        '合计',
        '',
        '',
        groupAmount.toStringAsFixed(2),
        groupReceived.toStringAsFixed(2),
        groupOutstanding.toStringAsFixed(2),
        '',
        '',
      ]);
      rows.add(List.filled(9, ''));
      groupAmount = 0.0;
      groupReceived = 0.0;
      groupOutstanding = 0.0;
    }

    for (final item in receivables) {
      final outstanding =
          outstandingById[item.id] ?? (item.isReceived ? 0.0 : item.amount);
      if (!includeReceived && outstanding <= 0.000001) continue;
      final received = item.amount - outstanding;

      if (currentBorrower != item.borrowerName) {
        closeGroupIfNeeded();
        currentBorrower = item.borrowerName;
        rows.add(['借款人：$currentBorrower', '', '', '', '', '', '', '', '']);
      }
      rows.add([
        '',
        item.id,
        accountMap[item.accountId]?.name ?? '',
        _formatDate(item.borrowDate),
        item.amount.toStringAsFixed(2),
        received.toStringAsFixed(2),
        outstanding.toStringAsFixed(2),
        outstanding <= 0.000001 ? '已收回' : '未收回',
        item.note ?? '',
      ]);
      groupAmount += item.amount;
      groupReceived += received;
      groupOutstanding += outstanding;
      grandAmount += item.amount;
      grandReceived += received;
      grandOutstanding += outstanding;
    }
    closeGroupIfNeeded();
    rows.add([
      '',
      '合计',
      '',
      '',
      grandAmount.toStringAsFixed(2),
      grandReceived.toStringAsFixed(2),
      grandOutstanding.toStringAsFixed(2),
      '',
      '',
    ]);
    return rows;
  }

  List<List<dynamic>> _buildPayableListRows(List<Payable> payables,
      Map<int, double> outstandingById, Map<int, Account> accountMap,
      {required bool includePaid}) {
    final rows = <List<dynamic>>[
      ['借款人/出借人', 'ID', '应付账户', '应付日期', '应付金额', '已还款', '未还款', '状态', '备注'],
    ];
    var grandAmount = 0.0;
    var grandPaid = 0.0;
    var grandOutstanding = 0.0;
    String? currentPayee;
    var groupAmount = 0.0;
    var groupPaid = 0.0;
    var groupOutstanding = 0.0;

    void closeGroupIfNeeded() {
      if (currentPayee == null) return;
      rows.add([
        '',
        '合计',
        '',
        '',
        groupAmount.toStringAsFixed(2),
        groupPaid.toStringAsFixed(2),
        groupOutstanding.toStringAsFixed(2),
        '',
        '',
      ]);
      rows.add(List.filled(9, ''));
      groupAmount = 0.0;
      groupPaid = 0.0;
      groupOutstanding = 0.0;
    }

    for (final item in payables) {
      final outstanding =
          outstandingById[item.id] ?? (item.isPaid ? 0.0 : item.amount);
      if (!includePaid && outstanding <= 0.000001) continue;
      final paid = item.amount - outstanding;

      if (currentPayee != item.payeeName) {
        closeGroupIfNeeded();
        currentPayee = item.payeeName;
        rows.add(['出借人：$currentPayee', '', '', '', '', '', '', '', '']);
      }
      rows.add([
        '',
        item.id,
        accountMap[item.accountId]?.name ?? '',
        _formatDate(item.payDate),
        item.amount.toStringAsFixed(2),
        paid.toStringAsFixed(2),
        outstanding.toStringAsFixed(2),
        outstanding <= 0.000001 ? '已还款' : '未还款',
        item.note ?? '',
      ]);
      groupAmount += item.amount;
      groupPaid += paid;
      groupOutstanding += outstanding;
      grandAmount += item.amount;
      grandPaid += paid;
      grandOutstanding += outstanding;
    }
    closeGroupIfNeeded();
    rows.add([
      '',
      '合计',
      '',
      '',
      grandAmount.toStringAsFixed(2),
      grandPaid.toStringAsFixed(2),
      grandOutstanding.toStringAsFixed(2),
      '',
      '',
    ]);
    return rows;
  }

  Future<List<List<dynamic>>> _buildAccountRows(
    BaseRepository repo,
    List<Account> accounts,
    List<Transaction> allLedgerTransactions,
    DateTime startDate,
    DateTime endDate,
  ) async {
    var totalStart = 0.0;
    var totalEnd = 0.0;
    final rows = <List<dynamic>>[
      ['账户ID', '名称', '类型', '币种', '初始金额', '末期金额', '余额变动'],
    ];
    for (final account in accounts) {
      final startAmount = await _computeAccountAmountAtDate(
        repo: repo,
        account: account,
        date: startDate,
        allLedgerTransactions: allLedgerTransactions,
      );
      final endAmount = await _computeAccountAmountAtDate(
        repo: repo,
        account: account,
        date: endDate,
        allLedgerTransactions: allLedgerTransactions,
      );
      final delta = endAmount - startAmount;
      totalStart += startAmount;
      totalEnd += endAmount;
      rows.add([
        account.id,
        account.name,
        _accountTypeLabel(account.type),
        account.currency,
        startAmount.toStringAsFixed(2),
        endAmount.toStringAsFixed(2),
        delta.toStringAsFixed(2),
      ]);
    }
    rows.add([
      '',
      '合计',
      '',
      '',
      totalStart.toStringAsFixed(2),
      totalEnd.toStringAsFixed(2),
      (totalEnd - totalStart).toStringAsFixed(2),
    ]);
    return rows;
  }

  Future<List<List<dynamic>>> _buildCategorySummaryRows({
    required BaseRepository repo,
    required List<({Transaction t, Category? category})> transactions,
    required DateTime start,
    required DateTime end,
  }) async {
    final incomeCategories = await repo.getTopLevelCategories('income');
    final expenseCategories = await repo.getTopLevelCategories('expense');
    final allCategories = <int, Category>{};
    for (final cat in [...incomeCategories, ...expenseCategories]) {
      allCategories[cat.id] = cat;
      final subs = await repo.getSubCategories(cat.id);
      for (final sub in subs) {
        allCategories[sub.id] = sub;
      }
    }

    final incomeByCategory = <String, double>{};
    final expenseByCategory = <String, double>{};
    var transferTotal = 0.0;

    for (final txWithCat in transactions) {
      final t = txWithCat.t;
      final c = txWithCat.category;
      if (t.type == 'income' || t.type == 'expense') {
        String categoryName = '';
        if (c != null) {
          if (c.level == 2 && c.parentId != null) {
            final parentCategory = allCategories[c.parentId];
            categoryName =
                CategoryUtils.getDisplayName(parentCategory?.name, context);
          } else {
            categoryName = CategoryUtils.getDisplayName(c.name, context);
          }
        }
        if (categoryName.isNotEmpty) {
          if (t.type == 'income') {
            incomeByCategory[categoryName] =
                (incomeByCategory[categoryName] ?? 0) + t.amount;
          } else {
            expenseByCategory[categoryName] =
                (expenseByCategory[categoryName] ?? 0) + t.amount;
          }
        }
      } else if (t.type == 'transfer') {
        transferTotal += t.amount;
      }
    }

    final dateRangeStr =
        '${start.year}.${start.month.toString().padLeft(2, '0')}.${start.day.toString().padLeft(2, '0')}-${end.year}.${end.month.toString().padLeft(2, '0')}.${end.day.toString().padLeft(2, '0')}';
    final rows = <List<dynamic>>[
      ['周期', dateRangeStr, '', ''],
      ['', '', '', ''],
    ];

    _appendSummarySection(
      rows: rows,
      title: '收入',
      valuesByCategory: incomeByCategory,
      differenceFormula: (actual, budget) => actual - budget,
    );
    _appendSummarySection(
      rows: rows,
      title: '支出',
      valuesByCategory: expenseByCategory,
      differenceFormula: (actual, budget) => budget - actual,
    );
    _appendSummarySection(
      rows: rows,
      title: '转账',
      valuesByCategory: {
        AppLocalizations.of(context).exportTypeTransfer: transferTotal
      },
      differenceFormula: (actual, budget) => actual - budget,
    );

    return rows;
  }

  void _appendSummarySection({
    required List<List<dynamic>> rows,
    required String title,
    required Map<String, double> valuesByCategory,
    required double Function(double actual, double budget) differenceFormula,
  }) {
    rows.add([title, '', '', '']);
    rows.add(['分类', '预算金额', '实际金额', '差额']);
    for (final entry in valuesByCategory.entries) {
      final budget = 0.0;
      final actual = entry.value;
      rows.add([
        entry.key,
        budget.toStringAsFixed(2),
        actual.toStringAsFixed(2),
        differenceFormula(actual, budget).toStringAsFixed(2),
      ]);
    }
    final totalActual =
        valuesByCategory.values.fold(0.0, (sum, amount) => sum + amount);
    final totalBudget = 0.0;
    rows.add([
      '合计',
      totalBudget.toStringAsFixed(2),
      totalActual.toStringAsFixed(2),
      differenceFormula(totalActual, totalBudget).toStringAsFixed(2),
    ]);
    rows.add(['', '', '', '']);
  }

  Future<double> _computeAccountAmountAtDate({
    required BaseRepository repo,
    required Account account,
    required DateTime date,
    required List<Transaction> allLedgerTransactions,
  }) async {
    final endOfDate =
        DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    if (account.type == 'receivable') {
      final receivables = await repo.getReceivablesByAccountId(account.id);
      var outstandingSum = 0.0;
      for (final receivable in receivables) {
        if (receivable.borrowDate.toLocal().isAfter(endOfDate)) continue;
        final payments = await repo.getReceivablePayments(receivable.id);
        final paidPrincipal = payments
            .where((p) => !p.happenedAt.toLocal().isAfter(endOfDate))
            .fold<double>(0.0, (sum, p) => sum + p.amount);
        final outstanding = receivable.amount - paidPrincipal;
        if (outstanding > 0) {
          outstandingSum += outstanding;
        }
      }
      return outstandingSum;
    }

    if (account.type == 'payable') {
      final payables = await repo.getPayablesByAccountId(account.id);
      var outstandingSum = 0.0;
      for (final payable in payables) {
        if (payable.payDate.toLocal().isAfter(endOfDate)) continue;
        final payments = await repo.getPayablePayments(payable.id);
        final paidPrincipal = payments
            .where((p) => !p.happenedAt.toLocal().isAfter(endOfDate))
            .fold<double>(0.0, (sum, p) => sum + p.amount);
        final outstanding = payable.amount - paidPrincipal;
        if (outstanding > 0) {
          outstandingSum += outstanding;
        }
      }
      return -outstandingSum;
    }

    var amount = account.initialBalance;
    for (final tx in allLedgerTransactions) {
      if (tx.happenedAt.toLocal().isAfter(endOfDate)) continue;
      if (tx.accountId == account.id) {
        if (tx.type == 'income') {
          amount += tx.amount;
        } else if (tx.type == 'expense' || tx.type == 'transfer') {
          amount -= tx.amount;
        }
      } else if (tx.toAccountId == account.id && tx.type == 'transfer') {
        amount += tx.amount;
      }
    }
    return amount;
  }

  Uint8List _buildXlsxBytes(Map<String, List<List<dynamic>>> sheets) {
    final excel = xls.Excel.createExcel();
    final thinBorder = xls.Border(borderStyle: xls.BorderStyle.Thin);
    final borderedStyle = xls.CellStyle(
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    final totalRowStyle = xls.CellStyle(
      backgroundColorHex: xls.ExcelColor.fromHexString('#FCF7B6'),
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    final groupRowStyle = xls.CellStyle(
      backgroundColorHex: xls.ExcelColor.fromHexString('#D13707'),
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );
    var firstSheet = true;
    for (final entry in sheets.entries) {
      final sheet = excel[entry.key];
      for (var rowIndex = 0; rowIndex < entry.value.length; rowIndex++) {
        final row = entry.value[rowIndex];
        sheet.appendRow(row.map(_toExcelCellValue).toList());
        final isTotalRow = row.any((cell) => cell?.toString() == '合计');
        final first = row.isNotEmpty ? (row.first?.toString() ?? '') : '';
        final isGroupRow = first.startsWith('借款人：') || first.startsWith('出借人：');
        final hasAnyContent =
            row.any((cell) => (cell?.toString() ?? '').isNotEmpty);
        if (isTotalRow || isGroupRow || hasAnyContent) {
          // 有效数据行整行加边框；合计行整行加底色+边框。
          for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
            final cell = sheet.cell(
              xls.CellIndex.indexByColumnRow(
                rowIndex: rowIndex,
                columnIndex: columnIndex,
              ),
            );
            if (isTotalRow) {
              cell.cellStyle = totalRowStyle;
            } else if (isGroupRow) {
              cell.cellStyle = groupRowStyle;
            } else {
              cell.cellStyle = borderedStyle;
            }
          }
        }
      }
      if (firstSheet && entry.key != 'Sheet1') {
        excel.delete('Sheet1');
      }
      firstSheet = false;
    }
    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('生成 Excel 文件失败');
    }
    return Uint8List.fromList(bytes);
  }

  xls.CellValue? _toExcelCellValue(dynamic value) {
    if (value == null) return null;
    if (value is int) return xls.IntCellValue(value);
    if (value is double) return xls.DoubleCellValue(value);
    if (value is bool) return xls.BoolCellValue(value);
    return xls.TextCellValue(value.toString());
  }

  Future<String?> _saveFile({
    required String fileName,
    required Uint8List bytes,
    required List<String> allowedExtensions,
    required String? directory,
  }) async {
    if (Platform.isAndroid) {
      return FilePicker.platform.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
      );
    }

    final path = p.join(directory!, fileName);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  String _categoryLabel(Category? category) {
    if (category == null) return '';
    return CategoryUtils.getDisplayName(category.name, context);
  }

  String _transactionTypeLabel(String type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case 'income':
        return l10n.exportTypeIncome;
      case 'expense':
        return l10n.exportTypeExpense;
      case 'transfer':
        return l10n.exportTypeTransfer;
      case 'invest_gain':
      case 'invest_loss':
        return l10n.exportTypeInvestPnl;
      default:
        return type;
    }
  }

  String _accountTypeLabel(String type) {
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
      case 'investment':
        return l10n.accountTypeInvestment;
      case 'receivable':
        return '应收款';
      case 'payable':
        return '应付款';
      case 'other':
        return l10n.accountTypeOther;
      default:
        return type;
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime.toLocal());
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    return DateFormat('yyyy-MM-dd').format(dateTime.toLocal());
  }

  void _setCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      startDate = DateTime(now.year, now.month, 1);
      endDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _setCurrentYear() {
    final now = DateTime.now();
    setState(() {
      startDate = DateTime(now.year, 1, 1);
      endDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _setPreviousMonth() {
    final now = DateTime.now();
    final firstDayOfThisMonth = DateTime(now.year, now.month, 1);
    final firstDayOfLastMonth =
        DateTime(firstDayOfThisMonth.year, firstDayOfThisMonth.month - 1, 1);
    final lastDayOfLastMonth =
        DateTime(firstDayOfThisMonth.year, firstDayOfThisMonth.month, 0);
    setState(() {
      startDate = firstDayOfLastMonth;
      endDate = lastDayOfLastMonth;
    });
  }
}
