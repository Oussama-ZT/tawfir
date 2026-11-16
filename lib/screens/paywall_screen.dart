import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/plan.dart';
import '../services/subscription_service.dart';
import '../state/plan_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../utils/format.dart';
import '../l10n/l10n.dart';

/// Opens the plans screen. Returns the plan afterwards.
Future<Plan> showPlans(BuildContext context, {String? reason, Plan? suggested}) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PaywallScreen(reason: reason, suggested: suggested),
  ));
  return context.mounted ? context.read<PlanState>().plan : Plan.starter;
}

/// Lets an action through if allowed, otherwise explains the limit and
/// offers the [needed] plan. Returns whether the action can go ahead now.
Future<bool> requirePlan(BuildContext context, {required bool allowed, required Plan needed, required String reason}) async {
  if (allowed) return true;
  final plan = await showPlans(context, reason: reason, suggested: needed);
  return plan.index >= needed.index;
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason, this.suggested});

  /// Why the screen opened, e.g. the limit that was reached.
  final String? reason;

  /// Plan selected when the screen opens.
  final Plan? suggested;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late Plan _selected;
  String? _packageId;
  bool _busy = false;
  String? _error;

  String get _store => Platform.isIOS || Platform.isMacOS ? 'l\'App Store' : 'Google Play';

  @override
  void initState() {
    super.initState();
    final plan = context.read<PlanState>();
    _selected = widget.suggested ?? (plan.plan == Plan.starter ? Plan.pro : plan.plan);
    if (plan.offers == null) plan.loadOffers();
  }

  Future<void> _run(Future<Plan?> Function(PlanState plan) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final plan = context.read<PlanState>();
    final before = plan.plan;
    try {
      final after = await action(plan);
      if (!mounted || after == null) return;
      if (after != before) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Formule {0} activée.', [after.label]))));
        Navigator.pop(context);
      } else {
        setState(() => _error = tr('Aucun achat à restaurer pour ce compte {0}.', [_store]));
      }
    } on SubscriptionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final plan = context.watch<PlanState>();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: GlowBackdrop(
          night: true,
          child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 28, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconButton(
                            tooltip: tr('Fermer'),
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close_rounded, color: eco.onBlue),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 0, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Choisissez votre formule'),
                                    style: context.type.headlineMedium?.copyWith(color: eco.onBlue)),
                                const SizedBox(height: 8),
                                Text(
                                  widget.reason ?? tr('Votre formule actuelle : {0}.', [plan.plan.label]),
                                  style: context.type.bodyLarge?.copyWith(color: eco.onBlueMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: eco.sheet.withValues(alpha: eco.isDark ? 0.88 : 0.96),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        border: Border(top: BorderSide(color: eco.heroBorder)),
                      ),
                      padding: EdgeInsetsDirectional.fromSTEB(16, 20, 16, 16 + MediaQuery.paddingOf(context).bottom),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PlanTable(
                            current: plan.plan,
                            selected: _selected,
                            onSelect: (p) => setState(() {
                              _selected = p;
                              _packageId = null;
                              _error = null;
                            }),
                          ),
                          const SizedBox(height: 20),
                          ..._purchaseArea(context, plan),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(_error!, style: context.type.bodyMedium?.copyWith(color: eco.coral)),
                            ),
                          const Spacer(),
                          if (plan.storeAvailable)
                            TextButton(
                              onPressed: _busy ? null : () => _run((p) => p.restore()),
                              child: Text(tr('Restaurer mes achats')),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  List<Widget> _purchaseArea(BuildContext context, PlanState plan) {
    final eco = context.eco;

    if (_selected == plan.plan) {
      return [
        _Note(
          icon: Icons.verified_rounded,
          color: eco.leaf,
          text: plan.isTestPlan
              ? tr('Formule {0} active (mode test).', [plan.plan.label])
              : plan.plan.isFree
                  ? tr('C\'est votre formule actuelle, gratuite.')
                  : plan.endsAt != null
                      ? tr('Abonnement résilié : {0} reste actif jusqu\'au {1}. Ensuite, seul votre portefeuille principal reste utilisable ; les autres sont gelés, jamais supprimés.', [plan.plan.label, fullDate(plan.endsAt!)])
                      : tr('C\'est votre formule actuelle. Gérez ou résiliez l\'abonnement dans {0}.', [_store]),
        ),
        if (plan.canTestPlans && plan.isTestPlan)
          TextButton(onPressed: () => plan.setTestPlan(null), child: Text(tr('Quitter le mode test'))),
      ];
    }

    if (_selected == Plan.starter) {
      return [
        _Note(
          icon: Icons.info_outline_rounded,
          color: eco.muted,
          text: tr('Pour revenir à Starter, résiliez votre abonnement dans {0}. À la fin de la période payée, ce qui dépasse Starter sera gelé : toujours visible, mais plus utilisable. Rien n\'est supprimé.', [_store]),
        ),
      ];
    }

    final offers = plan.offersFor(_selected);
    if (!plan.storeAvailable || (plan.offers != null && offers.isEmpty)) {
      return [
        _Note(
          icon: Icons.schedule_rounded,
          color: eco.muted,
          text: tr('Les abonnements ne sont pas encore disponibles. Revenez bientôt.'),
        ),
        if (plan.canTestPlans)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: () {
                plan.setTestPlan(_selected);
                Navigator.pop(context);
              },
              child: Text(tr('Essayer {0} (mode test)', [_selected.label])),
            ),
          ),
      ];
    }

    if (plan.offers == null) {
      return const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))];
    }

    final chosen = offers.firstWhere((o) => o.id == _packageId, orElse: () => offers.first);
    return [
      for (final o in offers) ...[
        _OfferTile(offer: o, selected: o == chosen, onTap: () => setState(() => _packageId = o.id)),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
      FilledButton(
        onPressed: _busy ? null : () => _run((p) => p.purchase(chosen)),
        style: FilledButton.styleFrom(backgroundColor: eco.yellow, foregroundColor: eco.onYellow),
        child: _busy
            ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: eco.onYellow))
            : Text(tr('Choisir {0}', [_selected.label])),
      ),
      const SizedBox(height: 10),
      Text(
        tr('Renouvellement automatique, résiliable à tout moment depuis {0}.', [_store]),
        style: context.type.bodySmall,
        textAlign: TextAlign.center,
      ),
    ];
  }
}

