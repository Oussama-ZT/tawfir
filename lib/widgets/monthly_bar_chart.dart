import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../l10n/l10n.dart';

/// Monthly totals with an optional dashed budget line. The selected month is blue.
class MonthlyBarChart extends StatelessWidget {
  const MonthlyBarChart({super.key, required this.totals, this.budget = 0});

  final List<MapEntry<DateTime, double>> totals;
  final double budget;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final maxValue = totals.fold(budget, (m, e) => e.value > m ? e.value : m);
    final maxY = maxValue <= 0 ? 100.0 : maxValue * 1.18;

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= totals.length) return const SizedBox.shrink();
                  final isLast = i == totals.length - 1;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      shortMonth(totals[i].key),
                      style: context.type.labelSmall?.copyWith(color: isLast ? eco.ink : eco.muted),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => eco.ink,
              tooltipBorderRadius: BorderRadius.circular(10),
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                money(rod.toY),
                TextStyle(fontFamily: bodyFont, color: eco.background, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (budget > 0)
                HorizontalLine(
                  y: budget,
                  color: eco.muted.withValues(alpha: 0.6),
                  strokeWidth: 1.2,
                  dashArray: [4, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topLeft,
                    padding: const EdgeInsets.only(bottom: 4),
                    style: TextStyle(fontFamily: bodyFont, color: eco.muted, fontSize: 11, fontWeight: FontWeight.w600),
                    labelResolver: (_) => tr('Budget'),
                  ),
                ),
            ],
          ),
          barGroups: [
            for (var i = 0; i < totals.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: totals[i].value,
                    width: 22,
                    color: i == totals.length - 1 ? eco.blueInk : eco.blueInk.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
