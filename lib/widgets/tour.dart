import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

/// The parts of the home screen the tour points at.
class TourKeys {
  static final budgetCard = GlobalKey(debugLabel: 'tour-budget');
  static final wallets = GlobalKey(debugLabel: 'tour-wallets');
  static final addButton = GlobalKey(debugLabel: 'tour-add');
  static final expensesTab = GlobalKey(debugLabel: 'tour-expenses');
  static final budgetsTab = GlobalKey(debugLabel: 'tour-budgets');
  static final profile = GlobalKey(debugLabel: 'tour-profile');

  /// The four boxes of the Autres tab.
  static final othersBudgets = GlobalKey(debugLabel: 'tour-others-budgets');
  static final othersGoals = GlobalKey(debugLabel: 'tour-others-goals');
  static final othersReport = GlobalKey(debugLabel: 'tour-others-report');
  static final othersDebts = GlobalKey(debugLabel: 'tour-others-debts');
}

class TourStep {
  const TourStep({required this.target, required this.title, required this.body, this.round = false, this.onShow});

  final GlobalKey target;
  final String title;
  final String body;

  /// A round spotlight (buttons) instead of a rounded rectangle.
  final bool round;

  /// Runs as the step comes up, e.g. to open the section it talks about.
  final VoidCallback? onShow;
}

/// The first-visit tour of the home screen.
List<TourStep> get homeTour => [
  TourStep(
    target: TourKeys.budgetCard,
    title: tr('Votre budget du mois'),
    body: tr(
      'Ce qui reste à dépenser ce mois-ci, et combien par jour. Les tubes s\'allument à mesure que vous dépensez ; la carte devient orange près de la limite, rouge au-delà. Touchez-la pour fixer votre budget.',
    ),
  ),
  TourStep(
    target: TourKeys.wallets,
    title: tr('Vos portefeuilles'),
    body: tr('Espèces, banque, carte… Touchez-en un pour voir son solde, ajouter, retirer ou transférer de l\'argent.'),
  ),
  TourStep(
    target: TourKeys.addButton,
    title: tr('Notez une dépense'),
    body: tr('Le bouton jaune est toujours là : un montant, une catégorie, et c\'est noté.'),
    round: true,
  ),
  TourStep(
    target: TourKeys.expensesTab,
    title: tr('Toutes vos dépenses'),
    body: tr('Mois par mois, à filtrer par portefeuille ou par catégorie. Glissez une dépense pour la supprimer.'),
  ),
  TourStep(
    target: TourKeys.budgetsTab,
    title: tr('Autres'),
    body: tr('Quatre cases pour choisir : le budget du mois, vos objectifs d\'épargne, le bilan du mois, et l\'argent prêté ou emprunté.'),
  ),
  TourStep(
    target: TourKeys.profile,
    title: tr('Votre profil'),
    body: tr('Devise, formule, catégories, mode clair ou sombre. Vous pourrez y revoir cette visite.'),
    round: true,
  ),
];

/// The first visit of the Autres tab: one step per box. [select] opens the
/// box's section so what is described shows below it.
List<TourStep> othersTour({required void Function(int section) select, required bool debtsLocked}) => [
  TourStep(
    target: TourKeys.othersBudgets,
    title: tr('Budgets'),
    body: tr(
      'Le budget du mois et sa répartition par catégorie. Touchez la carte du budget pour fixer le montant, ou le calculer depuis vos revenus.',
    ),
    onShow: () => select(0),
  ),
  TourStep(
    target: TourKeys.othersGoals,
    title: tr('Objectifs d\'épargne'),
    body: tr('Mettez de l\'argent de côté pour un projet : montant visé, échéance, et ce qu\'il faut épargner chaque mois pour y arriver.'),
    onShow: () => select(1),
  ),
  TourStep(
    target: TourKeys.othersReport,
    title: tr('Bilan du mois'),
    body: tr('Revenus, dépenses et épargne du mois, comparés au mois d\'avant et aux six derniers mois.'),
    onShow: () => select(2),
  ),
  TourStep(
    target: TourKeys.othersDebts,
    title: tr('Dettes'),
    body: debtsLocked
        ? tr('L\'argent prêté ou emprunté : qui vous doit, à qui vous devez, et ce qui reste à rendre. Inclus dans Pro et Premium.')
        : tr(
            'L\'argent prêté ou emprunté : qui vous doit, à qui vous devez, et ce qui reste à rendre. Le point rouge signale une échéance dépassée.',
          ),
    onShow: () => select(3),
  ),
];

/// Shows [steps] one after the other over the current screen. Steps whose
/// target is not on screen are skipped. [onDone] runs when the tour ends,
/// finished or skipped.
void showTour(BuildContext context, List<TourStep> steps, {required VoidCallback onDone}) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Tour(
      steps: [
        for (final s in steps)
          if (s.target.currentContext != null) s,
      ],
      onDone: () {
        entry.remove();
        onDone();
      },
    ),
  );
  overlay.insert(entry);
}

