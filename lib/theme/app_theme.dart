import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/glass.dart';

/// Tawfir design tokens: "the budget as a neon sign".
///
/// Every screen sits on a soft field of blue and yellow light. Content lives
/// on frosted glass panels that stay quiet; neon is spent in few places:
/// the month track (lit tubes), the add button, and the hero glow, which
/// changes colour with the budget.
class EcoColors extends ThemeExtension<EcoColors> {
  const EcoColors({
    required this.isDark,
    required this.blue,
    required this.blueDeep,
    required this.blueInk,
    required this.onBlue,
    required this.onBlueMuted,
    required this.yellow,
    required this.onYellow,
    required this.background,
    required this.backdropTop,
    required this.backdropBottom,
    required this.glowBlue,
    required this.glowYellow,
    required this.surface,
    required this.glassTop,
    required this.glassBottom,
    required this.glassBorder,
    required this.glassShadow,
    required this.sheet,
    required this.navFill,
    required this.heroTop,
    required this.heroBottom,
    required this.heroBorder,
    required this.surfaceSunken,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.coral,
    required this.amber,
    required this.violet,
    required this.sky,
    required this.leaf,
  });

  final bool isDark;

  /// Brand blue for filled buttons and selected states.
  final Color blue;
  final Color blueDeep;

  /// Blue for text, lines and marks on glass (neon blue in dark mode).
  final Color blueInk;
  final Color onBlue;
  final Color onBlueMuted;
  final Color yellow;
  final Color onYellow;

  /// Solid base colour (status bar, transitions).
  final Color background;
  final Color backdropTop;
  final Color backdropBottom;
  final Color glowBlue;
  final Color glowYellow;

  /// Translucent glass fill, for small surfaces (fields, chips, rows).
  final Color surface;
  final Color glassTop;
  final Color glassBottom;
  final Color glassBorder;
  final Color glassShadow;

  /// Opaque surface for dialogs, menus and sheets.
  final Color sheet;
  final Color navFill;

  /// The tinted glass of the hero cards.
  final Color heroTop;
  final Color heroBottom;
  final Color heroBorder;

  /// Recessed tone inside glass (progress tracks, icon wells).
  final Color surfaceSunken;
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color coral;
  final Color amber;
  final Color violet;
  final Color sky;
  final Color leaf;

