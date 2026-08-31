import 'package:flutter/material.dart';

import 'dsw_tokens.dart';

export 'breakpoints.dart';
export 'dsw_tokens.dart';

// ---------------------------------------------------------------------------
// Helpers — keep literal Colors out of this file; always delegate to DswTokens
// ---------------------------------------------------------------------------

TextTheme _buildTextTheme(Color baseColor) {
  const String uiFamily = 'SF Pro';
  const String codeFamily = 'SF Mono';

  TextStyle base(
    Color color,
    double size,
    double height,
    FontWeight weight, {
    String? family,
    FontStyle? style,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      fontStyle: style,
      fontFamily: family ?? uiFamily,
      fontFamilyFallback: family == codeFamily
          ? DswTokens.fontFamilyCodeFallback
          : DswTokens.fontFamilyFallback,
    );
  }

  // Map DswTokens typography scale to Material roles.
  return TextTheme(
    displayLarge: base(
      baseColor,
      DswTokens.markdownH1Size,
      DswTokens.markdownH1LineHeight,
      FontWeight.w700,
    ),
    displayMedium: base(
      baseColor,
      DswTokens.markdownH2Size,
      DswTokens.markdownH2LineHeight,
      FontWeight.w700,
    ),
    displaySmall: base(
      baseColor,
      DswTokens.markdownH3Size,
      DswTokens.markdownH3LineHeight,
      FontWeight.w700,
    ),
    headlineMedium: base(
      baseColor,
      DswTokens.markdownH4Size,
      DswTokens.markdownH4LineHeight,
      FontWeight.w600,
    ),
    headlineSmall: base(
      baseColor,
      DswTokens.fontSizeL20,
      DswTokens.lineHeightL20,
      FontWeight.w500,
    ),
    titleLarge: base(
      baseColor,
      DswTokens.fontSizeBase16,
      DswTokens.lineHeightBase16,
      FontWeight.w500,
    ),
    titleMedium: base(
      baseColor,
      DswTokens.fontSizeBase16,
      DswTokens.lineHeightBase16,
      FontWeight.w400,
    ),
    titleSmall: base(
      baseColor,
      DswTokens.fontSizeS14,
      DswTokens.lineHeightS14,
      FontWeight.w500,
    ),
    bodyLarge: base(
      baseColor,
      DswTokens.markdownBaseSize,
      DswTokens.markdownBaseLineHeight,
      FontWeight.w400,
    ),
    bodyMedium: base(
      baseColor,
      DswTokens.markdownSmallSize,
      DswTokens.markdownSmallLineHeight,
      FontWeight.w400,
    ),
    bodySmall: base(
      baseColor,
      DswTokens.fontSizeXs13,
      DswTokens.lineHeightXs13,
      FontWeight.w400,
    ),
    labelLarge: base(
      baseColor,
      DswTokens.fontSizeS14,
      DswTokens.lineHeightS14,
      FontWeight.w500,
    ),
    labelMedium: base(
      baseColor,
      DswTokens.fontSizeXxs12,
      DswTokens.lineHeightXxs12,
      FontWeight.w500,
    ),
    labelSmall: base(
      baseColor,
      DswTokens.fontSizeXxxs11,
      DswTokens.lineHeightXxxs11,
      FontWeight.w400,
    ),
  );
}

