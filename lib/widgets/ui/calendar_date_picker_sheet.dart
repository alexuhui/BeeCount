import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';

const _enMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _zhWeekdays = ['一', '二', '三', '四', '五', '六', '日'];
const _enWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _dateRowCount = 6;
const _dateRowHeight = 44.0;

/// 日历点选日期。不传 [initial] 时默认选中今天。
/// 左右箭头切换月份；点年份或月份后，在当前页弹出滚轮。

enum _WheelTarget { year, month }

Future<DateTime?> showCalendarDatePicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? minDate,
  DateTime? maxDate,
  bool confirmIsNext = false,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: BeeTokens.surfaceElevated(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (ctx) => CalendarDatePickerSheet(
      initial: initial ?? DateTime.now(),
      minDate: minDate,
      maxDate: maxDate,
      confirmIsNext: confirmIsNext,
    ),
  );
}

class CalendarDatePickerSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime? minDate;
  final DateTime? maxDate;
  final bool confirmIsNext;

  const CalendarDatePickerSheet({
    super.key,
    required this.initial,
    this.minDate,
    this.maxDate,
    this.confirmIsNext = false,
  });

  @override
  State<CalendarDatePickerSheet> createState() =>
      _CalendarDatePickerSheetState();
}

class _CalendarDatePickerSheetState extends State<CalendarDatePickerSheet> {
  late DateTime _selected;
  final _yearKey = GlobalKey();
  final _monthKey = GlobalKey();
  _WheelTarget? _openTarget;
  OverlayEntry? _popup;
  FixedExtentScrollController? _popupCtrl;
  int? _pendingIndex;

  DateTime get _minDay {
    final min = widget.minDate ?? DateTime(2000, 1, 1);
    return DateTime(min.year, min.month, min.day);
  }

  DateTime get _maxDay {
    final max = widget.maxDate ?? DateTime(2100, 12, 31);
    return DateTime(max.year, max.month, max.day);
  }

  @override
  void initState() {
    super.initState();
    _selected = _clamp(DateTime(
      widget.initial.year,
      widget.initial.month,
      widget.initial.day,
    ));
  }

  @override
  void dispose() {
    _popup?.remove();
    _popup = null;
    _popupCtrl?.dispose();
    _popupCtrl = null;
    super.dispose();
  }

