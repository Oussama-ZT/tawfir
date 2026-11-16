import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../models/savings_goal.dart';
import '../state/app_state.dart';
import '../state/plan_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'wallets_screen.dart';
import 'paywall_screen.dart';
import '../l10n/l10n.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key, this.showTitle = true});

  /// False inside the Budgets tab, whose header shows the title and the add button.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final eco = context.eco;
    final goals = state.goals;
    final totalSaved = goals.fold(0.0, (s, g) => s + g.saved);
    final totalTarget = goals.fold(0.0, (s, g) => s + g.target);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          if (showTitle)
            SliverToBoxAdapter(
              child: ScreenTitle(
                tr('Objectifs'),
                trailing: IconButton.filledTonal(
                  tooltip: tr('Nouvel objectif'),
                  onPressed: () => showGoalForm(context),
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
            ),
          if (!showTitle) const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (goals.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.savings_outlined,
                title: tr('Épargnez pour un projet'),
                message:
                    tr('Un voyage, un fonds d\'urgence, un ordinateur : fixez un montant et une date, Tawfir calcule combien mettre de côté chaque mois.'),
                action: FilledButton(onPressed: () => showGoalForm(context), child: Text(tr('Créer un objectif'))),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32 + MediaQuery.paddingOf(context).bottom),
              sliver: SliverList.list(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 16),
                    child: Text(
                      tr('{0} épargnés sur {1} visés.', [money(totalSaved), money(totalTarget)]),
                      style: context.type.bodyMedium?.copyWith(color: eco.muted),
                    ),
                  ),
                  for (final g in goals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _GoalCard(goal: g),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final SavingsGoal goal;

  Future<void> _move(BuildContext context, {required bool deposit}) async {
    final state = context.read<AppState>();
    final value = await showAmountDialog(
      context,
      title: deposit ? tr('Ajouter à « {0} »', [goal.name]) : tr('Retirer de « {0} »', [goal.name]),
      confirmLabel: deposit ? tr('Ajouter') : tr('Retirer'),
      helper: deposit ? null : tr('Épargne actuelle : {0}', [money(goal.saved)]),
    );
    if (value != null) await state.contribute(goal, deposit ? value : -value);
  }

  Future<void> _onMenu(BuildContext context, String action) async {
    final state = context.read<AppState>();
    if (action == 'edit' && state.isGoalFrozen(goal)) {
      await explainFrozen(context, frozen: tr('L\'objectif « {0} » est gelé', [goal.name]), needed: Plan.pro);
    } else if (action == 'edit') {
      await showGoalForm(context, goal);
    } else if (action == 'delete') {
      final ok = await confirm(
        context,
        title: tr('Supprimer « {0} » ?', [goal.name]),
        message: tr('L\'objectif et son épargne enregistrée seront supprimés.'),
        confirmLabel: tr('Supprimer'),
        destructive: true,
      );
      if (ok) await state.deleteGoal(goal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final frozen = context.watch<AppState>().isGoalFrozen(goal);
    final deadline = goal.deadline;
    final now = DateTime.now();
    String? pace;
    Color? paceColor;
    if (goal.isReached) {
      pace = tr('Objectif atteint');
      paceColor = eco.leaf;
    } else if (deadline != null) {
      if (deadline.isBefore(now)) {
        pace = tr('Échéance dépassée en {0}', [monthYear(deadline).toLowerCase()]);
        paceColor = eco.coral;
      } else {
        final months = math.max(1, (deadline.difference(now).inDays / 30.44).ceil());
        pace = tr('{0} par mois jusqu\'en {1}', [moneyApprox(goal.remaining / months), monthYear(deadline).toLowerCase()]);
      }
    }

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 18, 6, 14),
      decoration: eco.glass(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProgressRing(
                progress: goal.progress,
                size: 64,
                stroke: 7,
                color: goal.isReached ? eco.leaf : eco.blueInk,
                child: Text(percent(goal.progress), style: context.type.labelMedium?.copyWith(fontFeatures: tabular)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.name, style: context.type.titleMedium),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(child: AmountText(goal.saved, style: context.type.titleLarge)),
                        Text(tr('  sur {0}', [money(goal.target)]), style: context.type.bodySmall),
                      ],
                    ),
                    if (pace != null) ...[
                      const SizedBox(height: 6),
                      Text(pace, style: context.type.bodySmall?.copyWith(color: paceColor ?? eco.blueInk)),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Options'),
                icon: Icon(Icons.more_vert_rounded, color: eco.muted),
                onSelected: (a) => _onMenu(context, a),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('Modifier'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Supprimer'))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (frozen)
            TextButton.icon(
              onPressed: () =>
                  explainFrozen(context, frozen: tr('L\'objectif « {0} » est gelé', [goal.name]), needed: Plan.pro),
              icon: Icon(Icons.lock_outline_rounded, size: 18, color: eco.muted),
              label: Text(tr('Objectif gelé, le réactiver avec Pro'), style: TextStyle(color: eco.muted)),
            )
          else
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _move(context, deposit: true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 42),
                    backgroundColor: eco.surfaceSunken,
                    foregroundColor: eco.ink,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(tr('Ajouter')),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: goal.saved > 0 ? () => _move(context, deposit: false) : null,
                  child: Text(tr('Retirer')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet to create or edit a goal. Creating one past the Starter
/// limit opens the plans screen first.
Future<void> showGoalForm(BuildContext context, [SavingsGoal? goal]) async {
  if (goal == null) {
    final allowed = context.read<PlanState>().canAddGoal(context.read<AppState>().goals.length);
    final ok = await requirePlan(
      context,
      allowed: allowed,
      needed: Plan.pro,
      reason: tr('Starter permet {0} objectifs. Avec Pro, créez-en autant que vous voulez.', [Plan.starter.goalLimit]),
    );
    if (!ok || !context.mounted) return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GoalForm(goal: goal),
  );
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({this.goal});

  final SavingsGoal? goal;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _saved;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _name = TextEditingController(text: g?.name ?? '');
    _target = TextEditingController(text: g == null ? '' : g.target.toStringAsFixed(0));
    _saved = TextEditingController(text: g == null || g.saved == 0 ? '' : g.saved.toStringAsFixed(0));
    _deadline = g?.deadline;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime(now.year, now.month + 6, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 30),
      helpText: tr('Date à laquelle atteindre l\'objectif'),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final existing = widget.goal;
    final target = parseAmount(_target.text)!;
    final saved = parseAmount(_saved.text) ?? 0;
    if (existing == null) {
      await state.addGoal(
        SavingsGoal(
          name: _name.text.trim(),
          target: target,
          saved: saved,
          deadline: _deadline,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      await state.updateGoal(
        existing.copyWith(
          name: _name.text.trim(),
          target: target,
          saved: saved,
          deadline: _deadline,
          clearDeadline: _deadline == null,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 16),
                child: Text(
                  widget.goal == null ? tr('Nouvel objectif') : tr('Modifier l\'objectif'),
                  style: context.type.headlineSmall,
                ),
              ),
              TextFormField(
                controller: _name,
                autofocus: widget.goal == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Nom'), hintText: tr('Voyage, fonds d\'urgence…')),
                validator: (v) => (v == null || v.trim().isEmpty) ? tr('Donnez un nom à l\'objectif.') : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _target,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('Montant visé'), suffixText: currencySymbol),
                      validator: (v) {
                        final value = parseAmount(v ?? '');
                        return value == null || value <= 0 ? tr('Montant supérieur à 0.') : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _saved,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('Déjà épargné'), suffixText: currencySymbol),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final value = parseAmount(v);
                        return value == null || value < 0 ? tr('Montant invalide.') : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Material(
                color: eco.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: eco.hairline),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickDeadline,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
                    child: Row(
                      children: [
                        Icon(Icons.event_outlined, color: eco.muted),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Échéance (facultatif)'), style: context.type.bodySmall),
                              Text(
                                _deadline == null ? tr('Aucune date') : longDate(_deadline!),
                                style: context.type.titleSmall,
                              ),
                            ],
                          ),
                        ),
                        if (_deadline != null)
                          IconButton(
                            tooltip: tr('Retirer la date'),
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() => _deadline = null),
                          )
                        else
                          const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: Text(widget.goal == null ? tr('Créer l\'objectif') : tr('Enregistrer'))),
            ],
          ),
        ),
      ),
    );
  }
}
