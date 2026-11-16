import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Draws the mark centred on [center] with diameter [s]. Shared by the
/// widget and the launcher-icon generator (tool/render_icon_test.dart).
void paintEcoMark(Canvas canvas, Offset center, double s, Color coin, Color leaf) {
  canvas.drawCircle(center, s / 2, Paint()..color = coin);
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(-math.pi / 4);
  final w = s * 0.34;
  final h = s * 0.34;
  final path = Path()
    ..moveTo(0, -h)
    ..quadraticBezierTo(w, -h * 0.2, 0, h)
    ..quadraticBezierTo(-w, -h * 0.2, 0, -h)
    ..close();
  canvas.drawPath(path, Paint()..color = leaf);
  canvas.drawLine(
      Offset(0, -h * 0.55),
      Offset(0, h * 0.85),
      Paint()
        ..color = coin
        ..strokeWidth = s * 0.035
        ..strokeCap = StrokeCap.round);
  canvas.restore();
}

/// The Tawfir mark: a yellow coin with a blue leaf cut through it.
class EcoMark extends StatelessWidget {
  const EcoMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return CustomPaint(size: Size.square(size), painter: _MarkPainter(eco.yellow, eco.blue));
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.coin, this.leaf);

  final Color coin;
  final Color leaf;

  @override
  void paint(Canvas canvas, Size size) =>
      paintEcoMark(canvas, Offset(size.width / 2, size.height / 2), size.width, coin, leaf);

  @override
  bool shouldRepaint(_MarkPainter old) => old.coin != coin || old.leaf != leaf;
}

/// Circular progress used for savings goals.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.progress, this.size = 56, this.stroke = 6, this.color, this.child});

  final double progress;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(progress.clamp(0, 1), stroke, eco.surfaceSunken, color ?? eco.blueInk),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.stroke, this.track, this.color);

  final double progress;
  final double stroke;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, 0, math.pi * 2, false, p..color = track);
    if (progress > 0) canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * progress, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

/// Round avatar with the user's initial.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.initial, this.size = 44});

  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: eco.blue, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: displayFont,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
          color: eco.yellow,
        ),
      ),
    );
  }
}
