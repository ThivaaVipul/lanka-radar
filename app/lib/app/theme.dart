import 'package:flutter/material.dart';

/// Lanka Radar's look, Zen Mode's style with a teal accent: cool stone and paper
/// neutrals, teal for what you can act on, and ochre kept for the few things that
/// need your attention (a source that has gone quiet).
///
/// Cards and rows sit on [ColorScheme.surfaceContainerLowest]: paper white on
/// the stone page in light mode, one step above the page in dark mode. Tamil
/// text falls back to the phone's own Tamil font.
abstract final class AppTheme {
  static const fontFamily = 'Albert Sans';

  static final ThemeData light = _build(_lightColors);
  static final ThemeData dark = _build(_darkColors);

  static const _teal = Color(0xFF0F766E);

  static final _lightColors = ColorScheme.fromSeed(seedColor: _teal).copyWith(
    primary: _teal,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFCDEBE6),
    onPrimaryContainer: const Color(0xFF00201C),
    tertiary: const Color(0xFF9A5B13),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFF6E4CC),
    onTertiaryContainer: const Color(0xFF3B2306),
    surface: const Color(0xFFEEF1F1),
    onSurface: const Color(0xFF191C1C),
    onSurfaceVariant: const Color(0xFF5D6564),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF6F8F8),
    surfaceContainer: const Color(0xFFE7EBEA),
    surfaceContainerHigh: const Color(0xFFE1E5E4),
    surfaceContainerHighest: const Color(0xFFDBE0DF),
    outline: const Color(0xFF889190),
    outlineVariant: const Color(0xFFD0D6D5),
  );

  static final _darkColors =
      ColorScheme.fromSeed(
        seedColor: _teal,
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF7FD3C8),
        onPrimary: const Color(0xFF00382F),
        primaryContainer: const Color(0xFF1D4D47),
        onPrimaryContainer: const Color(0xFFC6EEE8),
        tertiary: const Color(0xFFE9B36B),
        onTertiary: const Color(0xFF452B00),
        tertiaryContainer: const Color(0xFF4A3313),
        onTertiaryContainer: const Color(0xFFFCE3C0),
        surface: const Color(0xFF101414),
        onSurface: const Color(0xFFE1E6E5),
        onSurfaceVariant: const Color(0xFFA7B1AF),
        surfaceContainerLowest: const Color(0xFF191E1E),
        surfaceContainerLow: const Color(0xFF1C2121),
        surfaceContainer: const Color(0xFF212727),
        surfaceContainerHigh: const Color(0xFF272D2D),
        surfaceContainerHighest: const Color(0xFF2E3434),
        outline: const Color(0xFF7A8483),
        outlineVariant: const Color(0xFF38403F),
      );

  static ThemeData _build(ColorScheme colors) {
    final base = ThemeData(colorScheme: colors, fontFamily: fontFamily);
    final text = _tuneText(base.textTheme);
    final card = colors.surfaceContainerLowest;
    const pill = StadiumBorder();

    return base.copyWith(
      extensions: [
        if (colors.brightness == Brightness.dark) Marks.dark else Marks.light,
      ],
      textTheme: text,
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 12),
        minVerticalPadding: 12,
        iconColor: colors.onSurfaceVariant,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: pill, textStyle: text.labelLarge),
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        side: BorderSide(color: colors.outlineVariant),
        backgroundColor: card,
        labelStyle: text.labelLarge?.copyWith(color: colors.onSurface),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(card),
        elevation: const WidgetStatePropertyAll(2),
        textStyle: WidgetStatePropertyAll(text.bodyLarge),
        hintStyle: WidgetStatePropertyAll(
          text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant),
      // Android's predictive back: the page follows your back gesture.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// One family, with the weight doing the work: semibold titles over
  /// regular body text, and tighter tracking as the size grows.
  static TextTheme _tuneText(TextTheme base) {
    TextStyle? tune(
      TextStyle? style,
      double size,
      double lineHeight,
      FontWeight weight,
      double tracking,
    ) => style?.copyWith(
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: tracking,
    );

    return base.copyWith(
      displaySmall: tune(base.displaySmall, 34, 40, FontWeight.w600, -0.6),
      headlineSmall: tune(base.headlineSmall, 26, 32, FontWeight.w600, -0.3),
      titleLarge: tune(base.titleLarge, 22, 28, FontWeight.w600, -0.2),
      titleMedium: tune(base.titleMedium, 16, 22, FontWeight.w600, 0),
      titleSmall: tune(base.titleSmall, 14, 20, FontWeight.w600, 0.1),
      bodyLarge: tune(base.bodyLarge, 16, 24, FontWeight.w400, 0.1),
      bodyMedium: tune(base.bodyMedium, 14, 20, FontWeight.w400, 0.1),
      bodySmall: tune(base.bodySmall, 12, 16, FontWeight.w400, 0.2),
      labelLarge: tune(base.labelLarge, 15, 20, FontWeight.w600, 0.1),
      labelMedium: tune(base.labelMedium, 12, 16, FontWeight.w600, 0.2),
    );
  }
}

/// Numbers that line up in columns and roll in place.
const tabular = [FontFeature.tabularFigures()];

/// A number large: the hero of a screen (44) or of a tile (30).
TextStyle bigNumber(BuildContext context, {double size = 30}) =>
    Theme.of(context).textTheme.displaySmall!.copyWith(
      fontSize: size,
      height: 1.1,
      fontWeight: FontWeight.w500,
      letterSpacing: -size / 40,
      fontFeatures: tabular,
    );

/// The colours that mark days and points: a holiday, an exam and a closing
/// date. Stepped apart from the brand's teal and ochre so that each pair stays
/// apart for colour-blind eyes, in both modes.
@immutable
class Marks extends ThemeExtension<Marks> {
  const Marks({
    required this.holiday,
    required this.exam,
    required this.closing,
  });

  static const light = Marks(
    holiday: Color(0xFF008C7E),
    exam: Color(0xFF6250D6),
    closing: Color(0xFFA65E00),
  );

  static const dark = Marks(
    holiday: Color(0xFF26A898),
    exam: Color(0xFF9085E9),
    closing: Color(0xFFC47F1F),
  );

  final Color holiday;
  final Color exam;
  final Color closing;

  static Marks of(BuildContext context) =>
      Theme.of(context).extension<Marks>() ?? light;

  @override
  Marks copyWith({Color? holiday, Color? exam, Color? closing}) => Marks(
    holiday: holiday ?? this.holiday,
    exam: exam ?? this.exam,
    closing: closing ?? this.closing,
  );

  @override
  Marks lerp(Marks? other, double t) => other == null
      ? this
      : Marks(
          holiday: Color.lerp(holiday, other.holiday, t)!,
          exam: Color.lerp(exam, other.exam, t)!,
          closing: Color.lerp(closing, other.closing, t)!,
        );
}
