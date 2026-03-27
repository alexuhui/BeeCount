import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/budget_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../services/data/category_service.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';

/// 预算编辑页面
class BudgetEditPage extends ConsumerStatefulWidget {
  final Budget? budget;
  final CategoryBudgetUsage? usage;
  final int year;
  final int month;
  final bool isYearlyMode;

  const BudgetEditPage({
    this.budget,
    this.usage,
    required this.year,
    required this.month,
    this.isYearlyMode = false,
    super.key,
  });

  @override
  ConsumerState<BudgetEditPage> createState() => _BudgetEditPageState();
}

class _BudgetEditPageState extends ConsumerState<BudgetEditPage> {
  final _amountController = TextEditingController();
  // late String _type;
  int? _selectedCategoryId;
  String? _selectedCategoryName;
  String? _selectedCategoryIcon;
  bool _isLoading = false;
  late int _selectedYear;
  /// 是否选中对应月份
  /// 0 表示整年，默认选中当前月份
  final List<bool> _selectedMonth = List.generate(13, (i) => false);

  bool get _isEditing => widget.budget != null || (widget.isYearlyMode && widget.usage != null);

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.year;
    // 如果是年度模式，默认选中整年及所有月份
    if (widget.isYearlyMode) {
      for (int i = 0; i <= 12; i++) {
        _selectedMonth[i] = true;
      }
    } else {
      _selectedMonth[widget.month] = true;
    }
    if (widget.budget != null) {
      _amountController.text = widget.budget!.amount.toStringAsFixed(0);
      _selectedCategoryId = widget.budget!.categoryId;
    }

