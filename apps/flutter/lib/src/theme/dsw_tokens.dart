import 'package:flutter/material.dart';

/// Static palette and semantic tokens ported from
/// `packages/client/ui-theme/src/styles/design-platform.css` and `base.css`.
///
/// Every color maps `rgb(r,g,b)` → `Color(0xFFRRGGBB)` and
/// `rgba(r,g,b,a)` → `Color(0xAARRGGBB)` with academic precision.
/// No literal [Color] values may appear outside this file.
abstract final class DswTokens {
  // ---------------------------------------------------------------------------
  // Static palettes — ` --dsw-static-* ` — invariant across light/dark.
  // The single exception is `--dsw-static-neutral-bluish-60` which is
  // 245,246,247 (0xFFF5F6F7) in light and 249,250,251 (0xFFF9FAFB) in dark.
  // ---------------------------------------------------------------------------

  // Amber — 5 stops
  static const Color amber100 = Color(0xFFFEF5E7); // rgb(254,245,231)
  static const Color amber400 = Color(0xFFF7AD31); // rgb(247,173,49)
  static const Color amber500 = Color(0xFFF59E0B); // rgb(245,158,11)
  static const Color amber600 = Color(0xFFDD8629); // rgb(221,134,41)
  static const Color amber900 = Color(0xFF27241F); // rgb(39,36,31)

  // Blue — 11 stops (+ 50p alias)
  static const Color blue50 = Color(0xFFEFF6FF); // rgb(239,246,255)
  static const Color blue50p = Color(0xFFEAF3FF); // rgb(234,243,255)
  static const Color blue75 = Color(0xFFE5F0FF); // rgb(229,240,255)
  static const Color blue100 = Color(0xFFDBEAFE); // rgb(219,234,254)
  static const Color blue300 = Color(0xFF93C5FD); // rgb(147,197,253)
  static const Color blue400 = Color(0xFF60A5FA); // rgb(96,165,250)
  static const Color blue450 = Color(0xFF4D93F8); // rgb(77,147,248)
  static const Color blue500 = Color(0xFF3B82F6); // rgb(59,130,246)
  static const Color blue600 = Color(0xFF2563EB); // rgb(37,99,235)
  static const Color blue800 = Color(0xFF1E40AF); // rgb(30,64,175)
  static const Color blue900 = Color(0xFF0E3074); // rgb(14,48,116)
  static const Color blue950 = Color(0xFF172554); // rgb(23,37,84)

  // DeepSeek — 10 stops (+ delete)
  static const Color deepseek50 = Color(0xFFEDF3FE); // rgb(237,243,254)
  static const Color deepseek100 = Color(0xFFE4EDFD); // rgb(228,237,253)
  static const Color deepseek200 = Color(0xFFD3E2FF); // rgb(211,226,255)
  static const Color deepseek300 = Color(0xFFB7C8FE); // rgb(183,200,254)
  static const Color deepseek400 = Color(0xFF679EFE); // rgb(103,158,254)
  static const Color deepseek450 = Color(0xFF5686FE); // rgb(86,134,254)
  static const Color deepseek500 = Color(0xFF4176E6); // rgb(65,118,230)
  static const Color deepseek600 = Color(0xFF4868B2); // rgb(72,104,178)
  static const Color deepseek700Delete = Color(0xFF2F4C8F); // rgb(47,76,143)
  static const Color deepseek800 = Color(0xFF34415B); // rgb(52,65,91)
  static const Color deepseek900 = Color(0xFF283142); // rgb(40,49,66)

  // Green — 4 stops
  static const Color green100 = Color(0xFFE6FAED); // rgb(230,250,237)
  static const Color green400 = Color(0xFF4ED17E); // rgb(78,209,126)
  static const Color green500 = Color(0xFF22C55E); // rgb(34,197,94)
  static const Color green900 = Color(0xFF233C2C); // rgb(35,60,44)

