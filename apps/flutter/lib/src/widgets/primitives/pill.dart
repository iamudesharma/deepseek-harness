import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

/// Small rounded label chip — Flutter port of `Pill.tsx` + `Pill.module.css`.
///
/// Interactive when [onPressed] is supplied (renders a button), otherwise a
/// static span. Active state adds `ghostActiveFill` + border.
class Pill extends ConsumerWidget {
  const Pill({
    super.key,
    this.label,
    this.child,
    this.active = false,
    this.onPressed,
    this.icon,
    this.semanticLabel,
  });

  /// Text label. Either [label] or [child] should be supplied.
  final String? label;

  /// Arbitrary child widget.
  final Widget? child;

  /// Selected/active visual state. Mirrors `.active` in Pill.module.css.
  final bool active;

  /// When non-null the pill is interactive (button semantics).
  final VoidCallback? onPressed;

  /// Optional leading icon (16px).
  final Widget? icon;

  final String? semanticLabel;

  bool get _interactive => onPressed != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final Color bg = active ? aliases.buttonGhostActiveFill : aliases.bgLayer2;
    final Color fg = active ? aliases.labelPrimary : aliases.labelSecondary;
    final BorderSide side = active
        ? BorderSide(color: aliases.buttonGhostActiveBorder)
        : BorderSide.none;
    final Color hoverBg = aliases.interactiveBgHover;

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          SizedBox(width: 16, height: 16, child: Center(child: icon)),
          const SizedBox(width: 4),
        ],
        if (label != null)
          Text(
            label!,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
              color: fg,
              fontFamily: 'SF Pro',
              fontFamilyFallback: DswTokens.fontFamilyFallback,
            ),
          )
        else if (child != null)
          DefaultTextStyle(
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
              color: fg,
            ),
            child: child!,
          ),
      ],
    );

    final Widget decorated = Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.fromBorderSide(side),
      ),
      alignment: Alignment.center,
      child: content,
    );

    if (!_interactive) {
      if (semanticLabel != null)
        return Semantics(label: semanticLabel, child: decorated);
      return decorated;
    }

    return Material(
      color: DswTokens.transparent,
      borderRadius: BorderRadius.circular(DswTokens.radiusLg),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        hoverColor: hoverBg,
        child: decorated,
      ),
    );
  }
}