ThemeData _buildTheme({
  required Brightness brightness,
  required ColorScheme colorScheme,
  required Color scaffoldBackground,
  required Color appBarBackground,
  required Color divider,
  required DswAliases aliases,
}) {
  final bool isDark = brightness == Brightness.dark;
  final Color textBase = aliases.labelPrimary;
  final Color textSecondary = aliases.labelSecondary;

  final TextTheme textTheme = _buildTextTheme(textBase)
      .apply(bodyColor: textBase, displayColor: textBase);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    dividerColor: divider,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: appBarBackground,
      foregroundColor: textBase,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: DswTokens.transparent,
      titleTextStyle: TextStyle(
        color: textBase,
        fontSize: DswTokens.fontSizeL20,
        height: DswTokens.lineHeightL20 / DswTokens.fontSizeL20,
        fontWeight: FontWeight.w500,
        fontFamily: 'SF Pro',
        fontFamilyFallback: DswTokens.fontFamilyFallback,
      ),
      iconTheme: IconThemeData(color: textBase),
    ),
    cardTheme: CardThemeData(
      color: aliases.bgLayer2,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        side: BorderSide(color: aliases.borderL2),
      ),
    ),
    dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: aliases.buttonPrimaryFill,
        foregroundColor: aliases.labelPrimaryForeground,
        disabledBackgroundColor: aliases.buttonPrimaryDimmed,
        disabledForegroundColor: aliases.labelCaption,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
        ),
        textStyle: const TextStyle(
          fontSize: DswTokens.fontSizeS14,
          fontWeight: FontWeight.w500,
          fontFamily: 'SF Pro',
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: aliases.labelPrimary,
        side: BorderSide(color: aliases.buttonGhostActiveBorder),
        backgroundColor: aliases.buttonGhostActiveFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: aliases.labelPrimary,
        backgroundColor: DswTokens.transparent,
        overlayColor: aliases.interactiveBgHover,
      ),
    ),
    iconTheme: IconThemeData(color: textSecondary),
    chipTheme: ChipThemeData(
      backgroundColor: aliases.bgOverlay,
      selectedColor: aliases.specificSidebarNavItemActive,
      secondarySelectedColor: aliases.specificSidebarNavItemActiveAccent,
      labelStyle: TextStyle(color: textBase, fontSize: DswTokens.fontSizeS14),
      side: BorderSide(color: aliases.borderL2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: aliases.tooltipBg,
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
      ),
      textStyle: TextStyle(
        color: isDark ? DswTokens.neutralBluish00 : DswTokens.neutralBluish00,
        fontSize: DswTokens.fontSizeXxs12,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.hovered)) {
          return aliases.scrollbarHoverL1;
        }
        return aliases.scrollbarBgL1;
      }),
      trackColor: const WidgetStatePropertyAll(DswTokens.transparent),
      radius: const Radius.circular(DswTokens.radiusXs),
      thickness: const WidgetStatePropertyAll(6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: aliases.specificInputMajor,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceLg,
        vertical: DswTokens.spaceMd,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        borderSide: BorderSide(color: aliases.borderL2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        borderSide: BorderSide(color: aliases.borderL2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        borderSide: BorderSide(color: aliases.stateBusinessPrimary, width: 1.5),
      ),
      hintStyle: TextStyle(color: aliases.labelCaption),
    ),
    extensions: <ThemeExtension<dynamic>>[DswThemeExtension(aliases: aliases)],
  );
}

/// Light theme — uses [DswAliases.light] and light [ColorScheme].
ThemeData buildLightTheme() {
  const DswAliases aliases = DswAliases.light();
  return _buildTheme(
    brightness: Brightness.light,
    scaffoldBackground: aliases.bgBase,
    appBarBackground: aliases.bgBase,
    divider: aliases.borderL2,
    aliases: aliases,
    colorScheme: ColorScheme.light(
      primary: DswTokens.deepseek500,
      onPrimary: DswTokens.neutralBluish00,
      primaryContainer: DswTokens.deepseek100,
      onPrimaryContainer: DswTokens.deepseek900,
      secondary: DswTokens.neutralBluish700,
      onSecondary: DswTokens.neutralBluish00,
      error: DswTokens.red600,
      onError: DswTokens.neutralBluish00,
      surface: DswTokens.neutralBluish00,
      onSurface: DswTokens.neutralBluish1000,
      surfaceContainerHighest: DswTokens.neutralBluish50,
      onSurfaceVariant: DswTokens.neutralBluish700,
      outline: aliases.borderL2,
      outlineVariant: aliases.borderL1,
      scrim: aliases.bgMask1,
    ),
  );
}

/// Dark theme — uses [DswAliases.dark] and dark [ColorScheme].
ThemeData buildDarkTheme() {
  const DswAliases aliases = DswAliases.dark();
  return _buildTheme(
    brightness: Brightness.dark,
    scaffoldBackground: aliases.bgBase,
    appBarBackground: aliases.bgBase,
    divider: aliases.borderL2,
    aliases: aliases,
    colorScheme: ColorScheme.dark(
      primary: DswTokens.deepseek400,
      onPrimary: DswTokens.neutralBluish1000,
      primaryContainer: DswTokens.deepseek800,
      onPrimaryContainer: DswTokens.neutralBluish50,
      secondary: DswTokens.neutralBluish300,
      onSecondary: DswTokens.neutralBluish900,
      error: DswTokens.red400,
      onError: DswTokens.neutralBluish1000,
      surface: DswTokens.neutralBluish950,
      onSurface: DswTokens.neutralBluish50,
      surfaceContainerHighest: DswTokens.neutralBluish850,
      onSurfaceVariant: DswTokens.neutralBluish300,
      outline: aliases.borderL2,
      outlineVariant: aliases.borderL1,
      scrim: aliases.bgMask1,
    ),
  );
}

/// Theme extension exposing semantic aliases for widget-level access.
class DswThemeExtension extends ThemeExtension<DswThemeExtension> {
  const DswThemeExtension({required this.aliases});

  final DswAliases aliases;

  @override
  DswThemeExtension copyWith({DswAliases? aliases}) =>
      DswThemeExtension(aliases: aliases ?? this.aliases);

  @override
  DswThemeExtension lerp(ThemeExtension<DswThemeExtension>? other, double t) {
    if (other is! DswThemeExtension) return this;
    return DswThemeExtension(aliases: t < 0.5 ? aliases : other.aliases);
  }
}