  // Neutral (warm) — 13 stops + 00 / 1000
  static const Color neutral00 = Color(0xFFFFFFFF); // rgb(255,255,255)
  static const Color neutral1000 = Color(0xFF000000); // rgb(0,0,0)
  static const Color neutral50 = Color(0xFFFAFAFA); // rgb(250,250,250)
  static const Color neutral100 = Color(0xFFF5F5F5); // rgb(245,245,245)
  static const Color neutral150 = Color(0xFFEDEDED); // rgb(237,237,237)
  static const Color neutral200 = Color(0xFFE5E5E5); // rgb(229,229,229)
  static const Color neutral250 = Color(0xFFDCDCDC); // rgb(220,220,220)
  static const Color neutral300 = Color(0xFFD4D4D4); // rgb(212,212,212)
  static const Color neutral400 = Color(0xFFA2A4A6); // rgb(162,164,166)
  static const Color neutral500 = Color(0xFF7F8287); // rgb(127,130,135)
  static const Color neutral550 = Color(0xFF65676B); // rgb(101,103,107)
  static const Color neutral600 = Color(0xFF545557); // rgb(84,85,87)
  static const Color neutral700 = Color(0xFF3C3C3D); // rgb(60,60,61)
  static const Color neutral800 = Color(0xFF292929); // rgb(41,41,41)
  static const Color neutral850 = Color(0xFF212123); // rgb(33,33,35)
  static const Color neutral900 = Color(0xFF0F0F0F); // rgb(15,15,15)

  // Neutral bluish — 18 stops + 00 / 1000
  static const Color neutralBluish00 = Color(0xFFFFFFFF); // rgb(255,255,255)
  static const Color neutralBluish1000 = Color(0xFF0F1115); // rgb(15,17,21)
  static const Color neutralBluish50 = Color(0xFFF9FAFB); // rgb(249,250,251)
  // ignore: constant_identifier_names — intentional split for light/dark 60
  static const Color neutralBluish60Light = Color(
    0xFFF5F6F7,
  ); // rgb(245,246,247) light
  static const Color neutralBluish60Dark = Color(
    0xFFF9FAFB,
  ); // rgb(249,250,251) dark
  /// Default light value for `--dsw-static-neutral-bluish-60`.
  static const Color neutralBluish60 = neutralBluish60Light;
  static const Color neutralBluish75 = Color(0xFFF1F3F5); // rgb(241,243,245)
  static const Color neutralBluish100 = Color(0xFFEBEEF2); // rgb(235,238,242)
  static const Color neutralBluish150 = Color(0xFFE9ECF2); // rgb(233,236,242)
  static const Color neutralBluish200 = Color(0xFFE1E5EE); // rgb(225,229,238)
  static const Color neutralBluish300 = Color(0xFFCFD3D6); // rgb(207,211,214)
  static const Color neutralBluish400 = Color(0xFFADB2B8); // rgb(173,178,184)
  static const Color neutralBluish500 = Color(0xFF979DA6); // rgb(151,157,166)
  static const Color neutralBluish600 = Color(0xFF81858C); // rgb(129,133,140)
  static const Color neutralBluish700 = Color(0xFF61666B); // rgb(97,102,107)
  static const Color neutralBluish750 = Color(0xFF43454A); // rgb(67,69,74)
  static const Color neutralBluish800 = Color(0xFF353638); // rgb(53,54,56)
  static const Color neutralBluish850 = Color(0xFF2C2C2E); // rgb(44,44,46)
  static const Color neutralBluish875 = Color(0xFF232324); // rgb(35,35,36)
  static const Color neutralBluish900 = Color(0xFF1B1B1C); // rgb(27,27,28)
  static const Color neutralBluish950 = Color(0xFF151517); // rgb(21,21,23)

  // Red — 6 stops
  static const Color red50 = Color(0xFFFEF2F2); // rgb(254,242,242)
  static const Color red100 = Color(0xFFFEE2E2); // rgb(254,226,226)
  static const Color red400 = Color(0xFFF25A5A); // rgb(242,90,90)
  static const Color red500 = Color(0xFFEF4444); // rgb(239,68,68)
  static const Color red600 = Color(0xFFEC1313); // rgb(236,19,19)
  static const Color red900 = Color(0xFF570C0C); // rgb(87,12,12)

