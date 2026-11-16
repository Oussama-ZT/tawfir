import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/category.dart';
import '../services/budget_math.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/common.dart';
import '../widgets/expense_tile.dart';
import '../widgets/glass.dart';
import 'expense_form_screen.dart';

/// Monthly report: what came in and went out, how the budget held, and how
/// the month compares with the one before. Past months use their own
/// transactions and the budget they had.
class ReportView extends StatefulWidget {
  const ReportView({super.key});

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  DateTime _month = monthStart(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final eco = context.eco;
    final r = app.report(_month);
    final previousMonth = addMonths(_month, -1);
    final prev = app.report(previousMonth);
    final months = [for (var i = 5; i >= 0; i--) app.report(addMonths(_month, -i))];
    final byCategory = app.byCategory(_month);
    final top = r.topCategoryId == null ? null : ExpenseCategory.byId(r.topCategoryId!);

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
      children: [
        MonthSelector(month: _month, onChanged: (m) => setState(() => _month = m)),
        const SizedBox(height: 16),
        if (r.count == 0 && r.income == 0)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: Icons.insert_chart_outlined_rounded,
              title: tr('Rien à analyser pour {0}', [monthName(_month)]),
              message: tr('Notez vos dépenses et vos revenus : le bilan du mois se construit avec eux.'),
            ),
          )
        else ...[
          // The month's result, then what makes it up.
          GlassPanel(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.net >= 0 ? tr('Épargne du mois') : tr('Déficit du mois'),
                    style: context.type.labelMedium?.copyWith(color: eco.muted)),
                const SizedBox(height: 4),
                AmountText(r.net.abs(), style: context.type.displayMedium?.copyWith(color: r.net >= 0 ? eco.leaf : eco.coral)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Metric(
                      label: tr('Revenus'),
                      value: money(r.income),
                      change: MonthReport.change(r.income, prev.income),
                      upIsGood: true,
                    ),
                    _Metric(
                      label: tr('Dépenses'),
                      value: money(r.expenses),
                      change: MonthReport.change(r.expenses, prev.expenses),
                      upIsGood: false,
                    ),
                  ],
                ),
                if (prev.count > 0 || prev.income > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(tr('Évolution par rapport à {0}', [monthName(previousMonth)]), style: context.type.bodySmall),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Grouped(
            children: [
              _Line(label: tr('Moyenne par jour'), value: money(r.averagePerDay)),
              _Line(label: tr('Nombre de dépenses'), value: '${r.count}'),
              _Line(
                label: tr('Budget utilisé'),
                value: r.budgetUsage == null
                    ? tr('Pas de budget ce mois-là')
                    : tr('{0} de {1}', [percent(r.budgetUsage!), money(r.budget)]),
                color: r.budgetUsage == null
                    ? null
                    : r.budgetUsage! > 1
                    ? eco.coral
                    : r.budgetUsage! >= BudgetStatus.warningRatio
                    ? eco.amber
                    : eco.leaf,
              ),
              if (top != null)
                _Line(label: tr('Première catégorie'), value: '${top.label}, ${money(r.topCategoryAmount)}'),
            ],
          ),
          if (r.biggest != null) ...[
            SectionHeader(tr('Plus grosse dépense')),
            Grouped(
              children: [
                ExpenseTile(
                  expense: r.biggest!,
                  showDate: true,
                  onTap: () => ExpenseFormScreen.open(context, r.biggest),
                ),
              ],
            ),
          ],
          SectionHeader(tr('Revenus et dépenses sur six mois')),
          GlassPanel(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 16, 12, 10),
            child: Column(
              children: [
                _IncomeExpenseChart(months: months),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Legend(color: eco.leaf, label: tr('Revenus')),
                    const SizedBox(width: 18),
                    _Legend(color: eco.blueInk, label: tr('Dépenses')),
                  ],
                ),
              ],
            ),
          ),
          if (byCategory.isNotEmpty) ...[
            SectionHeader(tr('Répartition de {0}', [monthName(_month)])),
            Grouped(children: [CategoryPieChart(data: byCategory)]),
          ],
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.change, required this.upIsGood});

  final String label;
  final String value;
  final double? change;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final c = change;
    final good = c == null ? null : (c >= 0) == upIsGood;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.labelSmall),
          const SizedBox(height: 3),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.titleMedium?.copyWith(fontFeatures: tabular)),
          if (c != null)
            Text(
              '${c >= 0 ? '+' : '−'}${percent(c.abs())}',
              style: context.type.labelMedium?.copyWith(color: good! ? eco.leaf : eco.coral, fontFeatures: tabular),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(label, style: context.type.bodyMedium),
            const SizedBox(width: 12),
            // The value takes the rest of the line, aligned to its end.
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: context.type.titleSmall?.copyWith(fontFeatures: tabular, color: color),
              ),
            ),
          ],
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: context.type.labelSmall),
        ],
      );
}

/// Income and expenses side by side for each of the last six months.
class _IncomeExpenseChart extends StatelessWidget {
  const _IncomeExpenseChart({required this.months});

  final List<MonthReport> months;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final peak = months.fold(0.0, (m, r) => [m, r.income, r.expenses].reduce((a, b) => a > b ? a : b));
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: peak <= 0 ? 100 : peak * 1.15,
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
                  if (i < 0 || i >= months.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      shortMonth(months[i].month),
                      style: context.type.labelSmall?.copyWith(color: i == months.length - 1 ? eco.ink : eco.muted),
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
          barGroups: [
            for (var i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [
                  BarChartRodData(toY: months[i].income, width: 10, color: eco.leaf, borderRadius: BorderRadius.circular(4)),
                  BarChartRodData(toY: months[i].expenses, width: 10, color: eco.blueInk, borderRadius: BorderRadius.circular(4)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
