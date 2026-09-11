import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Tag palette — port of `TagTone` in `Tag.tsx`.
enum DsTagTone {
  /// Hairline outline on tertiary text: the read-only default.
  outline,

  /// Inverted fill: one tag per group naming the current selection.
  solid,

  /// Platform-gray fill: a neutral fact with no status meaning.
  neutral,

  /// Text only, no fill: a fact stated more quietly than neutral.
  quiet,

  /// Tinted green: a healthy or enabled state.
  success,

  /// Tinted blue: informational classification, not health.
  info,

  /// Tinted amber: attention needed, not yet a failure.
  warning,

  /// Tinted red: a failure.
  danger,
}

/// Read-only capsule badge — Flutter port of `Tag.tsx` + `Tag.module.css`.
///
/// One fixed size everywhere; only the palette varies. The label is owned by
/// the render site (locale-owned copy); unlike [Pill] a tag takes no tap and
/// carries no copy of its own.
class DsTag extends StatelessWidget {
  /// Creates a tag.
  const DsTag({super.key, this.tone = DsTagTone.outline, required this.label});

  /// Which palette to use.
  final DsTagTone tone;

  /// Localized label, owned by the render site.
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final (Color? background, Color? border, Color text) = switch (tone) {
      DsTagTone.outline => (null, aliases.borderL4, aliases.labelTertiary),
      DsTagTone.solid => (
        aliases.labelPrimary,
        null,
        aliases.bgLayer3,
      ),
      DsTagTone.neutral => (
        aliases.bgModulePlatform,
        null,
        aliases.labelSecondary,
      ),
      DsTagTone.quiet => (null, null, aliases.labelTertiary),
      DsTagTone.success => (
        aliases.stateSuccessPrimary.withValues(alpha: 0.10),
        null,
        aliases.stateSuccessPrimary,
      ),
      DsTagTone.info => (
        aliases.stateBusinessPrimary.withValues(alpha: 0.10),
        null,
        aliases.stateBusinessPrimary,
      ),
      DsTagTone.warning => (
        aliases.stateWarnPrimary.withValues(alpha: 0.12),
        null,
        aliases.stateWarnPrimary,
      ),
      DsTagTone.danger => (
        aliases.stateErrorPrimary.withValues(alpha: 0.10),
        null,
        aliases.stateErrorPrimary,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DswTokens.radiusFull),
        color: background,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 17 / 11,
          fontWeight: FontWeight.w500,
          color: text,
        ),
      ),
    );
  }
}
