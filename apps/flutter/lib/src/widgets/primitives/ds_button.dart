import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

/// Visual variant — maps Button.module.css semantics.
///
/// * [primary] — filled dark/light capsule (`buttonPrimaryFill`).
/// * [ghost] — transparent, hover-tinted.
/// * [elevated] — elevated surface (`buttonElevatedFill`, `shadowLv1`), maps to
///   web `outline` bordered capsule.
/// * [floating] — floating surface (`buttonFloatingFill`, `shadowLv2`), maps to
///   web `toolbar` translucent fill.
enum DsButtonVariant { primary, ghost, elevated, floating }

/// Size — maps `.md` (36px) / `.sm` (28px) in Button.module.css.
enum DsButtonSize { md, sm }

/// Token-styled button atom — Flutter port of `Button.tsx` + `Button.module.css`.
///
/// Slots → Widget?: [icon] is the leading 16px icon, [child]/[label] the
/// text content. Pure build, no `ctx`.
class DsButton extends ConsumerWidget {
  const DsButton({
    super.key,
    this.variant = DsButtonVariant.ghost,
    this.size = DsButtonSize.md,
    this.icon,
    this.label,
    this.child,
    this.onPressed,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  });

  /// Visual family. Defaults to [DsButtonVariant.ghost] matching web default.
  final DsButtonVariant variant;

  /// Density. Defaults to [DsButtonSize.md].
  final DsButtonSize size;

  /// Optional leading 16px icon.
  final Widget? icon;

  /// Text label (alternative to [child] for string content).
  final String? label;

  /// Arbitrary child widget when [label] is insufficient.
  final Widget? child;

  /// Press handler. Null renders disabled state (opacity 0.4).
  final VoidCallback? onPressed;

  /// When true shows a spinner and disables press.
  final bool loading;

  /// When true expands to fill available width.
  final bool fullWidth;

  /// Accessibility label.
  final String? semanticLabel;

  bool get _isDisabled => onPressed == null || loading;
  bool get _isSmall => size == DsButtonSize.sm;

  double get _height => _isSmall ? 28 : 36;
  double get _horizontalPadding => _isSmall ? 10 : 14;
  double get _radius =>
      _isSmall ? DswTokens.radiusButtonSm : DswTokens.radiusButtonMd;
  double get _fontSize =>
      _isSmall ? DswTokens.fontSizeXxs12 : DswTokens.fontSizeS14;
  double get _lineHeight =>
      _isSmall ? DswTokens.lineHeightXxs12 : DswTokens.lineHeightS14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final ColorScheme scheme = theme.colorScheme;

    // Resolve variant colors via tokens — no literal Colors.
    late final Color background;
    late final Color foreground;
    late final Color hoverBackground;
    late final BorderSide side;

    switch (variant) {
      case DsButtonVariant.primary:
        background = aliases.buttonPrimaryFill;
        foreground = aliases.labelPrimaryForeground;
        hoverBackground = aliases.buttonPrimaryHover;
        side = BorderSide.none;
        break;
      case DsButtonVariant.ghost:
        background = DswTokens.transparent;
        foreground = aliases.labelPrimary;
        hoverBackground = aliases.interactiveBgHover;
        side = BorderSide.none;
        break;
      case DsButtonVariant.elevated:
        // Maps web `outline`: bordered capsule on transparent fill (figma 451:18655).
        background = DswTokens.transparent;
        foreground = aliases.labelPrimary;
        hoverBackground = aliases.interactiveBgHover;
        side = BorderSide(color: aliases.borderL2);
        break;
      case DsButtonVariant.floating:
        // Maps web `toolbar`: translucent fill.
        background = aliases.buttonToolBarFill;
        foreground = aliases.labelPrimary;
        hoverBackground = aliases.buttonToolBarHover;
        side = BorderSide.none;
        break;
    }

    final bool disabled = _isDisabled;
    final VoidCallback? handler = disabled ? null : onPressed;

    final Widget? content = _buildContent(theme, foreground);

    final ButtonStyle style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) return background;
        if (states.contains(WidgetState.hovered)) return hoverBackground;
        if (states.contains(WidgetState.pressed)) {
          // Ghost pressed uses active bg, others use hover.
          if (variant == DsButtonVariant.ghost)
            return aliases.interactiveBgActive;
          return hoverBackground;
        }
        return background;
      }),
      foregroundColor: WidgetStatePropertyAll(foreground),
      overlayColor: WidgetStatePropertyAll(aliases.interactiveBgHover),
      side: WidgetStatePropertyAll(side),
      elevation: WidgetStatePropertyAll(
        variant == DsButtonVariant.floating
            ? 2
            : variant == DsButtonVariant.elevated
            ? 1
            : 0,
      ),
      shadowColor: WidgetStatePropertyAll(scheme.shadow),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: side,
        ),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: _horizontalPadding),
      ),
      minimumSize: WidgetStatePropertyAll(Size(0, _height)),
      fixedSize: fullWidth
          ? WidgetStatePropertyAll(Size.fromHeight(_height))
          : null,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: _fontSize,
          height: _lineHeight / _fontSize,
          fontWeight: FontWeight.w500,
          fontFamily: 'SF Pro',
          fontFamilyFallback: DswTokens.fontFamilyFallback,
        ),
      ),
    );

    final Widget effectiveContent = content ?? const SizedBox.shrink();
    final Widget button = switch (variant) {
      DsButtonVariant.primary => ElevatedButton(
        onPressed: handler,
        style: style,
        child: effectiveContent,
      ),
      DsButtonVariant.elevated || DsButtonVariant.floating => ElevatedButton(
        onPressed: handler,
        style: style,
        child: effectiveContent,
      ),
      DsButtonVariant.ghost => TextButton(
        onPressed: handler,
        style: style,
        child: effectiveContent,
      ),
    };

    final Widget sized = fullWidth
        ? SizedBox(width: double.infinity, height: _height, child: button)
        : SizedBox(height: _height, child: button);

    // Disabled web style: opacity 0.4
    final Widget withOpacity = disabled
        ? Opacity(
            opacity: 0.4,
            child: IgnorePointer(
              ignoring: loading ? true : false,
              child: sized,
            ),
          )
        : sized;

    if (semanticLabel != null) {
      return Semantics(button: true, label: semanticLabel, child: withOpacity);
    }
    return withOpacity;
  }

  Widget? _buildContent(ThemeData theme, Color foreground) {
    if (loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          ),
          if (label != null || child != null)
            const SizedBox(width: DswTokens.spaceXs),
          if (label != null)
            Text(label!)
          else if (child != null)
            Flexible(child: child!),
        ],
      );
    }

    final List<Widget> row = <Widget>[];
    if (icon != null) {
      row.add(
        SizedBox(
          width: DswTokens.iconSizeSm,
          height: DswTokens.iconSizeSm,
          child: Center(child: icon!),
        ),
      );
    }
    if (label != null) {
      row.add(Text(label!));
    } else if (child != null) {
      row.add(Flexible(child: child!));
    }
    if (row.isEmpty) return null;
    if (row.length == 1) return row.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < row.length; i++) ...<Widget>[
          row[i],
          if (i != row.length - 1) const SizedBox(width: DswTokens.spaceXs),
        ],
      ],
    );
  }
}
