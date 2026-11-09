import 'package:flutter/material.dart';

/// The house palette (InTouch `app.css`), as a theme extension. Every colour in the UI comes from
/// here; a literal colour in a widget is a bug.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.text,
    required this.dim,
    required this.muted,
    required this.accent,
    required this.ok,
    required this.warn,
    required this.bad,
  });

  final Color bg, panel, panel2, line, text, dim, muted, accent, ok, warn, bad;

  Color get accentSoft => accent.withValues(alpha: 0.14);

  /// A border that must be seen on the dark theme (mixed from muted, not line).
  Color get frame => Color.lerp(line, muted, 0.35)!;

  static const dark = AppTokens(
    bg: Color(0xFF0F1216),
    panel: Color(0xFF171B21),
    panel2: Color(0xFF1D222A),
    line: Color(0xFF2A313B),
    text: Color(0xFFE6E9EE),
    dim: Color(0xFFAEB9C7),
    muted: Color(0xFF8794A5),
    accent: Color(0xFF4D9DFF),
    ok: Color(0xFF35C48A),
    warn: Color(0xFFE0A83A),
    bad: Color(0xFFE5544B),
  );

  static const light = AppTokens(
    bg: Color(0xFFF6F7F9),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFF0F2F5),
    line: Color(0xFFDDE1E7),
    text: Color(0xFF14181D),
    dim: Color(0xFF445060),
    muted: Color(0xFF5F6B79),
    accent: Color(0xFF1266D6),
    ok: Color(0xFF35C48A),
    warn: Color(0xFFE0A83A),
    bad: Color(0xFFE5544B),
  );

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      bg: l(bg, other.bg),
      panel: l(panel, other.panel),
      panel2: l(panel2, other.panel2),
      line: l(line, other.line),
      text: l(text, other.text),
      dim: l(dim, other.dim),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      ok: l(ok, other.ok),
      warn: l(warn, other.warn),
      bad: l(bad, other.bad),
    );
  }
}

extension TokensContext on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}

/// Monospace for IDs, MACs and hex.
const monoFamilies = ['Cascadia Mono', 'Consolas', 'Roboto Mono', 'Menlo', 'monospace'];

TextStyle monoStyle(BuildContext context, {double size = 12.5, Color? color, FontWeight? weight}) =>
    TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: monoFamilies,
      fontSize: size,
      color: color ?? context.tokens.text,
      fontWeight: weight,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// 11.5 px uppercase label in `dim`, weight 600 — table headers, tile labels, field labels.
TextStyle labelStyle(BuildContext context) => TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: context.tokens.dim,
    );

const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(AppTokens t, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: brightness == Brightness.dark ? t.bg : Colors.white,
    secondary: t.accent,
    onSecondary: Colors.white,
    error: t.bad,
    onError: Colors.white,
    surface: t.panel,
    onSurface: t.text,
    surfaceContainerHighest: t.panel2,
    outline: t.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.panel,
    dividerColor: t.line,
    extensions: [t],
    visualDensity: VisualDensity.compact,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: t.text, displayColor: t.text).copyWith(
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13, color: t.text),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12, color: t.dim),
        ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.panel2,
        border: Border.all(color: t.frame),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: t.text, fontSize: 12.5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: t.panel2,
      hintStyle: TextStyle(color: t.muted, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: t.line)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: t.frame)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: t.accent)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(t.line),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: brightness == Brightness.dark ? t.bg : Colors.white,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        side: BorderSide(color: t.frame),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.accent, textStyle: const TextStyle(fontSize: 13)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: t.frame)),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.text : t.dim),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accentSoft : Colors.transparent),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
        visualDensity: VisualDensity.compact,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : t.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accentSoft : t.panel2),
      trackOutlineColor: WidgetStatePropertyAll(t.frame),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      inactiveTrackColor: t.line,
      thumbColor: t.accent,
      overlayColor: t.accentSoft,
      showValueIndicator: ShowValueIndicator.never,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: t.panel, shape: const RoundedRectangleBorder()),
    popupMenuTheme: PopupMenuThemeData(
      color: t.panel,
      textStyle: TextStyle(color: t.text, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: t.frame)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.panel2,
      contentTextStyle: TextStyle(color: t.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