  /// Transparent — used for [Colors.transparent] replacement without literals outside this file.
  static const Color transparent = Color(0x00000000);

  // ---------------------------------------------------------------------------
  // Typography — from `base.css` and `gradient-shadow-text.css`
  // ---------------------------------------------------------------------------

  /// `--dsw-font-family` — system UI stack.
  static const String fontFamily =
      "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', "
      "'Hiragino Sans GB', 'Microsoft YaHei', 'Helvetica Neue', Helvetica, Arial, sans-serif";

  /// Flutter fontFamily fallback list derived from above (sans platform fonts).
  static const List<String> fontFamilyFallback = <String>[
    'SF Pro',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Helvetica Neue',
    'Helvetica',
    'Arial',
    'sans-serif',
  ];

  /// `--ds-font-family-code` — monospaced stack, SF Mono preferred.
  static const String fontFamilyCode =
      "'SF Mono', 'JetBrains Mono', 'Fira Code', Consolas, "
      "'Liberation Mono', Menlo, Courier, 'PingFang SC', 'Microsoft YaHei'";

  static const List<String> fontFamilyCodeFallback = <String>[
    'SF Mono',
    'JetBrains Mono',
    'Fira Code',
    'Consolas',
    'Liberation Mono',
    'Menlo',
    'Courier',
  ];

  // Font size / line-height tokens (px) — representative subset from
  // gradient-shadow-text.css; remaining markdown roles are available via
  // DswTypography.
  static const double fontSizeXxxs11 = 11;
  static const double lineHeightXxxs11 = 14;
  static const double fontSizeXxs12 = 12;
  static const double lineHeightXxs12 = 18;
  static const double fontSizeXs13 = 13;
  static const double lineHeightXs13 = 20;
  static const double fontSizeS14 = 14;
  static const double lineHeightS14 = 22;
  static const double fontSizeBase16 = 16;
  static const double lineHeightBase16 = 24;
  static const double fontSizeM18 =
      16; // --dsw-font-m-18 is 16px/28px, weight 500
  static const double lineHeightM18 = 28;
  static const double fontSizeL20 = 20;
  static const double lineHeightL20 = 28;
  static const double fontSizeXl24 = 24;
  static const double lineHeightXl24 = 32;

  // Markdown typography.
  static const double markdownH1Size = 24;
  static const double markdownH1LineHeight = 34;
  static const double markdownH2Size = 22;
  static const double markdownH2LineHeight = 32;
  static const double markdownH3Size = 20;
  static const double markdownH3LineHeight = 30;
  static const double markdownH4Size = 16;
  static const double markdownH4LineHeight = 28;
  static const double markdownBaseSize = 16;
  static const double markdownBaseLineHeight = 28;
  static const double markdownSmallSize = 14;
  static const double markdownSmallLineHeight = 24;
  static const double markdownCodeSize = 14;
  static const double markdownCodeLineHeight = 22;
  static const double markdownCodeBlockSize = 13;
  static const double markdownCodeBlockLineHeight = 22;
  static const double markdownCodeBlockSmallSize = 12;
  static const double markdownCodeBlockSmallLineHeight = 18;

  // ---------------------------------------------------------------------------
  // Motion — from `base.css`
  // ---------------------------------------------------------------------------

  /// `--ds-ease-in-out: cubic-bezier(0.4, 0, 0.2, 1)`
  static const Cubic easeInOut = Cubic(0.4, 0, 0.2, 1);

  /// `--ds-transition-duration: 0.2s`
  static const Duration transitionDuration = Duration(milliseconds: 200);

  /// `--ds-transition-duration-fast: 0.1s`
  static const Duration transitionDurationFast = Duration(milliseconds: 100);

  /// `--ds-transition-duration-slow: 0.3s`
  static const Duration transitionDurationSlow = Duration(milliseconds: 300);

  // ---------------------------------------------------------------------------
  // Spacing & radius — derived from component CSS conventions.
  // No explicit `--dsw-space-*` scale exists in the source sheets;
  // these values reflect the 4px base grid used throughout.
  // ---------------------------------------------------------------------------

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double space2xl = 32;