  /// A frosted glass panel.
  BoxDecoration glass({double radius = 22, Color? tint}) => BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tint == null
              ? [glassTop, glassBottom]
              : [Color.alphaBlend(tint.withValues(alpha: isDark ? 0.16 : 0.10), glassTop), glassBottom],
        ),
        border: Border.all(color: glassBorder),
        boxShadow: [BoxShadow(color: glassShadow, blurRadius: 28, offset: const Offset(0, 10))],
      );

  /// Soft coloured light behind a neon element.
  List<BoxShadow> neon(Color color, {double strength = 1}) => [
        BoxShadow(color: color.withValues(alpha: (isDark ? 0.55 : 0.40) * strength), blurRadius: 22, spreadRadius: -2),
        if (isDark) BoxShadow(color: color.withValues(alpha: 0.25 * strength), blurRadius: 48, spreadRadius: 2),
      ];

  static const light = EcoColors(
    isDark: false,
    blue: Color(0xFF1B3FA0),
    blueDeep: Color(0xFF132E7A),
    blueInk: Color(0xFF1B3FA0),
    onBlue: Color(0xFFFFFFFF),
    onBlueMuted: Color(0xFFC6D3F7),
    yellow: Color(0xFFFFC727),
    onYellow: Color(0xFF2B2200),
    background: Color(0xFFEAF0FF),
    backdropTop: Color(0xFFF3F6FF),
    backdropBottom: Color(0xFFE2E9FB),
    glowBlue: Color(0xFF9DB6FF),
    glowYellow: Color(0xFFFFDE7A),
    surface: Color(0xB3FFFFFF),
    glassTop: Color(0xE0FFFFFF),
    glassBottom: Color(0x99FFFFFF),
    glassBorder: Color(0xFFFFFFFF),
    glassShadow: Color(0x141B3FA0),
    sheet: Color(0xFFF5F8FF),
    navFill: Color(0xBFFFFFFF),
    heroTop: Color(0xFF2F5BE0),
    heroBottom: Color(0xFF1B3FA0),
    heroBorder: Color(0x40FFFFFF),
    surfaceSunken: Color(0x141B3FA0),
    ink: Color(0xFF0E1636),
    muted: Color(0xFF59658F),
    hairline: Color(0x171B3FA0),
    coral: Color(0xFFE5395B),
    amber: Color(0xFFC2740A),
    violet: Color(0xFF6650C8),
    sky: Color(0xFF0F8BA0),
    leaf: Color(0xFF1F9D6B),
  );

  static const dark = EcoColors(
    isDark: true,
    blue: Color(0xFF3060F0),
    blueDeep: Color(0xFF1B3FA0),
    blueInk: Color(0xFF8AABFF),
    onBlue: Color(0xFFFFFFFF),
    onBlueMuted: Color(0xFFB9C8FF),
    yellow: Color(0xFFFFCC1A),
    onYellow: Color(0xFF241B00),
    background: Color(0xFF0A0F2E),
    backdropTop: Color(0xFF0E1544),
    backdropBottom: Color(0xFF070A24),
    glowBlue: Color(0xFF2F5BEA),
    // Over deep blue, yellow light turns muddy: the warm pool is violet at night.
    glowYellow: Color(0xFF6C4DFF),
    surface: Color(0x14FFFFFF),
    glassTop: Color(0x1CFFFFFF),
    glassBottom: Color(0x08FFFFFF),
    glassBorder: Color(0x24FFFFFF),
    glassShadow: Color(0x00000000),
    sheet: Color(0xFF121A46),
    navFill: Color(0xA6141C4C),
    heroTop: Color(0x993060F0),
    heroBottom: Color(0x661B3FA0),
    heroBorder: Color(0x668AABFF),
    surfaceSunken: Color(0x40000318),
    ink: Color(0xFFEEF2FF),
    muted: Color(0xFF9AA5D6),
    hairline: Color(0x1AFFFFFF),
    coral: Color(0xFFFF5C7A),
    amber: Color(0xFFFFB547),
    violet: Color(0xFFB194FF),
    sky: Color(0xFF4FD8EB),
    leaf: Color(0xFF3EE6A8),
  );

  @override
  EcoColors copyWith() => this;

  @override
  EcoColors lerp(ThemeExtension<EcoColors>? other, double t) => t < 0.5 ? this : (other as EcoColors? ?? this);
}

extension EcoTheme on BuildContext {
  EcoColors get eco => Theme.of(this).extension<EcoColors>()!;
  TextTheme get type => Theme.of(this).textTheme;
}

const String displayFont = 'Bricolage';
const String bodyFont = 'Instrument';
const List<FontFeature> tabular = [FontFeature.tabularFigures()];

/// Paints the glowing backdrop under every page, inside the transition so
/// pages stay opaque while they slide.
class _BackdropTransitions extends PageTransitionsBuilder {
  const _BackdropTransitions(this.base);

  final PageTransitionsBuilder base;

  @override
  Duration get transitionDuration => base.transitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => base.delegatedTransition;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      base.buildTransitions(route, context, animation, secondaryAnimation, GlowBackdrop(child: child));
}

