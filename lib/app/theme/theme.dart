import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

ThemeData buildTheme(ThottamTokens t) {
  TextStyle style(double size, FontWeight weight, {bool heading = false}) =>
      TextStyle(
        fontFamily: heading ? t.headingFamily : t.bodyFamily,
        fontFamilyFallback: t.bodyFallback,
        fontSize: size,
        fontWeight: weight,
        height: t.lineHeight,
        color: t.ink,
        // Tabular figures everywhere, so every amount lines up.
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  final text = TextTheme(
    displayLarge: style(t.displaySize, FontWeight.w700, heading: true),
    headlineMedium: style(t.screenTitleSize, FontWeight.w700, heading: true),
    titleLarge: style(t.sectionTitleSize, FontWeight.w600, heading: true),
    titleMedium: style(t.cardTitleSize, FontWeight.w700, heading: true),
    bodyLarge: style(t.bodySize, FontWeight.w600),
    bodyMedium: style(t.bodySize, FontWeight.w400),
    bodySmall: style(t.captionSize, FontWeight.w400).copyWith(color: t.muted),
    labelLarge: style(t.primaryButtonTextSize, FontWeight.w600, heading: true),
    labelSmall: style(t.tabLabelSize, FontWeight.w500),
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(t.buttonRadius),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: t.primary,
      onPrimary: t.onPrimary,
      secondary: t.accent,
      surface: t.surface,
      onSurface: t.ink,
      error: t.danger,
      outline: t.line,
      outlineVariant: t.lineSoft,
    ),
    scaffoldBackgroundColor: t.ground,
    fontFamily: t.bodyFamily,
    fontFamilyFallback: t.bodyFallback,
    textTheme: text,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    dividerColor: t.lineSoft,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        minimumSize: Size.fromHeight(t.primaryButtonHeight),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.primaryDark,
        minimumSize: Size.fromHeight(t.minTouch),
        side: BorderSide(color: t.primary, width: t.outlineWidth),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.toast,
      contentTextStyle: text.bodyMedium!.copyWith(color: t.onToast),
    ),
    extensions: const [ThottamTokens.standard],
  );
}
