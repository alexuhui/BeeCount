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
  bool exportAccounts = true;
  bool exportReceivables = true;
  bool exportPayables = true;
  bool exportReceivablePayments = true;
  bool exportPayablePayments = true;

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
    return Scaffold(
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
                              value: exportReceivables,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(
                                      () => exportReceivables = value ?? false),
                              title: const Text('应收款'),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportPayables,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(
                                      () => exportPayables = value ?? false),
                              title: const Text('应付款'),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportReceivablePayments,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(() =>
                                      exportReceivablePayments =
                                          value ?? false),
                              title: const Text('应收款记录'),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            CheckboxListTile(
                              value: exportPayablePayments,
                              onChanged: exporting
                                  ? null
                                  : (value) => setState(() =>
                                      exportPayablePayments = value ?? false),
                              title: const Text('应付款记录'),
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
      };
      final shouldExportReceivableData = exportReceivables ||
          exportPayables ||
          exportReceivablePayments ||
          exportPayablePayments;
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

      final receivables = shouldExportReceivableData
          ? await _loadReceivables(
              repo: repo,
              accounts: accountsForReceivable,
              start: start,
              end: end,
            )
          : <Receivable>[];
      final payables = shouldExportReceivableData
          ? await _loadPayables(
              repo: repo,
              accounts: accountsForReceivable,
              start: start,
              end: end,
            )
          : <Payable>[];

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
          accountsForExport,
          allTransactionsWithCategory.map((e) => e.t).toList(),
          start,
          end,
        );
      }
      if (exportReceivables) {
        exportSheets['应收款'] = _buildReceivableRows(receivables, accountMap);
      }
      if (exportPayables) {
        exportSheets['应付款'] = _buildPayableRows(payables, accountMap);
      }
      if (exportReceivablePayments) {
        exportSheets['应收款记录'] = await _buildReceivablePaymentRows(
          repo: repo,
          receivables: receivables,
          accountMap: accountMap,
          start: start,
          end: end,
        );
      }
      if (exportPayablePayments) {
        exportSheets['应付款记录'] = await _buildPayablePaymentRows(
          repo: repo,
          payables: payables,
          accountMap: accountMap,
          start: start,
          end: end,
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

  Future<List<Receivable>> _loadReceivables({
    required BaseRepository repo,
    required List<Account> accounts,
    required DateTime start,
    required DateTime end,
  }) async {
    final byId = <int, Receivable>{};
    for (final account in accounts) {
      final list = await repo.getReceivablesByAccountId(account.id);
      for (final item in list) {
        if (_isInRange(item.borrowDate, start, end)) {
          byId[item.id] = item;
        }
      }
    }
    final result = byId.values.toList()
      ..sort((a, b) => b.borrowDate.compareTo(a.borrowDate));
    return result;
  }

  Future<List<Payable>> _loadPayables({
    required BaseRepository repo,
    required List<Account> accounts,
    required DateTime start,
    required DateTime end,
  }) async {
    final byId = <int, Payable>{};
    for (final account in accounts) {
      final list = await repo.getPayablesByAccountId(account.id);
      for (final item in list) {
        if (_isInRange(item.payDate, start, end)) {
          byId[item.id] = item;
        }
      }
    }
    final result = byId.values.toList()
      ..sort((a, b) => b.payDate.compareTo(a.payDate));
    return result;
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

  List<List<dynamic>> _buildReceivableRows(
    List<Receivable> receivables,
    Map<int, Account> accountMap,
  ) {
    final totalAmount =
        receivables.fold<double>(0.0, (sum, item) => sum + item.amount);
    return [
      [
        'ID',
        '应收账户',
        '借款人',
        '金额',
        '借款日期',
        '借款账户',
        '是否已收款',
        '收款日期',
        '收款账户',
        '备注'
      ],
      for (final item in receivables)
        [
          item.id,
          accountMap[item.accountId]?.name ?? '',
          item.borrowerName,
          item.amount.toStringAsFixed(2),
          _formatDate(item.borrowDate),
          item.fromAccountId == null
              ? ''
              : accountMap[item.fromAccountId!]?.name ?? '',
          item.isReceived ? '是' : '否',
          _formatDate(item.receiveDate),
          item.toAccountId == null
              ? ''
              : accountMap[item.toAccountId!]?.name ?? '',
          item.note ?? '',
        ],
      ['', '', '合计', totalAmount.toStringAsFixed(2), '', '', '', '', '', ''],
    ];
  }

  List<List<dynamic>> _buildPayableRows(
    List<Payable> payables,
    Map<int, Account> accountMap,
  ) {
    final totalAmount =
        payables.fold<double>(0.0, (sum, item) => sum + item.amount);
    return [
      [
        'ID',
        '应付账户',
        '收款人',
        '金额',
        '应付日期',
        '入账账户',
        '是否已还款',
        '还款日期',
        '还款账户',
        '备注'
      ],
      for (final item in payables)
        [
          item.id,
          accountMap[item.accountId]?.name ?? '',
          item.payeeName,
          item.amount.toStringAsFixed(2),
          _formatDate(item.payDate),
          item.toAccountId == null
              ? ''
              : accountMap[item.toAccountId!]?.name ?? '',
          item.isPaid ? '是' : '否',
          _formatDate(item.paidDate),
          item.fromAccountId == null
              ? ''
              : accountMap[item.fromAccountId!]?.name ?? '',
          item.note ?? '',
        ],
      ['', '', '合计', totalAmount.toStringAsFixed(2), '', '', '', '', '', ''],
    ];
  }

  Future<List<List<dynamic>>> _buildReceivablePaymentRows({
    required BaseRepository repo,
    required List<Receivable> receivables,
    required Map<int, Account> accountMap,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = <List<dynamic>>[
      ['ID', '应收款ID', '借款人', '本金', '利息', '收款日期', '收款账户', '备注'],
    ];
    var totalPrincipal = 0.0;
    var totalInterest = 0.0;
    for (final receivable in receivables) {
      final payments = await repo.getReceivablePayments(receivable.id);
      for (final payment in payments) {
        if (!_isInRange(payment.happenedAt, start, end)) continue;
        totalPrincipal += payment.amount;
        totalInterest += payment.interestAmount;
        rows.add([
          payment.id,
          payment.receivableId,
          receivable.borrowerName,
          payment.amount.toStringAsFixed(2),
          payment.interestAmount.toStringAsFixed(2),
          _formatDate(payment.happenedAt),
          payment.accountId == null
              ? ''
              : accountMap[payment.accountId!]?.name ?? '',
          payment.note ?? '',
        ]);
      }
    }
    rows.add([
      '',
      '',
      '合计',
      totalPrincipal.toStringAsFixed(2),
      totalInterest.toStringAsFixed(2),
      '',
      '',
      '',
    ]);
    return rows;
  }

  Future<List<List<dynamic>>> _buildPayablePaymentRows({
    required BaseRepository repo,
    required List<Payable> payables,
    required Map<int, Account> accountMap,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = <List<dynamic>>[
      ['ID', '应付款ID', '收款人', '本金', '利息', '还款日期', '还款账户', '备注'],
    ];
    var totalPrincipal = 0.0;
    var totalInterest = 0.0;
    for (final payable in payables) {
      final payments = await repo.getPayablePayments(payable.id);
      for (final payment in payments) {
        if (!_isInRange(payment.happenedAt, start, end)) continue;
        totalPrincipal += payment.amount;
        totalInterest += payment.interestAmount;
        rows.add([
          payment.id,
          payment.payableId,
          payable.payeeName,
          payment.amount.toStringAsFixed(2),
          payment.interestAmount.toStringAsFixed(2),
          _formatDate(payment.happenedAt),
          payment.accountId == null
              ? ''
              : accountMap[payment.accountId!]?.name ?? '',
          payment.note ?? '',
        ]);
      }
    }
    rows.add([
      '',
      '',
      '合计',
      totalPrincipal.toStringAsFixed(2),
      totalInterest.toStringAsFixed(2),
      '',
      '',
      '',
    ]);
    return rows;
  }

  Future<List<List<dynamic>>> _buildAccountRows(
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
      final startAmount = _computeAccountAmountAtDate(
        account: account,
        date: startDate,
        allLedgerTransactions: allLedgerTransactions,
      );
      final endAmount = _computeAccountAmountAtDate(
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

  double _computeAccountAmountAtDate({
    required Account account,
    required DateTime date,
    required List<Transaction> allLedgerTransactions,
  }) {
    var amount = account.initialBalance;
    final endOfDate =
        DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
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
    var firstSheet = true;
    for (final entry in sheets.entries) {
      final sheet = excel[entry.key];
      for (var rowIndex = 0; rowIndex < entry.value.length; rowIndex++) {
        final row = entry.value[rowIndex];
        sheet.appendRow(row.map(_toExcelCellValue).toList());
        final isTotalRow = row.any((cell) => cell?.toString() == '合计');
        final hasAnyContent =
            row.any((cell) => (cell?.toString() ?? '').isNotEmpty);
        if (isTotalRow || hasAnyContent) {
          // 有效数据行整行加边框；合计行整行加底色+边框。
          for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
            final cell = sheet.cell(
              xls.CellIndex.indexByColumnRow(
                rowIndex: rowIndex,
                columnIndex: columnIndex,
              ),
            );
            cell.cellStyle = isTotalRow ? totalRowStyle : borderedStyle;
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

  bool _isInRange(DateTime dateTime, DateTime start, DateTime end) {
    final d = dateTime.toLocal();
    return d.isAfter(start.subtract(const Duration(days: 1))) &&
        d.isBefore(end.add(const Duration(days: 1)));
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