class AppTheme {
  /// Status bar icons that stay readable on the backdrop.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) => brightness == Brightness.light
      ? SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent)
      : SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent);

  static ThemeData build(Brightness brightness) {
    final c = brightness == Brightness.light ? EcoColors.light : EcoColors.dark;
    final scheme = ColorScheme.fromSeed(seedColor: c.blue, brightness: brightness).copyWith(
      primary: c.blue,
      onPrimary: c.onBlue,
      secondary: c.yellow,
      onSecondary: c.onYellow,
      error: c.coral,
      onError: Colors.white,
      surface: c.sheet,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.sheet,
      surfaceContainerLow: c.sheet,
      surfaceContainer: c.sheet,
      surfaceContainerHigh: c.sheet,
      surfaceContainerHighest: c.surfaceSunken,
      outline: c.muted,
      outlineVariant: c.hairline,
      inverseSurface: c.ink,
      onInverseSurface: c.background,
    );

    TextStyle display(double size, FontWeight w, double tracking, {double height = 1.1}) => TextStyle(
        fontFamily: displayFont, fontSize: size, fontWeight: w, letterSpacing: tracking, height: height, color: c.ink);
    TextStyle body(double size, FontWeight w, {double height = 1.45, Color? color}) =>
        TextStyle(fontFamily: bodyFont, fontSize: size, fontWeight: w, height: height, color: color ?? c.ink);

    // Scale ~1.25: 12.5 / 14 / 16 / 20 / 25 / 32 / 46
    final textTheme = TextTheme(
      displayLarge: display(46, FontWeight.w700, -1.6, height: 1.0),
      displayMedium: display(32, FontWeight.w700, -0.9),
      headlineMedium: display(28, FontWeight.w700, -0.7),
      headlineSmall: display(25, FontWeight.w700, -0.5),
      titleLarge: display(20, FontWeight.w700, -0.3, height: 1.2),
      titleMedium: body(16, FontWeight.w600, height: 1.3),
      titleSmall: body(14, FontWeight.w600, height: 1.3),
      bodyLarge: body(16, FontWeight.w400),
      bodyMedium: body(14, FontWeight.w400),
      bodySmall: body(12.5, FontWeight.w400, color: c.muted),
      labelLarge: body(15, FontWeight.w600, height: 1.2),
      labelMedium: body(13, FontWeight.w600, height: 1.2),
      labelSmall: body(11.5, FontWeight.w600, height: 1.2, color: c.muted),
    );

    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c.glassBorder),
    );
    const base = FadeForwardsPageTransitionsBuilder();
    final transitions = _BackdropTransitions(FadeForwardsPageTransitionsBuilder(backgroundColor: c.background));
    final sheetShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: BorderSide(color: c.glassBorder),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: c.sheet,
      fontFamily: bodyFont,
      textTheme: textTheme,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        for (final p in TargetPlatform.values) p: p == TargetPlatform.android ? transitions : _BackdropTransitions(base),
      }),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        // Clear over the backdrop; frosted once content scrolls underneath.
        backgroundColor: WidgetStateColor.resolveWith((states) => states.contains(WidgetState.scrolledUnder)
            ? c.backdropTop.withValues(alpha: 0.92)
            : Colors.transparent),
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        systemOverlayStyle: overlayStyle(brightness),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(borderSide: BorderSide(color: c.blueInk, width: 1.6)),
        errorBorder: field.copyWith(borderSide: BorderSide(color: c.coral)),
        focusedErrorBorder: field.copyWith(borderSide: BorderSide(color: c.coral, width: 1.6)),
        labelStyle: body(15, FontWeight.w500, color: c.muted),
        floatingLabelStyle: body(14, FontWeight.w600, color: c.blueInk),
        hintStyle: body(15, FontWeight.w400, color: c.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.blue,
          foregroundColor: c.onBlue,
          minimumSize: const Size(64, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.surface,
          minimumSize: const Size(64, 50),
          side: BorderSide(color: c.glassBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.blueInk, textStyle: textTheme.labelMedium),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: c.glassBorder)),
          backgroundColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? c.blue : c.surface),
          foregroundColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? c.onBlue : c.ink),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.blue,
        side: BorderSide(color: c.glassBorder),
        shape: const StadiumBorder(),
        labelStyle: body(13.5, FontWeight.w600),
        secondaryLabelStyle: body(13.5, FontWeight.w600, color: c.onBlue),
        checkmarkColor: c.onBlue,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.isDark ? c.sheet : c.ink,
        contentTextStyle: body(14, FontWeight.w500, color: c.isDark ? c.ink : c.background),
        actionTextColor: c.yellow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: c.isDark ? BorderSide(color: c.glassBorder) : BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.sheet,
        surfaceTintColor: Colors.transparent,
        shape: sheetShape,
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.sheet,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.muted.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: c.glassBorder),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(color: c.sheet, surfaceTintColor: Colors.transparent, shape: sheetShape),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.sheet,
        surfaceTintColor: Colors.transparent,
        shape: sheetShape,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.blueInk, linearTrackColor: c.surfaceSunken),
    );
  }
}
