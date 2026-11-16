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
import 'expense_form_screen.dart';
import '../widgets/glass.dart';
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
    if (state.totalBudget <= 0) {
      final setFirst = await confirm(
        context,
        title: tr('Fixez d\'abord votre budget mensuel'),
        message: tr('Les budgets par catégorie répartissent le budget du mois : il faut donc le fixer en premier.'),
        confirmLabel: tr('Fixer le budget'),
      );
      if (setFirst && mounted) await showBudgetForm(context);
      return;
    }
    if (!mounted) return;
    final available = state.unallocatedFor(key);
    final value = await showAmountDialog(
      context,
      title: label,
      initial: current,
      allowZero: true,
      helper: tr('Disponible pour cette catégorie : {0}. Le même montant s\'applique chaque mois ; laissez vide pour retirer ce budget.',
          [money(available)]),
      max: available,
      maxError: tr('Au plus {0} : le reste du budget mensuel est déjà réparti entre vos catégories.', [money(available)]),
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
                  onTap: () => showBudgetForm(context),
                  onEdit: () => showBudgetForm(context),
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
                if (total > 0 && state.categoryBudgets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 10),
                    child: Text(
                      tr('Réparti : {0} sur {1}. Non réparti : {2}.', [
                        money(state.categoryBudgets.values.fold(0.0, (s, v) => s + v)),
                        money(total),
                        money(state.unallocatedFor('')),
                      ]),
                      style: context.type.bodySmall,
                    ),
                  ),
                Grouped(
                  dividerIndent: 72,
                  children: [
                    for (final cat in ExpenseCategory.visible)
                      _CategoryBudgetRow(
                        category: cat,
                        spent: state.spentIn(_month, categoryId: cat.id),
                        budget: state.categoryBudgetFor(cat.id, _month),
                        frozen: state.frozenBudgetKeys.contains(cat.id),
                        onTap: state.frozenBudgetKeys.contains(cat.id)
                            ? () => explainFrozen(context, frozen: tr('Le budget {0} est gelé', [cat.label]), needed: Plan.pro)
                            : () => showCategoryBudgetSheet(
                                  context,
                                  category: cat,
                                  month: _month,
                                  onEdit: () => _edit(cat.id, tr('Budget {0}', [cat.label]), state.budgetFor(cat.id)),
                                ),
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
                  else if (budget > 0) ...[
                    BudgetProgress(spent: spent, budget: budget),
                    const SizedBox(height: 6),
                    Text(
                      spent > budget
                          ? tr('Dépassé de {0}, {1} % utilisé', [money(spent - budget), (spent / budget * 100).round()])
                          : tr('Reste {0}, {1} % utilisé', [money(budget - spent), (spent / budget * 100).round()]),
                      style: context.type.bodySmall?.copyWith(color: spent > budget ? eco.coral : null),
                    ),
                  ] else
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

/// A category's budget and its spending history: this month against its
/// budget, the last six months, and the month's expenses.
Future<void> showCategoryBudgetSheet(
  BuildContext context, {
  required ExpenseCategory category,
  required DateTime month,
  required VoidCallback onEdit,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategorySheet(category: category, month: month, onEdit: onEdit),
    );

class _CategorySheet extends StatelessWidget {
  const _CategorySheet({required this.category, required this.month, required this.onEdit});

  final ExpenseCategory category;
  final DateTime month;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final eco = context.eco;
    final budget = state.categoryBudgetFor(category.id, month);
    final spent = state.spentIn(month, categoryId: category.id);
    final history = state.monthlyTotals(month, 6, categoryId: category.id);
    final peak = history.fold(0.0, (m, e) => e.value > m ? e.value : m);
    final items = state.expensesIn(month, categoryId: category.id);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Row(
            children: [
              CategoryAvatar(category: category),
              const SizedBox(width: 14),
              Expanded(child: Text(category.label, style: context.type.headlineSmall)),
            ],
          ),
          const SizedBox(height: 16),
          GlassPanel(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(monthYear(month), style: context.type.labelMedium?.copyWith(color: eco.muted)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Figure(label: tr('Alloué'), value: budget > 0 ? money(budget) : '—'),
                    _Figure(label: tr('Dépensé'), value: money(spent)),
                    _Figure(
                      label: budget > 0 && spent > budget ? tr('Dépassement') : tr('Reste'),
                      value: budget > 0 ? money((budget - spent).abs()) : '—',
                      color: budget > 0 && spent > budget ? eco.coral : null,
                    ),
                  ],
                ),
                if (budget > 0) ...[
                  const SizedBox(height: 14),
                  BudgetProgress(spent: spent, budget: budget, height: 8),
                  const SizedBox(height: 6),
                  Text(tr('{0} % utilisé', [(spent / budget * 100).round()]), style: context.type.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(context);
                    onEdit();
                  },
                  child: Text(budget > 0 ? tr('Modifier le budget') : tr('Fixer un budget')),
                ),
              ),
              if (budget > 0) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () async {
                    await context.read<AppState>().setBudget(category.id, 0);
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(foregroundColor: eco.coral),
                  child: Text(tr('Retirer')),
                ),
              ],
            ],
          ),
          SectionHeader(tr('Six derniers mois')),
          GlassPanel(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
            child: Column(
              children: [
                for (final e in history.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(width: 64, child: Text(shortMonth(e.key), style: context.type.bodySmall)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: peak <= 0 ? 0 : e.value / peak,
                              minHeight: 8,
                              color: e.value > 0 && state.categoryBudgetFor(category.id, e.key) > 0 && e.value > state.categoryBudgetFor(category.id, e.key) ? eco.coral : category.color,
                              backgroundColor: eco.surfaceSunken,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 104,
                          child: Text(
                            money(e.value),
                            textAlign: TextAlign.end,
                            style: context.type.labelMedium?.copyWith(fontFeatures: tabular),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SectionHeader(tr('Dépenses de {0}', [monthName(month)])),
          if (items.isEmpty)
            Text(tr('Aucune dépense dans cette catégorie ce mois-ci.'), style: context.type.bodyMedium?.copyWith(color: eco.muted))
          else
            Grouped(
              dividerIndent: 72,
              children: [
                for (final e in items)
                  ExpenseTile(expense: e, showDate: true, onTap: () => ExpenseFormScreen.open(context, e)),
              ],
            ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.type.labelSmall),
            const SizedBox(height: 3),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.titleSmall?.copyWith(fontFeatures: tabular, color: color)),
          ],
        ),
      );
}