  static const double radiusXs = 4;
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radius2xl = 24;
  static const double radiusFull = 999;
  static const double radiusButtonMd = 18;
  static const double radiusButtonSm = 14;

  static const double iconSizeSm = 16;
  static const double inputHeightRegular = 36;
  static const double inputHeightSmall = 32;
  static const double inputGap = 6;

  // Shadows — from gradient-shadow-text.css
  static const List<BoxShadow> shadowLv1 = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> shadowLv1Blur = <BoxShadow>[
    BoxShadow(color: Color(0x05000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> shadowLv2 = <BoxShadow>[
    BoxShadow(color: Color(0x05000000), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> shadowLv3 = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 1, offset: Offset(0, 0)),
    BoxShadow(color: Color(0x05000000), blurRadius: 4, offset: Offset(0, 0)),
    BoxShadow(color: Color(0x14000000), blurRadius: 32, offset: Offset(0, 12)),
  ];

  // ---------------------------------------------------------------------------
  // Semantic alias objects — light / dark
  // ---------------------------------------------------------------------------

  static const DswAliases lightAliases = DswAliases.light();
  static const DswAliases darkAliases = DswAliases.dark();

  // Convenience getters that default to light aliases (use
  // Theme.of(context).brightness to select at runtime; see app_theme.dart).
  static Color get aliasBgBase => lightAliases.bgBase;
  static Color get aliasLabelPrimary => lightAliases.labelPrimary;
}

/// Immutable semantic alias container. Light and dark variants are const.
class DswAliases {
  const DswAliases({
    required this.bgBase,
    required this.bgLayer1,
    required this.bgLayer2,
    required this.bgLayer3,
    required this.bgMask1,
    required this.bgMask2,
    required this.bgMask3,
    required this.bgMaskPhoto,
    required this.bgMaskDrop,
    required this.bgModulePlatform,
    required this.bgMultiSelect,
    required this.bgOverlay,
    required this.bgSkeleton,
    required this.borderInverted,
    required this.borderInverted2,
    required this.borderL1,
    required this.borderL2,
    required this.borderL2DarkmodeThin,
    required this.borderL3,
    required this.borderL4,
    required this.brandPrimary,
    required this.brandPrimaryInvert,
    required this.brandPrimaryNewColor,
    required this.brandText,
    required this.buttonContrastFill,
    required this.buttonElevatedFill,
    required this.buttonFloatingFill,
    required this.buttonFloatingHover,
    required this.buttonGhostActiveBorder,
    required this.buttonGhostActiveFill,
    required this.buttonGhostActiveHover,
    required this.buttonInfoFill,
    required this.buttonInfoHover,
    required this.buttonPrimaryDimmed,
    required this.buttonPrimaryFill,
    required this.buttonPrimaryHover,
    required this.buttonToolBarFill,
    required this.buttonToolBarFillInvisible,
    required this.buttonToolBarHover,
    required this.interactiveBgActive,
    required this.interactiveBgHover,
    required this.interactiveBgHoverAccent,
    required this.interactiveBgHoverDanger,
    required this.interactiveBgHoverSolid,
    required this.labelCaption,
    required this.labelDimmed,
    required this.labelPrimaryBluish,
    required this.labelPrimaryDimmed,
    required this.labelPrimaryForeground,
    required this.labelPrimaryInverted,
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.markdownCitation,
    required this.markdownCodeBlock,
    required this.markdownCodeBlockBanner,
    required this.markdownCodeSegmentSelected,
    required this.markdownCodeSegmentUnselected,
    required this.markdownInlineCode,
    required this.markdownPlaceholder,
    required this.markdownTag,
    required this.scrollbarBgL1,
    required this.scrollbarBgL2,
    required this.scrollbarHoverL1,
    required this.scrollbarHoverL2,
    required this.stateBusinessPrimary,
    required this.stateBusinessTertiary,
    required this.stateErrorPrimary,
    required this.stateErrorSecondary,
    required this.stateSuccessPrimary,
    required this.stateSuccessSecondary,
    required this.stateSuccessTertiary,
    required this.stateWarnLabel,
    required this.stateWarnPrimary,
    required this.stateWarnSecondary,
    required this.stateWarnTertiary,
    required this.toastBg,
    required this.tooltipBg,
    required this.specificBubble,
    required this.specificBubbleHighlight,
    required this.specificInputMajor,
    required this.specificLoginInput,
    required this.specificMenu,
    required this.specificSelector,
    required this.specificSidebarFill,
    required this.specificSidebarNavItemActive,
    required this.specificSidebarNavItemActiveAccent,
    required this.specificSidebarNavItemHover,
    required this.specificTip,
  });

  // Light — maps body { --dsw-alias-* } to static colors / rgba.
  const DswAliases.light()
    : bgBase = DswTokens.neutralBluish00,
      bgLayer1 = DswTokens.neutralBluish00,
      bgLayer2 = DswTokens.neutralBluish00,
      bgLayer3 = DswTokens.neutralBluish00,
      bgMask1 = const Color(0x3D000000), // rgba(0,0,0,0.24)
      bgMask2 = const Color(0x1F000000), // rgba(0,0,0,0.12)
      bgMask3 = const Color(0x7A000000), // rgba(0,0,0,0.48)
      bgMaskPhoto = const Color(0xE0000000), // rgba(0,0,0,0.88)
      bgMaskDrop = const Color(0xB3FFFFFF), // rgba(255,255,255,0.7)
      bgModulePlatform = DswTokens.neutralBluish60Light,
      bgMultiSelect = DswTokens.neutralBluish60Light,
      bgOverlay = DswTokens.neutralBluish150,
      bgSkeleton = const Color(0x0A000000), // rgba(0,0,0,0.04)
      borderInverted = const Color(0x00000000), // rgba(0,0,0,0)
      borderInverted2 = const Color(0x00000000),
      borderL1 = const Color(0x0A000000), // rgba(0,0,0,0.04)
      borderL2 = const Color(0x1A000000), // rgba(0,0,0,0.1)
      borderL2DarkmodeThin = const Color(0x1A000000),
      borderL3 = const Color(0x1F000000), // rgba(0,0,0,0.12)
      borderL4 = const Color(0x29000000), // rgba(0,0,0,0.16)
      brandPrimary = DswTokens.neutralBluish1000,
      brandPrimaryInvert = DswTokens.neutralBluish1000,
      brandPrimaryNewColor = DswTokens.deepseek500, // rgb(65,118,230)
      brandText = DswTokens.neutralBluish1000,
      buttonContrastFill = DswTokens.neutralBluish700,
      buttonElevatedFill = DswTokens.neutralBluish00,
      buttonFloatingFill = DswTokens.neutralBluish00,
      buttonFloatingHover = DswTokens.neutralBluish75,
      buttonGhostActiveBorder = DswTokens.neutralBluish500,
      buttonGhostActiveFill = DswTokens.neutralBluish100,
      buttonGhostActiveHover = DswTokens.neutralBluish150,
      buttonInfoFill = DswTokens.deepseek500,
      buttonInfoHover = DswTokens.deepseek400,
      buttonPrimaryDimmed = DswTokens.neutralBluish100,
      buttonPrimaryFill = DswTokens.neutralBluish1000,
      buttonPrimaryHover = DswTokens.neutralBluish750,
      buttonToolBarFill = const Color(0x80545557), // rgba(84,85,87,0.5)
      buttonToolBarFillInvisible = const Color(
        0x5C1F1F1F,
      ), // rgba(31,31,31,0.36)
      buttonToolBarHover = const Color(0x99545557), // rgba(84,85,87,0.6)
      interactiveBgActive = const Color(0x1A263148), // rgba(38,49,72,0.1)
      interactiveBgHover = const Color(0x0F263148), // rgba(38,49,72,0.06)
      interactiveBgHoverAccent = const Color(0x24263148), // rgba(38,49,72,0.14)
      interactiveBgHoverDanger = const Color(
        0x0DEC1313,
      ), // rgba(236,19,19,0.05)
      interactiveBgHoverSolid = DswTokens.neutralBluish75,
      labelCaption = DswTokens.neutralBluish400,
      labelDimmed = DswTokens.neutralBluish200,
      labelPrimaryBluish = DswTokens.blue900,
      labelPrimaryDimmed = DswTokens.neutralBluish950,
      labelPrimaryForeground = DswTokens.neutralBluish00,
      labelPrimaryInverted = DswTokens.neutralBluish00,
      labelPrimary = DswTokens.neutralBluish1000,
      labelSecondary = DswTokens.neutralBluish700,
      labelTertiary = DswTokens.neutralBluish600,
      markdownCitation = DswTokens.neutralBluish100,
      markdownCodeBlock = DswTokens.neutralBluish50,
      markdownCodeBlockBanner = DswTokens.neutralBluish50,
      markdownCodeSegmentSelected = DswTokens.neutralBluish00,
      markdownCodeSegmentUnselected = DswTokens.neutralBluish75,
      markdownInlineCode = DswTokens.neutralBluish100,
      markdownPlaceholder = DswTokens.neutralBluish60Light,
      markdownTag = DswTokens.neutralBluish75,
      scrollbarBgL1 = DswTokens.neutral200,
      scrollbarBgL2 = DswTokens.neutral200,
      scrollbarHoverL1 = DswTokens.neutral300,
      scrollbarHoverL2 = DswTokens.neutral300,
      stateBusinessPrimary = DswTokens.deepseek500,
      stateBusinessTertiary = DswTokens.deepseek100,
      stateErrorPrimary = DswTokens.red600,
      stateErrorSecondary = DswTokens.red400,
      stateSuccessPrimary = DswTokens.green500,
      stateSuccessSecondary = DswTokens.green400,
      stateSuccessTertiary = DswTokens.green100,
      stateWarnLabel = DswTokens.amber600,
      stateWarnPrimary = DswTokens.amber500,
      stateWarnSecondary = DswTokens.amber400,
      stateWarnTertiary = DswTokens.amber100,
      toastBg = DswTokens.neutralBluish800,
      tooltipBg = DswTokens.neutralBluish850,
      specificBubble = DswTokens.deepseek50,
      specificBubbleHighlight = DswTokens.deepseek200,
      specificInputMajor = DswTokens.neutralBluish00,
      specificLoginInput = DswTokens.neutralBluish50,
      specificMenu = DswTokens.neutralBluish00,
      specificSelector = DswTokens.neutralBluish60Light,
      specificSidebarFill = DswTokens.neutralBluish50,
      specificSidebarNavItemActive = DswTokens.neutralBluish100,
      specificSidebarNavItemActiveAccent = DswTokens.deepseek100,
      specificSidebarNavItemHover = DswTokens.neutralBluish75,
      specificTip = DswTokens.neutralBluish60Light;

  // Dark — maps body[data-ds-dark-theme] { --dsw-alias-* }.
  const DswAliases.dark()
    : bgBase = DswTokens.neutralBluish950,
      bgLayer1 = DswTokens.neutralBluish875,
      bgLayer2 = DswTokens.neutralBluish850,
      bgLayer3 = DswTokens.neutralBluish800,
      bgMask1 = const Color(0x80000000), // rgba(0,0,0,0.5)
      bgMask2 = const Color(0x33000000), // rgba(0,0,0,0.2)
      bgMask3 = const Color(0x7A000000), // rgba(0,0,0,0.48)
      bgMaskPhoto = const Color(0xE0000000),
      bgMaskDrop = const Color(0xB3272730), // rgba(39,39,48,0.7)
      bgModulePlatform = DswTokens.neutralBluish800,
      bgMultiSelect = DswTokens.neutral850,
      bgOverlay = DswTokens.neutralBluish700,
      bgSkeleton = const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
      borderInverted = const Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
      borderInverted2 = const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
      borderL1 = const Color(0x0FFFFFFF),
      borderL2 = const Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
      borderL2DarkmodeThin = const Color(0x0FFFFFFF),
      borderL3 = const Color(0x29FFFFFF), // rgba(255,255,255,0.16)
      borderL4 = const Color(0x33FFFFFF), // rgba(255,255,255,0.2)
      brandPrimary = DswTokens.neutralBluish50,
      brandPrimaryInvert = DswTokens.neutralBluish50,
      brandPrimaryNewColor = DswTokens.deepseek450,
      brandText = DswTokens.neutralBluish50,
      buttonContrastFill = DswTokens.neutralBluish50,
      buttonElevatedFill = DswTokens.neutralBluish750,
      buttonFloatingFill = DswTokens.neutralBluish850,
      buttonFloatingHover = DswTokens.neutralBluish800,
      buttonGhostActiveBorder = DswTokens.neutralBluish600,
      buttonGhostActiveFill = DswTokens.neutralBluish750,
      buttonGhostActiveHover = DswTokens.neutralBluish700,
      buttonInfoFill = DswTokens.deepseek400,
      buttonInfoHover = DswTokens.deepseek500,
      buttonPrimaryDimmed = DswTokens.neutralBluish750,
      buttonPrimaryFill = DswTokens.neutralBluish50,
      buttonPrimaryHover = DswTokens.neutralBluish100,
      buttonToolBarFill = const Color(0x80545557),
      buttonToolBarFillInvisible = const Color(0x5C1F1F1F),
      buttonToolBarHover = const Color(0x99545557),
      interactiveBgActive = const Color(0x24FFFFFF), // rgba(255,255,255,0.14)
      interactiveBgHover = const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
      interactiveBgHoverAccent = const Color(
        0x3DFFFFFF,
      ), // rgba(255,255,255,0.24)
      interactiveBgHoverDanger = const Color(
        0x26F25A5A,
      ), // rgba(242,90,90,0.15)
      interactiveBgHoverSolid = DswTokens.neutralBluish800,
      labelCaption = DswTokens.neutralBluish600,
      labelDimmed = DswTokens.neutralBluish750,
      labelPrimaryBluish = DswTokens.neutralBluish50,
      labelPrimaryDimmed = DswTokens.neutralBluish100,
      labelPrimaryForeground = DswTokens.neutralBluish1000,
      labelPrimaryInverted = DswTokens.neutralBluish800,
      labelPrimary = DswTokens.neutralBluish50,
      labelSecondary = DswTokens.neutralBluish300,
      labelTertiary = DswTokens.neutralBluish400,
      markdownCitation = DswTokens.neutralBluish800,
      markdownCodeBlock = DswTokens.neutralBluish900,
      markdownCodeBlockBanner = DswTokens.neutralBluish850,
      markdownCodeSegmentSelected = DswTokens.neutralBluish800,
      markdownCodeSegmentUnselected = DswTokens.neutralBluish900,
      markdownInlineCode = DswTokens.neutralBluish850,
      markdownPlaceholder = DswTokens.neutralBluish850,
      markdownTag = DswTokens.neutralBluish850,
      scrollbarBgL1 = DswTokens.neutral700,
      scrollbarBgL2 = DswTokens.neutral600,
      scrollbarHoverL1 = DswTokens.neutral600,
      scrollbarHoverL2 = DswTokens.neutral550,
      stateBusinessPrimary = DswTokens.deepseek400,
      stateBusinessTertiary = DswTokens.deepseek800,
      stateErrorPrimary = DswTokens.red400,
      stateErrorSecondary = DswTokens.red400,
      stateSuccessPrimary = DswTokens.green500,
      stateSuccessSecondary = DswTokens.green400,
      stateSuccessTertiary = DswTokens.green900,
      stateWarnLabel = DswTokens.amber600,
      stateWarnPrimary = DswTokens.amber500,
      stateWarnSecondary = DswTokens.amber400,
      stateWarnTertiary = DswTokens.amber900,
      toastBg = DswTokens.neutralBluish750,
      tooltipBg = DswTokens.neutralBluish750,
      specificBubble = DswTokens.neutralBluish850,
      specificBubbleHighlight = DswTokens.neutralBluish750,
      specificInputMajor = DswTokens.neutralBluish850,
      specificLoginInput = DswTokens.neutralBluish900,
      specificMenu = DswTokens.neutralBluish800,
      specificSelector = DswTokens.neutralBluish800,
      specificSidebarFill = DswTokens.neutralBluish900,
      specificSidebarNavItemActive = DswTokens.neutralBluish750,
      specificSidebarNavItemActiveAccent = DswTokens.neutralBluish800,
      specificSidebarNavItemHover = DswTokens.neutralBluish850,
      specificTip = DswTokens.neutralBluish800;

  // Background / surface
  final Color bgBase;
  final Color bgLayer1;
  final Color bgLayer2;
  final Color bgLayer3;
  final Color bgMask1;
  final Color bgMask2;
  final Color bgMask3;
  final Color bgMaskPhoto;
  final Color bgMaskDrop;
  final Color bgModulePlatform;
  final Color bgMultiSelect;
  final Color bgOverlay;
  final Color bgSkeleton;

  // Borders
  final Color borderInverted;
  final Color borderInverted2;
  final Color borderL1;
  final Color borderL2;
  final Color borderL2DarkmodeThin;
  final Color borderL3;
  final Color borderL4;

  // Brand
  final Color brandPrimary;
  final Color brandPrimaryInvert;
  final Color brandPrimaryNewColor;
  final Color brandText;

  // Buttons
  final Color buttonContrastFill;
  final Color buttonElevatedFill;
  final Color buttonFloatingFill;
  final Color buttonFloatingHover;
  final Color buttonGhostActiveBorder;
  final Color buttonGhostActiveFill;
  final Color buttonGhostActiveHover;
  final Color buttonInfoFill;
  final Color buttonInfoHover;
  final Color buttonPrimaryDimmed;
  final Color buttonPrimaryFill;
  final Color buttonPrimaryHover;
  final Color buttonToolBarFill;
  final Color buttonToolBarFillInvisible;
  final Color buttonToolBarHover;

  // Interactive
  final Color interactiveBgActive;
  final Color interactiveBgHover;
  final Color interactiveBgHoverAccent;
  final Color interactiveBgHoverDanger;
  final Color interactiveBgHoverSolid;

  // Labels
  final Color labelCaption;
  final Color labelDimmed;
  final Color labelPrimaryBluish;
  final Color labelPrimaryDimmed;
  final Color labelPrimaryForeground;
  final Color labelPrimaryInverted;
  final Color labelPrimary;
  final Color labelSecondary;
  final Color labelTertiary;

  // Markdown
  final Color markdownCitation;
  final Color markdownCodeBlock;
  final Color markdownCodeBlockBanner;
  final Color markdownCodeSegmentSelected;
  final Color markdownCodeSegmentUnselected;
  final Color markdownInlineCode;
  final Color markdownPlaceholder;
  final Color markdownTag;

  // Scrollbar
  final Color scrollbarBgL1;
  final Color scrollbarBgL2;
  final Color scrollbarHoverL1;
  final Color scrollbarHoverL2;

  // State
  final Color stateBusinessPrimary;
  final Color stateBusinessTertiary;
  final Color stateErrorPrimary;
  final Color stateErrorSecondary;
  final Color stateSuccessPrimary;
  final Color stateSuccessSecondary;
  final Color stateSuccessTertiary;
  final Color stateWarnLabel;
  final Color stateWarnPrimary;
  final Color stateWarnSecondary;
  final Color stateWarnTertiary;

  // Overlays
  final Color toastBg;
  final Color tooltipBg;

  // Specific (sidebar / bubble / inputs)
  final Color specificBubble;
  final Color specificBubbleHighlight;
  final Color specificInputMajor;
  final Color specificLoginInput;
  final Color specificMenu;
  final Color specificSelector;
  final Color specificSidebarFill;
  final Color specificSidebarNavItemActive;
  final Color specificSidebarNavItemActiveAccent;
  final Color specificSidebarNavItemHover;
  final Color specificTip;
}
