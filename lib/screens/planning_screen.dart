import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/plan_state.dart';
import '../state/session_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/tour.dart';
import 'budgets_screen.dart';
import 'debts_screen.dart';
import 'goals_screen.dart';
import 'home_shell.dart';
import 'report_screen.dart';
import '../l10n/l10n.dart';

/// The "Autres" tab: four boxes choose what is shown below them — budgets,
/// savings goals, the monthly report, or debts.
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  int _tab = 0;
  bool _touring = false;

  static final _boxKeys = [TourKeys.othersBudgets, TourKeys.othersGoals, TourKeys.othersReport, TourKeys.othersDebts];

  @override
  void initState() {
    super.initState();
    HomeShell.tab.addListener(_maybeTour);
  }

  @override
  void dispose() {
    HomeShell.tab.removeListener(_maybeTour);
    super.dispose();
  }

  /// The first time the tab opens (after the home tour), walk through the
  /// four boxes; each step opens its section. Ends back on the section the
  /// person was looking at.
  void _maybeTour() {
    final session = context.read<SessionState>();
    if (_touring || HomeShell.tab.value != HomeShell.budgets || !session.tourSeen || session.othersTourSeen) return;
    _touring = true;
    final before = _tab;
    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || HomeShell.tab.value != HomeShell.budgets) {
        _touring = false;
        return;
      }
      showTour(
        context,
        othersTour(
          select: (i) {
            if (mounted) setState(() => _tab = i);
          },
          debtsLocked: !context.read<PlanState>().canUseDebts,
        ),
        onDone: () {
          _touring = false;
          session.finishOthersTour();
          if (mounted) setState(() => _tab = before);
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final debtsAllowed = context.watch<PlanState>().canUseDebts;
    final now = DateTime.now();
    // (icon, label, alert dot, padlock)
    final sections = [
      (Icons.donut_small_rounded, tr('Budgets'), false, false),
      (Icons.savings_rounded, tr('Objectifs'), false, false),
      (Icons.insights_rounded, tr('Bilan'), false, false),
      // Pro and Premium only. A dot when money should already have been given back.
      (Icons.handshake_rounded, tr('Dettes'), debtsAllowed && app.debts.any((d) => d.isOverdue(now)), !debtsAllowed),
    ];
    final action = switch (_tab) {
      1 => GlassIconButton(
        key: const ValueKey('add-goal'),
        icon: Icons.add_rounded,
        tooltip: tr('Nouvel objectif'),
        onPressed: () => showGoalForm(context),
      ),
      3 when debtsAllowed && app.debts.isNotEmpty => GlassIconButton(
        key: const ValueKey('add-debt'),
        icon: Icons.add_rounded,
        tooltip: tr('Nouvelle dette'),
        onPressed: () => showDebtForm(context),
      ),
      _ => const SizedBox(width: 44, height: 44),
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 4),
            child: Row(
              children: [
                Expanded(child: Text(tr('Autres'), style: context.type.displayMedium!.copyWith(fontSize: 30))),
                AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: action),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
            child: Row(
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _SectionBox(
                      key: _boxKeys[i],
                      icon: sections[i].$1,
                      label: sections[i].$2,
                      alert: sections[i].$3,
                      locked: sections[i].$4,
                      selected: _tab == i,
                      onTap: () => setState(() => _tab = i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [BudgetsScreen(showTitle: false), GoalsScreen(showTitle: false), ReportView(), DebtsView()],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the four boxes: lit blue when its section is shown.
class _SectionBox extends StatelessWidget {
  const _SectionBox({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.alert = false,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool alert;

  /// Not in the current plan: a small padlock in the corner.
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final radius = BorderRadius.circular(20);
    final fg = selected ? Colors.white : eco.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? tr('{0}, réservé à Pro et Premium', [label]) : label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 78,
        decoration: selected
            ? BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [eco.blue, eco.blueDeep]),
                boxShadow: eco.neon(eco.blue, strength: 0.5),
              )
            : eco.glass(radius: 20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 26, color: selected ? Colors.white : eco.blueInk),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: context.type.labelMedium?.copyWith(color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (locked)
                  PositionedDirectional(
                    top: 8,
                    end: 9,
                    child: Icon(Icons.lock_rounded, size: 13, color: selected ? Colors.white70 : eco.muted),
                  ),
                if (alert)
                  PositionedDirectional(
                    top: 10,
                    end: 12,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: eco.coral,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? Colors.white : eco.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