class _Tour extends StatefulWidget {
  const _Tour({required this.steps, required this.onDone});

  final List<TourStep> steps;
  final VoidCallback onDone;

  @override
  State<_Tour> createState() => _TourState();
}

class _TourState extends State<_Tour> with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  int _index = 0;
  Rect? _from;
  Rect? _to;

  @override
  void initState() {
    super.initState();
    if (widget.steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(0));
    }
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  Rect get _current {
    final t = Curves.easeInOutCubic.transform(_move.value);
    return Rect.lerp(_from ?? _to, _to, t) ?? Rect.zero;
  }

  /// Runs the step's [TourStep.onShow], then points at its target.
  Future<void> _focus(int i) async {
    final show = widget.steps[i].onShow;
    if (show != null) {
      show();
      // Let the section it opened lay out before measuring.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    await _spotlight(i);
  }

  /// Scrolls the step's target into view, then slides the spotlight to it.
  Future<void> _spotlight(int i) async {
    final target = widget.steps[i].target.currentContext;
    if (target == null) return _next();
    final reduce = MediaQuery.disableAnimationsOf(context);
    await Scrollable.ensureVisible(
      target,
      alignment: 0.35,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !target.mounted) return;
    final box = target.findRenderObject() as RenderBox?;
    final mine = context.findRenderObject() as RenderBox?;
    if (box == null || mine == null || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero, ancestor: mine) & box.size;
    setState(() {
      _index = i;
      _from = _to == null ? null : _current;
      _to = rect;
    });
    _move.duration = reduce ? Duration.zero : const Duration(milliseconds: 420);
    await _move.forward(from: 0);
  }

  void _next() {
    if (_index + 1 >= widget.steps.length) {
      widget.onDone();
    } else {
      _focus(_index + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final step = widget.steps.isEmpty ? null : widget.steps[_index];
    final size = MediaQuery.sizeOf(context);
    final last = _index == widget.steps.length - 1;

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _move,
        builder: (context, _) {
          final rect = _to == null ? null : _current;
          final hole = rect == null ? null : _holeFor(rect, step!.round);
          final below = hole == null || hole.center.dy < size.height * 0.5;
          return Stack(
            children: [
              // Tapping anywhere moves on; nothing under the tour is touched.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _next,
                  child: CustomPaint(
                    painter: _SpotlightPainter(hole: hole, ring: eco.yellow, scrim: _scrim(eco)),
                  ),
                ),
              ),
              if (hole != null && step != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: below ? (hole.bottom + 18).clamp(0, size.height - 260) : null,
                  bottom: below ? null : size.height - hole.top + 18,
                  child: _Card(step: step, index: _index, count: widget.steps.length, last: last, onNext: _next, onSkip: widget.onDone),
                ),
            ],
          );
        },
      ),
    );
  }

  static Color _scrim(EcoColors eco) =>
      eco.isDark ? const Color(0xFF02041A).withValues(alpha: 0.78) : const Color(0xFF0B1240).withValues(alpha: 0.74);

  static RRect _holeFor(Rect r, bool round) {
    if (round) {
      final radius = r.shortestSide / 2 + 10;
      return RRect.fromRectAndRadius(Rect.fromCircle(center: r.center, radius: radius), Radius.circular(radius));
    }
    return RRect.fromRectAndRadius(r.inflate(8), const Radius.circular(26));
  }
}

/// The scrim with a hole around the target and a neon ring along its edge.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.ring, required this.scrim});

  final RRect? hole;
  final Color ring;
  final Color scrim;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(screen, Paint()..color = scrim);
      return;
    }
    canvas.drawPath(Path.combine(PathOperation.difference, screen, Path()..addRRect(h)), Paint()..color = scrim);
    canvas.drawRRect(
      h,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = ring.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      h,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.ring != ring || old.scrim != scrim;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.step,
    required this.index,
    required this.count,
    required this.last,
    required this.onNext,
    required this.onSkip,
  });

  final TourStep step;
  final int index;
  final int count;
  final bool last;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 10),
          decoration: BoxDecoration(
            color: eco.sheet.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: eco.glassBorder),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Semantics(
              key: ValueKey(index),
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A real sequence: where you are in it.
                  Row(
                    children: [
                      for (var i = 0; i < count; i++)
                        Container(
                          margin: const EdgeInsetsDirectional.only(end: 5),
                          width: i == index ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i <= index ? eco.yellow : eco.muted.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      const Spacer(),
                      Text(tr('{0} sur {1}', [index + 1, count]), style: context.type.labelSmall),
                      const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(step.title, style: context.type.titleLarge),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Text(step.body, style: context.type.bodyMedium?.copyWith(color: eco.muted)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!last) TextButton(onPressed: onSkip, child: Text(tr('Passer la visite'))),
                      const Spacer(),
                      FilledButton(
                        onPressed: onNext,
                        style: FilledButton.styleFrom(minimumSize: const Size(110, 46)),
                        child: Text(last ? tr('C\'est parti') : tr('Suivant')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
