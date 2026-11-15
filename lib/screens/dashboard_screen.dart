import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/insights_service.dart';
import '../state/app_state.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/budget_card.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/common.dart';
import '../widgets/expense_tile.dart';
import '../models/savings_goal.dart';
import '../widgets/glass.dart';
import '../widgets/insight_card.dart';
import '../widgets/tour.dart';
import 'expense_form_screen.dart';
import 'goals_screen.dart';
import 'home_shell.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'wallets_screen.dart';
import '../l10n/l10n.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = context.watch<SessionState>().user!;
    final now = DateTime.now();
    final eco = context.eco;
    final setupDone = state.totalBudget > 0 && state.expenses.isNotEmpty && state.goals.isNotEmpty;
    final byCategory = state.byCategory(now);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 0, 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Bonjour,'), style: context.type.bodyMedium?.copyWith(color: eco.muted)),
                      Text(user.firstName, style: context.type.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const ThemeToggleButton(),
                const SizedBox(width: 10),
                Semantics(
                  key: TourKeys.profile,
                  button: true,
                  label: tr('Profil et réglages'),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                    child: InitialAvatar(initial: user.initial),
                  ),
                ),
              ],
            ),
          ),
          const _MonthCloseCard(),
          KeyedSubtree(
            key: TourKeys.budgetCard,
            child: BudgetCard(month: now, onTap: () => onNavigate(HomeShell.budgets)),
          ),
          if (state.wallets.isNotEmpty) ...[
            SectionHeader(
              state.hasSeveralWallets ? tr('Portefeuilles') : tr('Portefeuille'),
              action: tr('Ouvrir'),
              onAction: () => HomeShell.showWallet(context, null),
            ),
            SizedBox(
              key: TourKeys.wallets,
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: state.wallets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => WalletChip(wallet: state.wallets[i]),
              ),
            ),
          ],
          if (!setupDone) _StartChecklist(onNavigate: onNavigate),
          if (state.insights.isNotEmpty) ...[
            SectionHeader(
              tr('Conseils'),
              action: tr('Tout voir'),
              onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightsScreen())),
            ),
            Grouped(
              dividerIndent: 66,
              children: [for (final i in InsightsService.highlights(state.insights)) InsightRow(insight: i)],
            ),
          ],
          if (byCategory.isNotEmpty) ...[
            SectionHeader(tr('Répartition de {0}', [monthName(now)])),
            Grouped(children: [CategoryPieChart(data: byCategory)]),
          ],
          if (state.expenses.isNotEmpty) ...[
            SectionHeader(tr('Récentes'), action: tr('Tout voir'), onAction: () => onNavigate(HomeShell.expenses)),
            Grouped(
              dividerIndent: 72,
              children: [
                for (final e in state.expenses.take(5))
                  ExpenseTile(expense: e, showDate: true, onTap: () => ExpenseFormScreen.open(context, e)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// First steps for a new account. A real sequence, so the steps are numbered.
class _StartChecklist extends StatelessWidget {
  const _StartChecklist({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final eco = context.eco;
    final steps = [
      (
        tr('Fixez votre budget du mois'),
        tr('EcoBudget vous préviendra avant un dépassement.'),
        state.totalBudget > 0,
        () => onNavigate(HomeShell.budgets),
      ),
      (
        tr('Notez une première dépense'),
        tr('Le bouton + est toujours en bas de l\'écran.'),
        state.expenses.isNotEmpty,
        () => ExpenseFormScreen.open(context),
      ),
      (
        tr('Créez un objectif d\'épargne'),
        tr('Un voyage, un fonds d\'urgence, un ordinateur…'),
        state.goals.isNotEmpty,
        () => showGoalForm(context),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(tr('Pour bien démarrer')),
        Grouped(
          dividerIndent: 64,
          children: [
            for (var i = 0; i < steps.length; i++)
              InkWell(
                onTap: steps[i].$3 ? null : steps[i].$4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: steps[i].$3 ? eco.leaf : eco.surfaceSunken,
                          shape: BoxShape.circle,
                        ),
                        child: steps[i].$3
                            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                            : Text('${i + 1}', style: context.type.labelMedium),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              steps[i].$1,
                              style: context.type.titleSmall?.copyWith(
                                color: steps[i].$3 ? eco.muted : eco.ink,
                                decoration: steps[i].$3 ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(steps[i].$2, style: context.type.bodySmall),
                          ],
                        ),
                      ),
                      if (!steps[i].$3) Icon(Icons.chevron_right_rounded, color: eco.muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (state.expenses.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () async {
                final ok = await confirm(context,
                    title: tr('Explorer avec des données de démo ?'),
                    message: tr('Cinq mois de dépenses fictives seront ajoutés à votre compte. Vous pourrez les effacer depuis votre profil.'),
                    confirmLabel: tr('Charger la démo'));
                if (ok && context.mounted) await context.read<AppState>().loadDemoData();
              },
              child: Text(tr('Explorer avec des données de démo')),
            ),
          ),
      ],
    );
  }
}

/// At the start of a month: what was left in last month's envelope, and
/// where it goes (back to the wallets, or into a savings goal).
class _MonthCloseCard extends StatelessWidget {
  const _MonthCloseCard();

  Future<void> _toGoal(BuildContext context, DateTime month, double left, List<SavingsGoal> goals) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final goal = await showDialog<SavingsGoal>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Mettre {0} dans', [money(left)])),
        children: [
          for (final g in goals)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(tr('{0}, {1} sur {2}', [g.name, money(g.saved), money(g.target)])),
              ),
            ),
        ],
      ),
    );
    if (goal == null) return;
    await app.closeMonth(month, goal: goal);
    messenger.showSnackBar(SnackBar(content: Text(tr('{0} ajoutés à « {1} ».', [money(left), goal.name]))));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pending = app.monthToClose;
    if (pending == null) return const SizedBox.shrink();
    final eco = context.eco;
    final name = monthName(pending.month);
    final elided = 'aeiouéâ'.contains(name[0]);
    final goals = app.goals.where((g) => !g.isReached && !app.isGoalFrozen(g)).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GlassPanel(
        tint: eco.leaf,
        padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.savings_rounded, color: eco.leaf),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(elided
                        ? tr("Il reste {0} du budget d'{1}", [money(pending.left), name])
                        : tr('Il reste {0} du budget de {1}', [money(pending.left), name]), style: context.type.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr('Cet argent est toujours dans vos portefeuilles. Rendez-le libre, ou mettez-le de côté pour un objectif.'),
              style: context.type.bodySmall,
            ),
            const SizedBox(height: 12),
            if (goals.isNotEmpty)
              FilledButton(
                onPressed: () => _toGoal(context, pending.month, pending.left, goals),
                child: Text(tr('Mettre dans un objectif')),
              )
            else
              FilledButton(
                onPressed: () => showGoalForm(context),
                child: Text(tr('Créer un objectif pour l\'y mettre')),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await app.closeMonth(pending.month);
                messenger.showSnackBar(
                  SnackBar(content: Text(tr('{0} de nouveau libres dans vos portefeuilles.', [money(pending.left)]))),
                );
              },
              child: Text(tr('Rendre aux portefeuilles')),
            ),
          ],
        ),
      ),
    );
  }
}

