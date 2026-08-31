import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

/// Placement relative to the anchor — mirrors web `TooltipSide`.
enum DsTooltipSide { right, bottom, top }

/// Tooltip wrapper — Flutter port of `Tooltip.tsx` + `Tooltip.module.css`.
///
/// Thin wrapper around Flutter's [Tooltip] that applies DSW token styling:
/// dark plate (`tooltipBg`), white text, radius 8, padding 3/7, type 13/20,
/// max 50vw, fade 150ms. Pure build, no `ctx`.
class DsTooltip extends ConsumerWidget {
  const DsTooltip({
    super.key,
    required this.message,
    required this.child,
    this.side = DsTooltipSide.right,
    this.waitDuration = Duration.zero,
    this.showDuration,
    this.enabled = true,
    this.maxWidth,
    this.textAlign,
    this.excludeFromSemantics = false,
  });

  /// Bubble text. When a function is needed (web `() => string` resolver),
  /// resolve before passing.
  final String message;

  /// Anchor widget.
  final Widget child;

  /// Placement preference. Maps to [Tooltip] `preferBelow` / verticalOffset.
  final DsTooltipSide side;

  /// Hover delay. Defaults to zero matching web `delayMs = 0`.
  final Duration waitDuration;

  /// How long to keep the tooltip visible after show.
  final Duration? showDuration;

  /// When false suppresses the tooltip (web `disabled`).
  final bool enabled;

  /// Width cap for long labels. Mirrors web `maxWidth` prop; default 50vw
  /// is handled via constraints.
  final double? maxWidth;

  final TextAlign? textAlign;

  /// Whether to exclude tooltip semantics.
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled || message.isEmpty) return child;

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // Tooltip.module.css: padding 3/7, radius 8, bg tooltipBg, text neutral-bluish-00,
    // font 13/20, max 50vw, animation 150ms ease-in-out.
    // maxWidth mirrors web `maxWidth` prop; default 50vw is enforced via
    // LayoutBuilder so long labels wrap before the viewport edge.
    final bool isTop = side == DsTooltipSide.top;
    final bool isBottom = side == DsTooltipSide.bottom;

    final double effectiveMaxWidth =
        maxWidth ?? MediaQuery.sizeOf(context).width * 0.5;

    return Tooltip(
      message: message,
      preferBelow: side == DsTooltipSide.bottom || side == DsTooltipSide.right
          ? false
          : true,
      verticalOffset: isBottom
          ? 8
          : isTop
          ? -8
          : 0,
      waitDuration: waitDuration,
      showDuration: showDuration,
      excludeFromSemantics: excludeFromSemantics,
      constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
      decoration: BoxDecoration(
        color: aliases.tooltipBg,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      textStyle: TextStyle(
        color: DswTokens.neutralBluish00,
        fontSize: 13,
        height: 20 / 13,
        fontFamily: 'SF Pro',
        fontFamilyFallback: DswTokens.fontFamilyFallback,
      ),
      textAlign: textAlign,
      child: child,
    );
  }
}

/// Convenience extension for wrapping any widget with a tooltip.
extension DsTooltipExtension on Widget {
  Widget withTooltip(
    String message, {
    DsTooltipSide side = DsTooltipSide.right,
    bool enabled = true,
    Duration waitDuration = Duration.zero,
    double? maxWidth,
    Duration? showDuration,
  }) => DsTooltip(
    message: message,
    side: side,
    enabled: enabled,
    waitDuration: waitDuration,
    maxWidth: maxWidth,
    showDuration: showDuration,
    child: this,
  );
}