  DateTime _clamp(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    if (day.isBefore(_minDay)) return _minDay;
    if (day.isAfter(_maxDay)) return _maxDay;
    return day;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isZh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  Color _onColor(Color color) =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.light
          ? const Color(0xFF333333)
          : Colors.white;

  bool _dayEnabled(DateTime day) =>
      !day.isBefore(_minDay) && !day.isAfter(_maxDay);

  bool _monthInRange(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    return !end.isBefore(_minDay) && !start.isAfter(_maxDay);
  }

  List<int> get _years =>
      [for (var year = _minDay.year; year <= _maxDay.year; year++) year];

  List<int> _monthsFor(int year) {
    var start = 1;
    var end = 12;
    if (year == _minDay.year) start = _minDay.month;
    if (year == _maxDay.year) end = _maxDay.month;
    return [for (var month = start; month <= end; month++) month];
  }

  void _applyYearMonth(int year, int month) {
    final dim = DateTime(year, month + 1, 0).day;
    var day = _selected.day;
    if (day > dim) day = dim;
    final next = _clamp(DateTime(year, month, day));
    if (_sameDay(next, _selected)) return;
    setState(() => _selected = next);
  }

  void _shiftMonth(int delta) {
    final target = DateTime(_selected.year, _selected.month + delta, 1);
    if (!_monthInRange(target.year, target.month)) return;
    _applyYearMonth(target.year, target.month);
  }

  void _closePopup() {
    _commitWheel();
    _popup?.remove();
    _popup = null;
    _popupCtrl?.dispose();
    _popupCtrl = null;
    _pendingIndex = null;
    if (mounted && _openTarget != null) {
      setState(() => _openTarget = null);
    } else {
      _openTarget = null;
    }
  }

  void _commitWheel() {
    final target = _openTarget;
    final index = _pendingIndex;
    if (target == null || index == null) return;
    if (target == _WheelTarget.year) {
      final years = _years;
      if (index < 0 || index >= years.length) return;
      final year = years[index];
      final months = _monthsFor(year);
      var month = _selected.month;
      if (!months.contains(month)) {
        month = month < months.first ? months.first : months.last;
      }
      _applyYearMonth(year, month);
      return;
    }
    final months = _monthsFor(_selected.year);
    if (index < 0 || index >= months.length) return;
    _applyYearMonth(_selected.year, months[index]);
  }

  void _openWheel(_WheelTarget target) {
    if (_openTarget == target) {
      _closePopup();
      return;
    }
    _popup?.remove();
    _popup = null;
    _popupCtrl?.dispose();
    _popupCtrl = null;

    final anchor = target == _WheelTarget.year ? _yearKey : _monthKey;
    final box = anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;

    final origin = box.localToGlobal(Offset.zero);
    final anchorSize = box.size;
    const popupWidth = 148.0;
    const popupHeight = 156.0;
    final screen = MediaQuery.sizeOf(context);
    final left = (origin.dx + anchorSize.width / 2 - popupWidth / 2)
        .clamp(8.0, screen.width - popupWidth - 8);
    var top = origin.dy + anchorSize.height + 6;
    if (top + popupHeight > screen.height - 8) {
      top = origin.dy - popupHeight - 6;
    }

    final labels = <String>[];
    late final int initialIndex;
    if (target == _WheelTarget.year) {
      final years = _years;
      labels.addAll(years.map((year) => '$year'));
      final index = years.indexOf(_selected.year);
      initialIndex = index < 0 ? 0 : index;
    } else {
      final months = _monthsFor(_selected.year);
      final zh = _isZh(context);
      labels.addAll(
        months.map((month) => zh ? '$month月' : _enMonths[month - 1]),
      );
      final index = months.indexOf(_selected.month);
      initialIndex = index < 0 ? 0 : index;
    }
    _pendingIndex = initialIndex;
    _popupCtrl = FixedExtentScrollController(initialItem: initialIndex);

    _popup = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closePopup,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              height: popupHeight,
              child: Material(
                color: BeeTokens.surfaceElevated(overlayContext),
                elevation: 8,
                shadowColor: Colors.black26,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side:
                      BorderSide(color: BeeTokens.borderStrong(overlayContext)),
                ),
                clipBehavior: Clip.antiAlias,
                child: CupertinoPicker(
                  itemExtent: 52,
                  scrollController: _popupCtrl,
                  onSelectedItemChanged: (i) => _pendingIndex = i,
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _pendingIndex = i;
                          _closePopup();
                        },
                        child: Center(
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 18,
                              color: BeeTokens.textPrimary(overlayContext),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
    setState(() => _openTarget = target);
    Overlay.of(context).insert(_popup!);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, l10n, primary),
          _buildYearMonthBar(context, primary),
          _buildDayPanel(context, primary),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n,
    Color primary,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: BeeTokens.isDark(context)
                ? BeeTokens.border(context)
                : const Color(0xFFE5E5E5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.commonCancel,
              style: TextStyle(
                  fontSize: 16, color: BeeTokens.textTertiary(context)),
            ),
          ),
          Expanded(
            child: Text(
              l10n.homeSelectDate,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: BeeTokens.textPrimary(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: Text(
              widget.confirmIsNext ? l10n.commonNext : l10n.commonOk,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearMonthBar(BuildContext context, Color primary) {
    final previous = DateTime(_selected.year, _selected.month - 1, 1);
    final next = DateTime(_selected.year, _selected.month + 1, 1);
    final canPrev = _monthInRange(previous.year, previous.month);
    final canNext = _monthInRange(next.year, next.month);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: canPrev ? () => _shiftMonth(-1) : null,
            icon: const Icon(Icons.chevron_left),
            color: primary,
            disabledColor: BeeTokens.textDisabled(context),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _headerChip(
                  context,
                  key: _yearKey,
                  label: _isZh(context)
                      ? '${_selected.year}年'
                      : '${_selected.year}',
                  active: _openTarget == _WheelTarget.year,
                  primary: primary,
                  onTap: () => _openWheel(_WheelTarget.year),
                ),
                const SizedBox(width: 8),
                _headerChip(
                  context,
                  key: _monthKey,
                  label: _isZh(context)
                      ? '${_selected.month}月'
                      : _enMonths[_selected.month - 1],
                  active: _openTarget == _WheelTarget.month,
                  primary: primary,
                  onTap: () => _openWheel(_WheelTarget.month),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: canNext ? () => _shiftMonth(1) : null,
            icon: const Icon(Icons.chevron_right),
            color: primary,
            disabledColor: BeeTokens.textDisabled(context),
          ),
        ],
      ),
    );
  }

  Widget _headerChip(
    BuildContext context, {
    required GlobalKey key,
    required String label,
    required bool active,
    required Color primary,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: active
                ? primary.withValues(alpha: 0.16)
                : BeeTokens.surfaceSecondary(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? primary : Colors.transparent),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                Icon(
                  active ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 20,
                  color: BeeTokens.textSecondary(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayPanel(BuildContext context, Color primary) {
    final year = _selected.year;
    final month = _selected.month;
    final leading = DateTime(year, month, 1).weekday - 1;
    final days = DateTime(year, month + 1, 0).day;
    final labels = _isZh(context) ? _zhWeekdays : _enWeekdays;
    final today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in labels)
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: BeeTokens.textTertiary(context),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < _dateRowCount; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _dayCell(
                      context,
                      primary,
                      today,
                      _cellDate(row, col, leading, days, year, month),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  DateTime? _cellDate(
      int row, int col, int leading, int days, int year, int month) {
    final day = row * 7 + col - leading + 1;
    if (day < 1 || day > days) return null;
    return DateTime(year, month, day);
  }

  Widget _dayCell(
    BuildContext context,
    Color primary,
    DateTime today,
    DateTime? day,
  ) {
    if (day == null) return const SizedBox(height: _dateRowHeight);

    final enabled = _dayEnabled(day);
    final selected = _sameDay(day, _selected);
    final isToday = _sameDay(day, today);

    return SizedBox(
      height: _dateRowHeight,
      child: Center(
        child: Material(
          color: selected ? primary : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled
                ? () {
                    setState(() =>
                        _selected = DateTime(day.year, day.month, day.day));
                    Navigator.pop(context, _selected);
                  }
                : null,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: isToday && !selected
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: primary, width: 1.4),
                    )
                  : null,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      selected || isToday ? FontWeight.w600 : FontWeight.w400,
                  color: !enabled
                      ? BeeTokens.textDisabled(context)
                      : selected
                          ? _onColor(primary)
                          : BeeTokens.textPrimary(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