/// Side-by-side comparison. Tapping a column selects that plan.
class _PlanTable extends StatelessWidget {
  const _PlanTable({required this.current, required this.selected, required this.onSelect});

  final Plan current;
  final Plan selected;
  final ValueChanged<Plan> onSelect;

  static String _count(int? n) => n == null ? tr('Illimités') : '$n';

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final rows = <(String, Widget Function(Plan))>[
      (tr('Portefeuilles'), (p) => _text(context, _count(p.walletLimit))),
      (tr('Cartes, épargne, noms libres'), (p) => _check(context, p.customWalletNames)),
      (tr('Portefeuilles en devises'), (p) => _check(context, p.foreignCurrencyWallets)),
      (tr('Catégories personnalisées'), (p) => _check(context, p.customCategories)),
      (tr('Objectifs d\'épargne'), (p) => _text(context, _count(p.goalLimit))),
      (tr('Budgets par catégorie'), (p) => _text(context, _count(p.categoryBudgetLimit))),
      (tr('Prêts et emprunts'), (p) => _check(context, p.debts)),
      (tr('Conseils et alertes'), (p) => _check(context, true)),
    ];

    Widget cell(Plan p, Widget child, {bool top = false, bool bottom = false}) {
      final isSelected = p == selected;
      return Expanded(
        flex: 10,
        child: Semantics(
          button: true,
          selected: isSelected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(p),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: top ? 12 : 11),
              decoration: BoxDecoration(
                color: isSelected ? eco.blueInk.withValues(alpha: 0.10) : null,
                borderRadius: BorderRadius.vertical(
                  top: top ? const Radius.circular(14) : Radius.zero,
                  bottom: bottom ? const Radius.circular(14) : Radius.zero,
                ),
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
      decoration: eco.glass(radius: 20),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(flex: 16, child: SizedBox()),
              for (final p in Plan.values)
                cell(
                  p,
                  Column(
                    children: [
                      Text(p.label,
                          style: context.type.titleSmall?.copyWith(color: p == selected ? eco.blueInk : eco.ink)),
                      const SizedBox(height: 2),
                      Text(
                        p == current ? tr('Actuelle') : (p.isFree ? tr('Gratuite') : ' '),
                        style: context.type.labelSmall?.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                  top: true,
                ),
            ],
          ),
          for (var i = 0; i < rows.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: eco.hairline))),
              child: Row(
                children: [
                  Expanded(
                    flex: 16,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Text(rows[i].$1, style: context.type.bodySmall?.copyWith(color: eco.ink)),
                    ),
                  ),
                  for (final p in Plan.values) cell(p, rows[i].$2(p), bottom: i == rows.length - 1),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _text(BuildContext context, String s) =>
      Text(s, textAlign: TextAlign.center, style: context.type.labelMedium?.copyWith(fontSize: 12));

  Widget _check(BuildContext context, bool yes) => yes
      ? Icon(Icons.check_rounded, size: 18, color: context.eco.blueInk, semanticLabel: tr('Inclus'))
      : Icon(Icons.remove_rounded, size: 18, color: context.eco.hairline, semanticLabel: tr('Non inclus'));
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.eco.glass(radius: 20),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: context.type.bodyMedium)),
        ],
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.selected, required this.onTap});

  final PlanOffer offer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: eco.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? eco.blueInk : eco.hairline, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? eco.blueInk : eco.muted),
                const SizedBox(width: 12),
                Expanded(child: Text(offer.price, style: context.type.titleMedium?.copyWith(fontFeatures: tabular))),
                Text(offer.period, style: context.type.bodyMedium?.copyWith(color: eco.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
