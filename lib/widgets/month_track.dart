import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

/// The home screen's signature: one glass tube per day of the month. Tubes
/// light up in neon yellow as the budget is used, so light running ahead of
/// "today" means spending is ahead of the calendar. Neon pink once the
/// budget is exceeded.
class MonthTrack extends StatelessWidget {
  const MonthTrack({super.key, required this.days, required this.today, required this.usedRatio});

  final int days;

  /// 1-based day of the month.
  final int today;

  /// spent / budget; null when no budget is set (only the calendar is shown).
  final double? usedRatio;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final target = usedRatio ?? 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Right to left languages read the month from the right.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    Widget paint(double ratio) => Transform.flip(
          flipX: rtl,
          child: CustomPaint(
            size: const Size(double.infinity, 42),
            painter: _TrackPainter(
              days: days,
              today: today,
              usedTicks: (ratio * days).clamp(0, days.toDouble()).toDouble(),
              lit: usedRatio != null && ratio > 1 ? eco.coral : eco.yellow,
              glass: Colors.white,
            ),
          ),
        );

    return Semantics(
      label: usedRatio == null
          ? tr('Jour {0} sur {1}', [today, days])
          : tr('Budget utilisé à {0} %, jour {1} sur {2}', [(target * 100).round(), today, days]),
      child: reduceMotion
          ? paint(target)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => paint(value),
            ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.days,
    required this.today,
    required this.usedTicks,
    required this.lit,
    required this.glass,
  });

  final int days;
  final int today;
  final double usedTicks;
  final Color lit;
  final Color glass;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    const tubeHeight = 28.0;
    final tubeWidth = (size.width - gap * (days - 1)) / days;
    final radius = Radius.circular(tubeWidth / 2);
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final halo = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (var i = 0; i < days; i++) {
      final left = i * (tubeWidth + gap);
      final tube = RRect.fromLTRBR(left, 0, left + tubeWidth, tubeHeight, radius);

      // Empty glass tube: brighter for days already gone.
      fill.color = glass.withValues(alpha: i < today ? 0.16 : 0.07);
      canvas.drawRRect(tube, fill);
      edge.color = glass.withValues(alpha: i < today ? 0.22 : 0.10);
      canvas.drawRRect(tube.deflate(0.5), edge);

      // Lit gas, partial for the tube being filled during the animation.
      final level = (usedTicks - i).clamp(0.0, 1.0);
      if (level > 0) {
        final top = tubeHeight * (1 - level);
        final gas = RRect.fromLTRBR(left, top, left + tubeWidth, tubeHeight, radius);
        halo.color = lit.withValues(alpha: 0.75 * level);
        canvas.drawRRect(gas.inflate(1.5), halo);
        fill.color = lit;
        canvas.drawRRect(gas, fill);
        // Hot white core.
        fill.color = Colors.white.withValues(alpha: 0.55);
        final core = tubeWidth * 0.18;
        if (tubeHeight - top > 12) {
          canvas.drawRRect(
          RRect.fromLTRBR(left + tubeWidth / 2 - core / 2, top + 4, left + tubeWidth / 2 + core / 2,
              tubeHeight - 4, Radius.circular(core)),
            fill,
          );
        }
      }
    }

    // Today marker under the current day.
    final cx = (today - 1) * (tubeWidth + gap) + tubeWidth / 2;
    halo.color = glass.withValues(alpha: 0.8);
    canvas.drawCircle(Offset(cx, tubeHeight + 9), 3.5, halo);
    fill.color = glass;
    canvas.drawCircle(Offset(cx, tubeHeight + 9), 3, fill);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.usedTicks != usedTicks || old.today != today || old.days != days || old.lit != lit;
}
