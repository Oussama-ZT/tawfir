import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../models/category.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'common.dart';
import '../l10n/l10n.dart';

/// Donut of spending per category with a legend. Tap a slice to focus it.
class CategoryPieChart extends StatefulWidget {
  const CategoryPieChart({super.key, required this.data});

  final List<MapEntry<ExpenseCategory, double>> data;

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final total = widget.data.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) return const SizedBox.shrink();
    final selected = _touched != null && _touched! < widget.data.length ? widget.data[_touched!] : null;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 12),
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 64,
                    sectionsSpace: 3,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        if (!event.isInterestedForInteractions || response?.touchedSection == null) {
                          if (_touched != null) setState(() => _touched = null);
                          return;
                        }
                        final i = response!.touchedSection!.touchedSectionIndex;
                        if (i != _touched) setState(() => _touched = i < 0 ? null : i);
                      },
                    ),
                    sections: [
                      for (var i = 0; i < widget.data.length; i++)
                        PieChartSectionData(
                          value: widget.data[i].value,
                          color: widget.data[i].key.color,
                          radius: i == _touched ? 26 : 20,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(selected?.key.label ?? tr('Total'), style: context.type.bodySmall),
                    const SizedBox(height: 2),
                    AmountText(selected?.value ?? total, style: context.type.titleLarge),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < widget.data.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _touched = _touched == i ? null : i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: widget.data[i].key.color, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(widget.data[i].key.label,
                          style: context.type.bodyMedium?.copyWith(
                              fontWeight: i == _touched ? FontWeight.w700 : FontWeight.w400)),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(percent(widget.data[i].value / total),
                          textAlign: TextAlign.end, style: context.type.bodySmall?.copyWith(color: eco.muted)),
                    ),
                    SizedBox(
                      width: 104,
                      child: Text(money(widget.data[i].value),
                          textAlign: TextAlign.end,
                          style: context.type.titleSmall?.copyWith(fontFeatures: tabular)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
