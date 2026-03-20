import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
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
import '../../widgets/ui/wheel_date_picker.dart';

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.exportDescription),
                  const SizedBox(height: 16),
                  // 日期范围选择
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('日期范围'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('开始日期'),
                                    const SizedBox(height: 8),
                                    FilledButton(
                                      onPressed: () async {
                                        final date = await showWheelDatePicker(
                                          context,
                                          initial: startDate ?? DateTime(DateTime.now().year, 1, 1),
                                          minDate: DateTime(2000, 1, 1),
                                          maxDate: DateTime.now(),
                                        );
                                        if (date != null) {
                                          setState(() => startDate = date);
                                        }
                                      },
                                      child: Text(startDate != null 
                                        ? DateFormat('yyyy-MM-dd').format(startDate!)
                                        : '选择开始日期'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('结束日期'),
                                    const SizedBox(height: 8),
                                    FilledButton(
                                      onPressed: () async {
                                        final date = await showWheelDatePicker(
                                          context,
                                          initial: endDate ?? DateTime.now(),
                                          minDate: startDate ?? DateTime(2000, 1, 1),
                                          maxDate: DateTime.now(),
                                        );
                                        if (date != null) {
                                          setState(() => endDate = date);
                                        }
                                      },
                                      child: Text(endDate != null 
                                        ? DateFormat('yyyy-MM-dd').format(endDate!)
                                        : '选择结束日期'),
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
                  FilledButton.icon(
                    onPressed: exporting ? null : () => _export(repo, ledgerId),
                    icon: const Icon(Icons.save_alt_outlined),
                    label: Text(Platform.isIOS ? l10n.exportButtonIOS : l10n.exportButtonAndroid),
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
          )
        ],
      ),
    );
  }

  Future<void> _export(BaseRepository repo, int ledgerId) async {
    try {
      setState(() {
        exporting = true;
        progress = 0;
        savedPath = null;
      });
      String directory;
      bool shareAfter = false;
      if (Platform.isIOS) {
        // iOS: 写入应用文档目录，然后使用系统分享
        final docDir = await getApplicationDocumentsDirectory();
        directory = docDir.path;
        shareAfter = true;
      } else if (Platform.isAndroid) {
        // Android: 直接保存到公共 Download/BeeCount 目录
        const downloadPath = '/storage/emulated/0/Download/BeeCount';
        final dir = Directory(downloadPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        directory = downloadPath;
      } else if (Platform.isWindows) {
        // Windows: 下载目录， 
        final docDir = await getDownloadsDirectory();
        directory = docDir?.path ?? '';
        if (directory.isEmpty) {
          showToast(context, '无法获取下载目录');
          return;
        }
      } else {
        // 其他平台: 不支持导出
        showToast(context, '不支持在${Platform.operatingSystem}上导出数据');
        return;
      }

      // 设置默认日期范围（如果未选择）
      final start = startDate ?? DateTime(DateTime.now().year, 1, 1);
      final end = endDate ?? DateTime.now();
      final l10n = AppLocalizations.of(context);

      // 生成日期范围字符串
      final dateRangeStr = '${start.year}.${start.month.toString().padLeft(2, '0')}.${start.day.toString().padLeft(2, '0')}-${end.year}.${end.month.toString().padLeft(2, '0')}.${end.day.toString().padLeft(2, '0')}';

      // 获取交易和分类数据
      final transactionsWithCategory = await repo.transactionsWithCategoryAll(ledgerId: ledgerId).first;
      
      // 过滤日期范围内的交易
      final filteredTransactions = transactionsWithCategory.where((tx) {
        final txDate = tx.t.happenedAt.toLocal();
        return txDate.isAfter(start.subtract(const Duration(days: 1))) && 
               txDate.isBefore(end.add(const Duration(days: 1)));
      }).toList();

      // 按一级分类分组统计收入和支出
      final incomeByCategory = <String, double>{};
      final expenseByCategory = <String, double>{};

      // 缓存所有分类信息（包括父分类）
      final incomeCategories = await repo.getTopLevelCategories('income');
      final expenseCategories = await repo.getTopLevelCategories('expense');
      final allCategories = <int, Category>{};
      for (final cat in [...incomeCategories, ...expenseCategories]) {
        allCategories[cat.id] = cat;
        // 获取子分类
        final subCategories = await repo.getSubCategories(cat.id);
        for (final subCat in subCategories) {
          allCategories[subCat.id] = subCat;
        }
      }

      // 统计收入和支出
      for (final txWithCat in filteredTransactions) {
        final t = txWithCat.t;
        final c = txWithCat.category;
        
        if (t.type == 'income' || t.type == 'expense') {
          String categoryName = '';
          if (c != null) {
            if (c.level == 2 && c.parentId != null) {
              // 二级分类：使用一级分类名称
              final parentCategory = allCategories[c.parentId];
              categoryName = CategoryUtils.getDisplayName(parentCategory?.name, context);
            } else {
              // 一级分类：使用当前分类名称
              categoryName = CategoryUtils.getDisplayName(c.name, context);
            }
          }
          
          if (categoryName.isNotEmpty) {
            if (t.type == 'income') {
              incomeByCategory[categoryName] = (incomeByCategory[categoryName] ?? 0) + t.amount;
            } else {
              expenseByCategory[categoryName] = (expenseByCategory[categoryName] ?? 0) + t.amount;
            }
          }
        }
      }

      // 获取预算数据
      final categoryBudgets = <String, double>{};
      
      // 获取日期范围内每个月的预算
      for (int year = start.year; year <= end.year; year++) {
        int startMonth = year == start.year ? start.month : 1;
        int endMonth = year == end.year ? end.month : 12;
        
        for (int month = startMonth; month <= endMonth; month++) {
          final monthBudgets = await repo.getCategoryBudgetsByMonth(ledgerId, year, month);
          for (final budget in monthBudgets) {
            if (budget.categoryId != null) {
              final category = allCategories[budget.categoryId!];
              if (category != null) {
                String categoryName = CategoryUtils.getDisplayName(category.name, context);
                categoryBudgets[categoryName] = (categoryBudgets[categoryName] ?? 0) + budget.amount;
              }
            }
          }
        }
      }

      // 生成 CSV 数据
      final rows = <List<dynamic>>[];
      
      // 添加周期标题
      rows.add(['周期 $dateRangeStr']);
      rows.add([]);
      
      // 收入部分
      rows.add(['收入', '预算金额', '实际金额', '差额']);
      for (final entry in incomeByCategory.entries) {
        final category = entry.key;
        final actual = entry.value;
        final budget = categoryBudgets[category] ?? 0.0;
        final difference = actual - budget;
        rows.add([category, budget.toStringAsFixed(2), actual.toStringAsFixed(2), difference.toStringAsFixed(2)]);
      }
      // 添加收入合计
      final totalIncome = incomeByCategory.values.fold(0.0, (sum, amount) => sum + amount);
      final totalIncomeBudget = incomeByCategory.keys.fold(0.0, (sum, category) => sum + (categoryBudgets[category] ?? 0.0));
      final totalIncomeDiff = totalIncome - totalIncomeBudget;
      rows.add(['合计', totalIncomeBudget.toStringAsFixed(2), totalIncome.toStringAsFixed(2), totalIncomeDiff.toStringAsFixed(2)]);
      rows.add([]);
      
      // 支出部分
      rows.add(['支出', '预算金额', '实际金额', '差额']);
      for (final entry in expenseByCategory.entries) {
        final category = entry.key;
        final actual = entry.value;
        final budget = categoryBudgets[category] ?? 0.0;
        final difference = budget - actual;
        rows.add([category, budget.toStringAsFixed(2), actual.toStringAsFixed(2), difference.toStringAsFixed(2)]);
      }
      // 添加支出合计
      final totalExpense = expenseByCategory.values.fold(0.0, (sum, amount) => sum + amount);
      final totalExpenseBudget = expenseByCategory.keys.fold(0.0, (sum, category) => sum + (categoryBudgets[category] ?? 0.0));
      final totalExpenseDiff = totalExpenseBudget -totalExpense;
      rows.add(['合计', totalExpenseBudget.toStringAsFixed(2), totalExpense.toStringAsFixed(2), totalExpenseDiff.toStringAsFixed(2)]);

      final csvStr = const ListToCsvConverter(eol: '\n').convert(rows);
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final path = p.join(directory, 'beecount_budget_$ts.csv');
      
      // 添加UTF-8 BOM标记，确保Excel正确识别中文编码
      const utf8Bom = '\uFEFF';
      await File(path).writeAsString(utf8Bom + csvStr, encoding: Encoding.getByName('utf-8')!);
      setState(() {
        savedPath = path;
        exporting = false;
        progress = 1;
      });
      if (!mounted) return;
      final l10nDialog = AppLocalizations.of(context);
      if (shareAfter) {
        // 触发分享面板
        await Share.shareXFiles([XFile(path)], text: l10nDialog.exportShareText);
        await AppDialog.info(context,
            title: l10nDialog.exportSuccessTitle, message: l10nDialog.exportSuccessMessageIOS(path));
      } else {
        await AppDialog.info(context, title: l10nDialog.exportSuccessTitle, message: l10nDialog.exportSuccessMessageAndroid(path));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => exporting = false);
      final l10nError = AppLocalizations.of(context);
      await AppDialog.error(context, title: l10nError.exportFailedTitle, message: e.toString());
    }
  }

  /// 将英文类型转换为中文显示名称
  String _getTypeDisplayName(String type) {
    final l10nType = AppLocalizations.of(context);
    switch (type) {
      case 'income':
        return l10nType.exportTypeIncome;
      case 'expense':
        return l10nType.exportTypeExpense;
      case 'transfer':
        return l10nType.exportTypeTransfer;
      default:
        return type; // 兜底返回原始值
    }
  }
}
