import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'dart:math' as math;

class PieChartWidget extends StatelessWidget {
  final List<({Color? color, String name, double percent, double value})> data;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final bool showHint;
  final String? hintText;
  final VoidCallback? onCloseHint;
  final bool hideAmounts;
  final Color themeColor;
  final bool whiteBg;
  final bool isDark;
  final double cornerRadius;

  const PieChartWidget({
    super.key,
    required this.data,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    this.showHint = false,
    this.hintText,
    this.onCloseHint,
    this.hideAmounts = false,
    required this.themeColor,
    this.whiteBg = true,
    this.isDark = false,
    this.cornerRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < 0) {
          onSwipeLeft();
        } else if (v > 0) {
          onSwipeRight();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: whiteBg ? Colors.white : BeeTokens.dividerStatic,
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 3,
                  child: PieChart(
                    PieChartData(
                      sections: _buildSections(context),
                      centerSpaceRadius: 40,
                      sectionsSpace: 2,
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _buildLegend(context),
                  ),
                ),
              ],
            ),
            if (showHint)
              Positioned(
                right: 8,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: BeeTokens.dividerStatic,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.swipe,
                            size: 14, color: BeeTokens.textSecondary(context)),
                        const SizedBox(width: 4),
                        Text(
                          hintText ?? AppLocalizations.of(context)!.analyticsSwipeHint,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: BeeTokens.textSecondary(context)),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: onCloseHint,
                          child: Icon(Icons.close,
                              size: 14, color: BeeTokens.textTertiary(context)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildSections(BuildContext context) {
    final colors = _generateColors(data.length);
    return data.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      return PieChartSectionData(
        color: item.color ?? colors[index],
        value: item.value,
        title: hideAmounts ? '**' : '${(item.percent * 100).toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
      );
    }).toList();
  }

  Widget _buildLegend(BuildContext context) {
    final colors = _generateColors(data.length);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: item.color ?? colors[index],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              item.name,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  List<Color> _generateColors(int count) {
    final List<Color> colors = [];
    for (int i = 0; i < count; i++) {
      final hue = (i * 360 / count) % 360;
      colors.add(HSLColor.fromAHSL(1.0, hue, 0.65, 0.55).toColor());
    }
    return colors;
  }
}
