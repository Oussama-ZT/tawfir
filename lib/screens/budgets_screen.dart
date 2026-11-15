import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/plan.dart';
import '../services/insights_service.dart';
import '../state/app_state.dart';
import '../state/plan_state.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/format.dart';
import '../widgets/budget_card.dart';
import '../widgets/common.dart';
import '../widgets/expense_tile.dart';
import '../widgets/monthly_bar_chart.dart';
import 'envelope_form.dart';
import 'paywall_screen.dart';
import 'wallets_screen.dart';
import '../l10n/l10n.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, this.showTitle = true});

  /// False inside the Budgets tab, whose header shows the title.
  final bool showTitle;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  DateTime _month = monthStart(DateTime.now());

  Future<void> _edit(String key, String label, double current) async {
    final state = context.read<AppState>();
    // A new category budget past the Starter limit asks for Pro first.
    if (key != InsightsService.totalBudgetKey && current <= 0) {
      final ok = await requirePlan(context,
          allowed: context.read<PlanState>().canAddCategoryBudget(state.categoryBudgetCount),
          needed: Plan.pro,
          reason: tr('Starter permet {0} budgets par catégorie. Avec Pro, fixez-en sur toutes vos catégories.', [Plan.starter.categoryBudgetLimit]));
      if (!ok || !mounted) return;
    }
    final value = await showAmountDialog(
      context,
      title: label,
      initial: current,
      allowZero: true,
      helper: tr('Le même montant s\'applique chaque mois. Laissez vide pour retirer ce budget.'),
    );
    if (value != null) await state.setBudget(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final eco = context.eco;
    final total = state.totalBudget;
    final totals = state.monthlyTotals(_month, 6);
    final previous = totals[totals.length - 2].value;
    final withData = totals.where((t) => t.value > 0).toList();
    final average = withData.isEmpty ? 0.0 : withData.fold(0.0, (s, t) => s + t.value) / withData.length;
    final categoryBudgetSum = ExpenseCategory.visible.fold(0.0, (s, c) => s + state.budgetFor(c.id));

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          if (widget.showTitle) ScreenTitle(tr('Budgets')) else const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MonthSelector(month: _month, onChanged: (m) => setState(() => _month = m)),
                const SizedBox(height: 16),
                BudgetCard(
                  month: _month,
                  onTap: () => showEnvelopeForm(context),
                  onEdit: () => showEnvelopeForm(context),
                ),
                if (total > 0 && categoryBudgetSum > total)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 10, 4, 0),
                    child: Text(
                      tr('Vos budgets par catégorie ({0}) dépassent le budget global.', [money(categoryBudgetSum)]),
                      style: context.type.bodySmall?.copyWith(color: eco.amber),
                    ),
                  ),
                SectionHeader(tr('Six derniers mois')),
                Grouped(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 16, 14),
                  children: [
                    Column(
                      children: [
                        Row(
                          children: [
                            _Stat(label: tr('Moyenne mensuelle'), value: moneyApprox(average)),
                            _Stat(
                              label: tr('Comparé à {0}', [monthName(totals[totals.length - 2].key)]),
                              value: previous <= 0
                                  ? tr('Pas de données')
                                  : '${totals.last.value >= previous ? '+' : '−'}${percent((totals.last.value / previous - 1).abs())}',
                              color: previous <= 0 ? null : (totals.last.value > previous ? eco.coral : eco.leaf),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        MonthlyBarChart(totals: totals, budget: total),
                      ],
                    ),
                  ],
                ),
                SectionHeader(tr('Par catégorie')),
                Grouped(
                  dividerIndent: 72,
                  children: [
                    for (final cat in ExpenseCategory.visible)
                      _CategoryBudgetRow(
                        category: cat,
                        spent: state.spentIn(_month, categoryId: cat.id),
                        budget: state.budgetFor(cat.id),
                        frozen: state.frozenBudgetKeys.contains(cat.id),
                        onTap: state.frozenBudgetKeys.contains(cat.id)
                            ? () => explainFrozen(context, frozen: tr('Le budget {0} est gelé', [cat.label]), needed: Plan.pro)
                            : () => _edit(cat.id, tr('Budget {0}', [cat.label]), state.budgetFor(cat.id)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.bodySmall, maxLines: 2),
          const SizedBox(height: 4),
          Text(value, style: context.type.titleLarge?.copyWith(color: color, fontFeatures: tabular)),
        ],
      ),
    );
  }
}

class _CategoryBudgetRow extends StatelessWidget {
  const _CategoryBudgetRow(
      {required this.category, required this.spent, required this.budget, required this.onTap, this.frozen = false});

  final ExpenseCategory category;
  final double spent;
  final double budget;
  final VoidCallback onTap;

  /// Beyond the plan's limit: shown, but not applied.
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CategoryAvatar(category: category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(category.label, style: context.type.titleSmall)),
                      Text(money(spent), style: context.type.titleSmall?.copyWith(fontFeatures: tabular)),
                      if (budget > 0)
                        Text(' / ${money(budget)}',
                            style: context.type.bodySmall?.copyWith(color: eco.muted, fontFeatures: tabular)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (frozen)
                    Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 14, color: eco.muted),
                        const SizedBox(width: 6),
                        Text(tr('Budget gelé, non appliqué'), style: context.type.bodySmall),
                      ],
                    )
                  else if (budget > 0)
                    BudgetProgress(spent: spent, budget: budget)
                  else
                    Text(tr('Pas de budget, touchez pour en fixer un'), style: context.type.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