    if(widget.usage != null){
      if( widget.budget == null){
        _amountController.text = widget.usage!.usage.used.toStringAsFixed(0);
        _selectedCategoryId = widget.usage!.categoryId;
      }
      _selectedCategoryName = widget.usage!.categoryName;
      _selectedCategoryIcon = widget.usage!.categoryIcon;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: _isEditing ? l10n.budgetEditTitle : l10n.budgetAddTitle,
            showBack: true,
            compact: true,
            actions: [
              if (widget.budget != null)
                IconButton(
                  onPressed: _deleteBudget,
                  icon: const Icon(Icons.delete_outline),
                ),
              TextButton(
                onPressed: _isLoading ? null : _saveBudget,
                child: Text(
                  l10n.commonSave,
                  style: TextStyle(
                    color: BeeTokens.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 8.0.scaled(context, ref),
              ),
              children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.budgetPeriodLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: BeeTokens.textSecondary(context),
                          ),
                        ),
                        SizedBox(height: 12.0.scaled(context, ref)),
                        _buildYearSelector(context),
                        SizedBox(height: 12.0.scaled(context, ref)),
                        _buildMonthSelector(context),
                        SizedBox(height: 12.0.scaled(context, ref)),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.0.scaled(context, ref)),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.budgetCategoryLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: BeeTokens.textSecondary(context),
                          ),
                        ),
                        SizedBox(height: 12.0.scaled(context, ref)),
                        _buildCategorySelector(context, l10n),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.0.scaled(context, ref)),
                // 预算金额
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.budgetAmountLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                      SizedBox(height: 12.0.scaled(context, ref)),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: BeeTokens.textPrimary(context),
                        ),
                        decoration: InputDecoration(
                          prefixText: '¥ ',
                          prefixStyle: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context),
                          ),
                          hintText: l10n.budgetAmountHint,
                          hintStyle: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            color: BeeTokens.textTertiary(context),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                // TODO: 起始日设置暂时隐藏，后期与周期开始日期一起调整
                // SizedBox(height: 12.0.scaled(context, ref)),
                // SectionCard(
                //   child: Column(
                //     crossAxisAlignment: CrossAxisAlignment.start,
                //     children: [
                //       Text(l10n.budgetStartDayLabel, ...),
                //       _buildStartDaySelector(context),
                //     ],
                //   ),
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Widget _buildTypeOption(
  //   BuildContext context,
  //   String label,
  //   String type,
  //   IconData icon, {
  //   bool disabled = false,
  // }) {
  //   // final isSelected = _type == type;
  //   final primary = Theme.of(context).colorScheme.primary;

  //   return InkWell(
  //     onTap: disabled ? null : () => setState(() => _type = type),
  //     borderRadius: BorderRadius.circular(12),
  //     child: Opacity(
  //       opacity: disabled ? 0.4 : 1.0,
  //       child: Container(
  //         padding: EdgeInsets.all(16.0.scaled(context, ref)),
  //         decoration: BoxDecoration(
  //           color: isSelected && !disabled
  //               ? primary.withValues(alpha: 0.1)
  //               : BeeTokens.surface(context),
  //           borderRadius: BorderRadius.circular(12),
  //           border: Border.all(
  //             color: isSelected && !disabled ? primary : BeeTokens.border(context),
  //             width: isSelected && !disabled ? 2 : 1,
  //           ),
  //         ),
  //         child: Column(
  //           children: [
  //             Icon(
  //               icon,
  //               size: 32.0.scaled(context, ref),
  //               color: isSelected && !disabled ? primary : BeeTokens.iconSecondary(context),
  //             ),
  //             SizedBox(height: 8.0.scaled(context, ref)),
  //             Text(
  //               label,
  //               style: TextStyle(
  //                 fontSize: 14,
  //                 fontWeight: isSelected && !disabled ? FontWeight.w600 : FontWeight.w400,
  //                 color: isSelected && !disabled ? primary : BeeTokens.textSecondary(context),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  Widget _buildCategorySelector(BuildContext context, AppLocalizations l10n) {
    final isDisabled = _isEditing;
    return InkWell(
      onTap: isDisabled ? null : _selectCategory,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.all(12.0.scaled(context, ref)),
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BeeTokens.border(context)),
        ),
        child: Row(
          children: [
            if (_selectedCategoryId != null) ...[
              Container(
                width: 36.0.scaled(context, ref),
                height: 36.0.scaled(context, ref),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  CategoryService.getCategoryIcon(_selectedCategoryIcon),
                  size: 20.0.scaled(context, ref),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(width: 12.0.scaled(context, ref)),
              Expanded(
                child: Text(
                  _selectedCategoryName ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
              ),
            ] else ...[
              Icon(
                Icons.add_circle_outline,
                size: 24.0.scaled(context, ref),
                color: BeeTokens.iconTertiary(context),
              ),
              SizedBox(width: 12.0.scaled(context, ref)),
              Expanded(
                child: Text(
                  l10n.budgetCategoryHint,
                  style: TextStyle(
                    fontSize: 16,
                    color: BeeTokens.textTertiary(context),
                  ),
                ),
              ),
            ],
            if (!isDisabled)
              Icon(
                Icons.chevron_right,
                color: BeeTokens.iconTertiary(context),
              ),
          ],
        ),
      ),
    );
  }

  /// 年份选择器，默认显示当前年份
  Widget _buildYearSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<int>(
      initialValue: _selectedYear,
      decoration: InputDecoration(
        labelText: l10n.selectYear,
        border: OutlineInputBorder(),
      ),
      items: List.generate(5, (index) {
        final year = DateTime.now().year + index;
        return DropdownMenuItem(
          value: year,
          child: Text(l10n.homeYear(year)),
        );
      }),
      onChanged: (value) => setState(() {if(value != null) _selectedYear = value;}),
    );
  }

  /// 月份选择器, 支持多选
  Widget _buildMonthSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [        
        Text(
          l10n.selectMonth,
          style: TextStyle(
            fontSize: 14,
          ),
        ),
        Wrap(
        spacing: 8.0.scaled(context, ref),
        runSpacing: 8.0.scaled(context, ref),
        children: List.generate(13, (index) {
          final primary = Theme.of(context).colorScheme.primary;
          final isAll = index == 0;
          final month = index;
          final isSelected = _selectedMonth[index];
          return InkWell(
            onTap: () => setState(() {
              if(isSelected) {
                // 取消全选
                if(isAll){              
                  for(int i = 0; i <= 12; i++){
                    _selectedMonth[i] = false;
                  }
                }else{
                  _selectedMonth[index] = false;
                }
              } else {
                // 全选
                if(isAll){
                  for(int i = 0; i <= 12; i++){
                    _selectedMonth[i] = true;
                  }
                }else{
                  _selectedMonth[index] = true;
                }
              }
            }),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40.0.scaled(context, ref),
              height: 40.0.scaled(context, ref),
              decoration: BoxDecoration(
                color: isSelected ? primary : BeeTokens.surface(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? primary : BeeTokens.border(context),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                isAll ? l10n.wholeYear : '$month',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : BeeTokens.textPrimary(context),
                ),
              ),
            ),
          );
        }),
        ) 
      ]); 
  }

  // TODO: 起始日选择器暂时隐藏，后期与周期开始日期一起调整
  // Widget _buildStartDaySelector(BuildContext context) {
  //   return Wrap(
  //     spacing: 8.0.scaled(context, ref),
  //     runSpacing: 8.0.scaled(context, ref),
  //     children: List.generate(28, (index) {
  //       final day = index + 1;
  //       final isSelected = _startDay == day;
  //       final primary = Theme.of(context).colorScheme.primary;
  //       return InkWell(
  //         onTap: () => setState(() => _startDay = day),
  //         borderRadius: BorderRadius.circular(8),
  //         child: Container(
  //           width: 40.0.scaled(context, ref),
  //           height: 40.0.scaled(context, ref),
  //           decoration: BoxDecoration(
  //             color: isSelected ? primary : BeeTokens.surface(context),
  //             borderRadius: BorderRadius.circular(8),
  //             border: Border.all(
  //               color: isSelected ? primary : BeeTokens.border(context),
  //             ),
  //           ),
  //           alignment: Alignment.center,
  //           child: Text(
  //             '$day',
  //             style: TextStyle(
  //               fontSize: 14,
  //               fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
  //               color: isSelected ? Colors.white : BeeTokens.textPrimary(context),
  //             ),
  //           ),
  //         ),
  //       );
  //     }),
  //   );
  // }

  Future<void> _selectCategory() async {
    final repo = ref.read(repositoryProvider);
    final categories = await repo.getAllCategories();

    // 只显示支出类父分类
    final expenseCategories = categories
        .where((c) => c.kind == 'expense' && c.parentId == null)
        .toList();

    if (!mounted) return;

    final selected = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context).budgetCategoryLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: expenseCategories.length,
                itemBuilder: (context, index) {
                  final category = expenseCategories[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        CategoryService.getCategoryIcon(category.icon),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(category.name),
                    trailing: _selectedCategoryId == category.id
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.pop(context, category),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedCategoryId = selected.id;
        _selectedCategoryName = selected.name;
        _selectedCategoryIcon = selected.icon;
      });
    }
  }

  Future<void> _saveBudget() async {
    final l10n = AppLocalizations.of(context);
    final amountText = _amountController.text.trim();

    if (amountText.isEmpty) {
      showToast(context, l10n.budgetAmountHint);
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      showToast(context, l10n.budgetAmountHint);
      return;
    }

    if (_selectedCategoryId == null) {
      showToast(context, l10n.budgetCategoryHint);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);

      if (_isEditing) {
        await repo.updateBudget(
          widget.budget!.id,
          amount: amount,
        );
      } else {
        // 0 是全选下标，忽略
        for (int i = 1; i < _selectedMonth.length; i++) {
          if(!_selectedMonth[i]) continue;
          await repo.createBudget(
            ledgerId: ledgerId,
            year: _selectedYear,
            month: i,
            categoryId: _selectedCategoryId,
            amount: amount,
            // 预留功能，特定日预算，提示用户支付
            prompt: false,
          );
        }
      }

      // 刷新预算数据
      ref.read(budgetRefreshProvider.notifier).state++;

      if (mounted) {
        showToast(context, l10n.budgetSaveSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteBudget() async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(l10n.budgetDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(repositoryProvider);
      await repo.deleteBudget(widget.budget!.id);

      // 刷新预算数据
      ref.read(budgetRefreshProvider.notifier).state++;

      if (mounted) {
        showToast(context, l10n.budgetDeleteSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, e.toString());
      }
    }
  }
}
