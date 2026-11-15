import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Real cards are 85.6 × 54 mm.
const double cardAspectRatio = 85.6 / 54;

/// Raised-print shadow for text on a card.
final List<Shadow> cardEmboss = [
  Shadow(color: Colors.black.withValues(alpha: 0.35), offset: const Offset(0, 1), blurRadius: 2),
];

/// The body of a payment card: card proportions, a gradient from [deep] to
/// [lit], fine security arcs and a band of light. Cards keep their colours
/// in both themes, like real ones. [glow] adds a neon halo in [lit].
class PaymentCardSurface extends StatelessWidget {
  const PaymentCardSurface({
    super.key,
    required this.deep,
    required this.lit,
    required this.child,
    this.glow = false,
    this.onTap,
    this.padding = const EdgeInsetsDirectional.fromSTEB(20, 12, 6, 16),
  });

  final Color deep;
  final Color lit;
  final Widget child;
  final bool glow;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    const white = Colors.white;
    final radius = BorderRadius.circular(22);
    return AspectRatio(
      aspectRatio: cardAspectRatio,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(color: deep.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 12)),
            if (glow) ...eco.neon(lit, strength: 0.6),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [deep, lit]),
                ),
                child: Stack(
                  children: [
                    const Positioned.fill(child: CustomPaint(painter: _CardPattern())),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(color: white.withValues(alpha: 0.18)),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: const [0, 0.42, 0.5, 0.58, 1],
                            colors: [
                              white.withValues(alpha: 0.10),
                              white.withValues(alpha: 0),
                              white.withValues(alpha: 0.09),
                              white.withValues(alpha: 0),
                              Colors.black.withValues(alpha: 0.12),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(padding: padding, child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gold contact chip; grey on a card that is switched off.
class CardChip extends StatelessWidget {
  const CardChip({super.key, this.muted = false, this.size = const Size(40, 30)});

  final bool muted;
  final Size size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: size, painter: _ChipPainter(muted: muted));
}

class _ChipPainter extends CustomPainter {
  const _ChipPainter({this.muted = false});

  final bool muted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final corner = Radius.circular(size.height * 0.2);
    final body = RRect.fromRectAndRadius(rect, corner);
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: muted
              ? const [Color(0xFFC9CCD6), Color(0xFF9A9EAD), Color(0xFFBFC2CD), Color(0xFF858999)]
              : const [Color(0xFFF6DE94), Color(0xFFD4A940), Color(0xFFF1D27E), Color(0xFFB8892E)],
          stops: const [0, 0.4, 0.6, 1],
        ).createShader(rect),
    );
    final line = Paint()
      ..color = const Color(0xFF8A6420).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height > 20 ? 1 : 0.6;
    final w = size.width, h = size.height;
    // Contact pads: a centre plate and lines on each side.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.36, h * 0.22, w * 0.28, h * 0.56), corner * 0.5),
      line,
    );
    for (final y in [h / 3, h * 2 / 3]) {
      canvas.drawLine(Offset(0, y), Offset(w * 0.36, y), line);
      canvas.drawLine(Offset(w * 0.64, y), Offset(w, y), line);
    }
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h * 0.22), line);
    canvas.drawLine(Offset(w / 2, h * 0.78), Offset(w / 2, h), line);
    canvas.drawRRect(body, line..color = const Color(0xFF8A6420).withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(_ChipPainter old) => old.muted != muted;
}

/// Fine concentric arcs, like the security print on a card.
class _CardPattern extends CustomPainter {
  const _CardPattern();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.07);
    final center = Offset(size.width * 1.05, size.height * 1.1);
    for (var r = size.height * 0.35; r < size.width * 1.1; r += 14) {
      canvas.drawCircle(center, r, p);
    }
  }

  @override
  bool shouldRepaint(_CardPattern old) => false;
}
