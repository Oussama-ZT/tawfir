import 'package:material_ui/material_ui.dart';

import '../widgets/glass.dart';
import 'budgets_screen.dart';
import 'goals_screen.dart';
import '../l10n/l10n.dart';

/// The Budgets tab: monthly budgets and savings goals, switched from the
/// title itself.
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TitleTabs(
                    labels: [tr('Budgets'), tr('Objectifs')],
                    selected: _tab,
                    onSelected: (i) => setState(() => _tab = i),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _tab == 1
                      ? GlassIconButton(
                          key: const ValueKey('add-goal'),
                          icon: Icons.add_rounded,
                          tooltip: tr('Nouvel objectif'),
                          onPressed: () => showGoalForm(context),
                        )
                      : const SizedBox(width: 44, height: 44),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [BudgetsScreen(showTitle: false), GoalsScreen(showTitle: false)],
            ),
          ),
        ],
      ),
    );
  }
}
