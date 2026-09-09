import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_list_view/flutter_list_view.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../providers.dart';
import '../../providers/home_transaction_providers.dart';
import '../settings/personalize_page.dart' show headerStyleProvider;
import '../../data/db.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/biz/bee_icon.dart';
import '../../styles/tokens.dart';
import '../transaction/search_page.dart';
import '../ai/ai_chat_page.dart';
import '../../l10n/app_localizations.dart';
import '../../services/system/logger_service.dart';
import '../../services/export/share_poster_service.dart';
import '../report/annual_report_page.dart';
import '../calendar/calendar_page.dart';

// 优化版首页 - 使用FlutterListView实现精准定位和丝滑跳转
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late FlutterListViewController _listController;
  bool _isJumping = false;
  final GlobalKey<TransactionListState> _transactionListKey =
      GlobalKey<TransactionListState>();

  // 可见性管理
  final Set<String> _visibleHeaders = {}; // 当前可见的日期头部
  Timer? _debounceTimer;

  // StreamBuilder 刷新计数器
  int _streamBuilderKey = 0;
  int? _lastLedgerId;

  // 月初提醒状态
  bool _showLastMonthReminder = false;
  static const String _reminderDismissedKey = 'last_month_reminder_dismissed';

  // 年度账单提醒状态（12月15日 - 次年1月31日显示）
  bool _showAnnualReportReminder = false;
  static const String _annualReportDismissedKey =
      'annual_report_reminder_dismissed';

  @override
  void initState() {
    super.initState();
    _listController = FlutterListViewController();
    _checkLastMonthReminder();
    _checkAnnualReportReminder();
  }

  // 检查是否应该显示上月报告提醒
  Future<void> _checkLastMonthReminder() async {
    final now = DateTime.now();
    // 只在每月前7天显示提醒
    if (now.day > 7) return;

    final prefs = await SharedPreferences.getInstance();
    final dismissedMonth = prefs.getString(_reminderDismissedKey);
    final currentMonth = '${now.year}-${now.month}';

    // 如果当月已经关闭过，不再显示
    if (dismissedMonth == currentMonth) return;

    if (mounted) {
      setState(() {
        _showLastMonthReminder = true;
      });
    }
  }

  // 关闭上月报告提醒
  Future<void> _dismissLastMonthReminder() async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reminderDismissedKey, currentMonth);

    if (mounted) {
      setState(() {
        _showLastMonthReminder = false;
      });
    }
  }

  // 检查是否应该显示年度账单提醒（12月15日 - 次年1月31日）
  Future<void> _checkAnnualReportReminder() async {
    final now = DateTime.now();

    // 判断是否在提醒时间范围内：12月15日 - 次年1月31日
    final isInRange = (now.month == 12 && now.day >= 15) || now.month == 1;
    if (!isInRange) return;

    // 确定要展示的年度（12月展示当年，1月展示上一年）
    final reportYear = now.month == 1 ? now.year - 1 : now.year;

    final prefs = await SharedPreferences.getInstance();
    final dismissedYear = prefs.getInt(_annualReportDismissedKey);

    // 如果这个年度已经关闭过，不再显示
    if (dismissedYear == reportYear) return;

    if (mounted) {
      setState(() {
        _showAnnualReportReminder = true;
      });
    }
  }

  // 关闭年度账单提醒
  Future<void> _dismissAnnualReportReminder() async {
    final now = DateTime.now();
    final reportYear = now.month == 1 ? now.year - 1 : now.year;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_annualReportDismissedKey, reportYear);

    if (mounted) {
      setState(() {
        _showAnnualReportReminder = false;
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _listController.dispose();
    super.dispose();
  }

  // 精准月份跳转：必要时继续翻页，并挡住可见性回调，避免把月份打回当前屏
  Future<void> _jumpToTargetMonth(DateTime targetMonth) async {
    if (_isJumping) return;

    _debounceTimer?.cancel();
    _visibleHeaders.clear();
    setState(() {
      _isJumping = true;
    });

    try {
      final ledgerId = ref.read(currentLedgerIdProvider);
      await ref
          .read(homeTransactionControllerProvider(ledgerId).notifier)
          .ensureLoadedThroughMonth(targetMonth);
      if (!mounted) return;

      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      var jumped =
          _transactionListKey.currentState?.jumpToMonth(targetMonth) ?? false;
      if (!jumped) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        jumped =
            _transactionListKey.currentState?.jumpToMonth(targetMonth) ?? false;
      }
      if (!jumped) {
        logger.warning('HomePage', '未能定位到 ${targetMonth.year}-${targetMonth.month}');
      }

      // jumpToIndex 在下一帧才真正滚过去，这期间不要让可见性检测改月份
      await Future<void>.delayed(const Duration(milliseconds: 320));
    } finally {
      if (mounted) {
        setState(() {
          _isJumping = false;
        });
      }
    }
  }

  // 日期头部可见性变化
  void _onHeaderVisibilityChanged(String dateKey, bool isVisible) {
    if (_isJumping) return;

    if (isVisible) {
      _visibleHeaders.add(dateKey);
    } else {
      _visibleHeaders.remove(dateKey);
    }

    // 防抖更新月份
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      _updateCurrentMonth();
    });
  }

  // 更新当前月份
  void _updateCurrentMonth() {
    if (_isJumping || !mounted || _visibleHeaders.isEmpty) return;

    try {
      // 获取最顶部的可见日期头部（按日期排序，取最新的）
      final sortedDates = _visibleHeaders.toList()
        ..sort((a, b) => b.compareTo(a));
      final topDateKey = sortedDates.first;

      final dateParts = topDateKey.split('-');
      if (dateParts.length != 3) return;

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final detectedMonth = DateTime(year, month, 1);

      // 更新选中月份
      final currentSelected = ref.read(selectedMonthProvider);
      if (currentSelected.year != detectedMonth.year ||
          currentSelected.month != detectedMonth.month) {
        ref.read(selectedMonthProvider.notifier).state = detectedMonth;
      }
    } catch (e) {
      // 忽略错误，继续正常运行
    }
  }

  // FlutterListView不需要手动计算偏移量，直接使用jumpToIndex即可！

  // 日期选择处理
  Future<void> _handleDateSelection() async {
    final month = ref.read(selectedMonthProvider);
    final res = await showWheelDatePicker(
      context,
      initial: month,
      mode: WheelDatePickerMode.ym,
      maxDate: DateTime.now(),
    );

    if (res != null) {
      final targetMonth = DateTime(res.year, res.month, 1);
      ref.read(selectedMonthProvider.notifier).state = targetMonth;

      // 使用FlutterListView的精准跳转
      await _jumpToTargetMonth(targetMonth);
    }
  }

  // 构建月初提醒卡片
  Widget _buildLastMonthReminderCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final monthFormat = DateFormat.MMMM(l10n.localeName);
    final primaryColor = ref.watch(primaryColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // 左侧装饰条
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                color: primaryColor,
              ),
            ),
            // 主体内容
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  // 文案
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: monthFormat.format(lastMonth),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: primaryColor,
                                  ),
                                ),
                                TextSpan(
                                  text: ' ${l10n.homeLastMonthReportSubtitle}',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 查看按钮（查看后本次隐藏，下次打开app还会显示）
                  GestureDetector(
                    onTap: () {
                      SharePosterService.showPosterCarouselPreview(
                        context,
                        year: lastMonth.year,
                        month: lastMonth.month,
                      );
                      // 只临时隐藏，不保存到 prefs
                      setState(() {
                        _showLastMonthReminder = false;
                      });
                    },
                    child: Text(
                      l10n.homeLastMonthReportView,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 关闭按钮（关闭后当月不再显示）
                  GestureDetector(
                    onTap: _dismissLastMonthReminder,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 年度账单提醒卡片（样式与月初提醒一致）
  Widget _buildAnnualReportReminderCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final reportYear = now.month == 1 ? now.year - 1 : now.year;
    final primaryColor = ref.watch(primaryColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // 左侧装饰条
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                color: primaryColor,
              ),
            ),
            // 主体内容
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  // 文案
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_graph_rounded,
                          color: primaryColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.homeAnnualReportReminder(reportYear),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 查看按钮
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AnnualReportPage(initialYear: reportYear),
                        ),
                      );
                      // 临时隐藏
                      setState(() {
                        _showAnnualReportReminder = false;
                      });
                    },
                    child: Text(
                      l10n.homeAnnualReportView,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 关闭按钮
                  GestureDetector(
                    onTap: _dismissAnnualReportReminder,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cachedFullData = ref.watch(cachedTransactionsProvider);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final homeTx = ref.watch(homeTransactionControllerProvider(ledgerId));
    final month = ref.watch(selectedMonthProvider);
    final hide = ref.watch(hideAmountsProvider);
    final aiEnabledAsync = ref.watch(aiAssistantEnabledProvider);
    final aiEnabled = aiEnabledAsync.asData?.value ?? true; // 默认开启

    // 检测账本切换，强制刷新 StreamBuilder 并清空缓存
    if (_lastLedgerId != null && _lastLedgerId != ledgerId) {
      _streamBuilderKey++;
      // 清空缓存，避免显示旧账本数据
      Future.microtask(() {
        ref.read(cachedTransactionsProvider.notifier).state = null;
      });
      logger.info('HomePage',
          '账本切换: $_lastLedgerId → $ledgerId, 刷新StreamBuilder (key=$_streamBuilderKey)');
    }
    _lastLedgerId = ledgerId;

    // 监听滚动到顶部的信号
    ref.listen<int>(homeScrollToTopProvider, (previous, next) {
      if (previous != next) {
        // 滚动到列表顶部
        _transactionListKey.currentState?.jumpToTop();
      }
    });

    // 监听切换到 Stream 模式的信号
    ref.listen<int>(homeSwitchToStreamProvider, (previous, next) {
      if (previous != next) {
        _transactionListKey.currentState?.switchToStreamMode();
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // ⭐ 自适应背景色
      body: Column(
        children: [
          Consumer(builder: (context, ref, _) {
            ref.watch(headerStyleProvider);
            final hide = ref.watch(hideAmountsProvider);
            return PrimaryHeader(
              title: '',
              showTitleSection: false,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 头部 - 使用Stack实现真正居中
                  SizedBox(
                    height: 48, // IconButton默认高度
                    child: Stack(
                      children: [
                        // 底层：居中的图标和文字
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              BeeIcon(
                                color: Theme.of(context).colorScheme.primary,
                                size: 32,
                              ),
                              Text(
                                AppLocalizations.of(context).homeAppTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        // 上层：左侧AI助手按钮（仅在开启时显示）
                        if (aiEnabled)
                          Positioned(
                            left: -10,
                            top: 0,
                            bottom: 0,
                            child: IconButton(
                              tooltip: AppLocalizations.of(context).aiChatTitle,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                // 用户离开首页，切换到 Stream 模式
                                _transactionListKey.currentState
                                    ?.switchToStreamMode();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const AIChatPage(),
                                  ),
                                );
                              },
                              icon: Padding(
                                padding: const EdgeInsets.all(12),
                                child: SvgPicture.asset(
                                  'assets/icons/ai.svg',
                                  width: 20,
                                  height: 20,
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // 上层：右侧按钮（日历 + 搜索）
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Row(
                            children: [
                              // 日历按钮
                              IconButton(
                                tooltip:
                                    AppLocalizations.of(context).calendarTitle,
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CalendarPage(),
                                    ),
                                  );
                                },
                                icon: Icon(
                                  Icons.calendar_month_outlined,
                                  size: 20,
                                  color: Theme.of(context).iconTheme.color,
                                ),
                              ),
                              // 搜索按钮
                              IconButton(
                                tooltip:
                                    AppLocalizations.of(context).homeSearch,
                                onPressed: () {
                                  // 用户离开首页，切换到 Stream 模式
                                  _transactionListKey.currentState
                                      ?.switchToStreamMode();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => const SearchPage(),
                                    ),
                                  );
                                },
                                icon: Icon(
                                  Icons.search,
                                  size: 20,
                                  color: Theme.of(context).iconTheme.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 第二行 - 月份显示和统计
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _isJumping ? null : _handleDateSelection,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                AppLocalizations.of(context)
                                    .homeYear(month.year),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withOpacity(0.6), // ⭐ 自适应次要文字颜色
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  AppLocalizations.of(context).homeMonth(
                                      month.month.toString().padLeft(2, '0')),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.color, // ⭐ 自适应主文字颜色
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 4),
                                // 月份旁边的向下三角形（日期选择）
                                _isJumping
                                    ? SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.color, // ⭐ 自适应颜色
                                        ),
                                      )
                                    : Icon(
                                        Icons.keyboard_arrow_down,
                                        size: 16,
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withOpacity(0.6), // ⭐ 自适应次要颜色
                                      ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: 1,
                        height: 36,
                        color: Theme.of(context).dividerTheme.color ??
                            Theme.of(context).dividerColor, // ⭐ 自适应分割线颜色
                      ),
                      const Expanded(child: _HeaderCenterSummary()),
                    ],
                  ),
                ],
              ),
              bottom: null,
            );
          }),
          const SizedBox(height: 0),
          // 月初提醒卡片
          if (_showLastMonthReminder) _buildLastMonthReminderCard(context),
          // 年度账单提醒卡片（12月15日 - 次年1月31日）
          if (_showAnnualReportReminder)
            _buildAnnualReportReminderCard(context),
          Expanded(
            child: homeTx.loading && homeTx.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : homeTx.error != null && homeTx.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${homeTx.error}'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => ref
                                  .read(homeTransactionControllerProvider(
                                          ledgerId)
                                      .notifier)
                                  .reload(),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >=
                              n.metrics.maxScrollExtent - 240) {
                            ref
                                .read(homeTransactionControllerProvider(
                                        ledgerId)
                                    .notifier)
                                .loadMore();
                          }
                          return false;
                        },
                        child: TransactionList(
                          key: _transactionListKey,
                          transactions: homeTx.items,
                          transactionsWithDetails: cachedFullData,
                          hideAmounts: hide,
                          enableVisibilityTracking: true,
                          onDateVisibilityChanged: _onHeaderVisibilityChanged,
                          controller: _listController,
                          emptyWidget: AppEmpty(
                            text: AppLocalizations.of(context).homeNoRecords,
                            subtext: AppLocalizations.of(context)
                                .homeNoRecordsSubtext,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCenterSummary extends ConsumerWidget {
  const _HeaderCenterSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final month = ref.watch(selectedMonthProvider);
    final params = (ledgerId: ledgerId, month: month);

    ref.watch(monthlyTotalsProvider(params));
    final cachedTotals = ref.watch(lastMonthlyTotalsProvider(params));
    final (income, expense) = cachedTotals ?? (0.0, 0.0);
    final balance = income - expense;

    Widget item(String title, double value) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                textAlign: TextAlign.left, style: BeeTextTokens.label(context)),
            const SizedBox(height: 2),
            AmountText(
              value: value,
              signed: false,
              decimals: 2,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.color, // ⭐ 自适应主文字颜色
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ) ??
                  TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.color, // ⭐ 自适应主文字颜色
                  ),
            ),
          ],
        );
    return Row(
      children: [
        Expanded(child: item(AppLocalizations.of(context).homeIncome, income)),
        Expanded(
            child: item(AppLocalizations.of(context).homeExpense, expense)),
        Expanded(
            child: item(AppLocalizations.of(context).homeBalance, balance)),
      ],
    );
  }
}
