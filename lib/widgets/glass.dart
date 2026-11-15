import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/session_state.dart';

import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

/// Colours of one backdrop: a vertical wash and two pools of light.
class _Scene {
  const _Scene(this.top, this.bottom, this.blue, this.blueAlpha, this.yellow, this.yellowAlpha);

  final Color top, bottom, blue, yellow;
  final double blueAlpha, yellowAlpha;

  @override
  bool operator ==(Object other) =>
      other is _Scene &&
      other.top == top &&
      other.bottom == bottom &&
      other.blue == blue &&
      other.yellow == yellow &&
      other.blueAlpha == blueAlpha &&
      other.yellowAlpha == yellowAlpha;

  @override
  int get hashCode => Object.hash(top, bottom, blue, yellow, blueAlpha, yellowAlpha);

  static const night = _Scene(Color(0xFF13207A), Color(0xFF070B2C), Color(0xFF3B6BFF), 0.55, Color(0xFF7B5CFF), 0.30);
}

/// The light behind every page: blue from the top left, a warm yellow pool
/// on the right, a faint blue echo at the bottom.
class GlowBackdrop extends StatelessWidget {
  const GlowBackdrop({super.key, required this.child, this.night = false});

  final Widget child;

  /// The deep blue scene of the welcome, sign-in and plans screens,
  /// whatever the theme.
  final bool night;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final scene = night
        ? _Scene.night
        : _Scene(eco.backdropTop, eco.backdropBottom, eco.glowBlue, eco.isDark ? 0.42 : 0.55, eco.glowYellow,
            eco.isDark ? 0.22 : 0.50);
    return CustomPaint(
      painter: _BackdropPainter(scene),
      isComplex: true,
      willChange: false,
      child: child,
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.s);

  final _Scene s;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [s.top, s.bottom]),
    );
    void pool(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(center, radius, [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.35),
            color.withValues(alpha: 0),
          ], [0, 0.45, 1]),
      );
    }

    final w = size.width;
    pool(Offset(w * 0.05, size.height * 0.02), w * 0.95, s.blue, s.blueAlpha);
    pool(Offset(w * 1.02, size.height * 0.38), w * 0.75, s.yellow, s.yellowAlpha);
    pool(Offset(w * 0.1, size.height * 1.02), w * 0.8, s.blue, s.blueAlpha * 0.55);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.s != s;
}

/// A frosted glass panel.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.radius = 22, this.padding, this.tint});

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: context.eco.glass(radius: radius, tint: tint),
        child: child,
      );
}

/// Tinted blue glass with real blur and a neon glow around it. [glow]
/// carries meaning: the hero glows pink once the budget is exceeded.
class NeonHero extends StatelessWidget {
  const NeonHero({super.key, required this.child, this.glow, this.padding = const EdgeInsetsDirectional.fromSTEB(22, 22, 22, 18)});

  final Widget child;
  final Color? glow;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final radius = BorderRadius.circular(30);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: eco.neon(glow ?? eco.blue, strength: 0.85)),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [eco.heroTop, eco.heroBottom],
              ),
              border: Border.all(color: glow?.withValues(alpha: 0.55) ?? eco.heroBorder),
            ),
            // Light catching the top edge of the glass.
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: const Alignment(0, -0.2),
                colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Round glass button for small actions in headers.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.size = 44});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: eco.glassBorder)),
        child: Ink(
          decoration: BoxDecoration(shape: BoxShape.circle, color: eco.surface),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(dimension: size, child: Icon(icon, size: 21, color: eco.ink)),
          ),
        ),
      ),
    );
  }
}

/// Switches between light and dark, from the home header.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassIconButton(
      icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      tooltip: dark ? tr('Passer en mode clair') : tr('Passer en mode sombre'),
      onPressed: () => context.read<SessionState>().setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}

/// Screen title that is also the switch between two views: the current one
/// lit with a neon underline, the other dimmed beside it.
class TitleTabs extends StatelessWidget {
  const TitleTabs({super.key, required this.labels, required this.selected, required this.onSelected});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    final base = context.type.displayMedium!.copyWith(fontSize: 30);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsetsDirectional.only(end: i == labels.length - 1 ? 0 : 20),
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: base.copyWith(color: i == selected ? eco.ink : eco.muted.withValues(alpha: 0.55)),
                        child: Text(labels[i]),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: i == selected ? 28 : 0,
                        height: 4,
                        decoration: BoxDecoration(
                          color: eco.yellow,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: i == selected ? eco.neon(eco.yellow, strength: 0.7) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
