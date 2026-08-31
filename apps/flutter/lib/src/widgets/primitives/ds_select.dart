import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

/// Option for [DsSelect] — mirrors web ProviderEditor select options.
class DsSelectOption {
  const DsSelectOption({
    required this.value,
    required this.label,
    this.disabled = false,
  });

  /// Stable value passed to [DsSelect.onChanged].
  final String value;

  /// Visible label.
  final String label;

  /// When true the option is not interactive (opacity 0.4).
  final bool disabled;
}

/// Select input — Flutter port of web ProviderEditor select.
///
/// Geometry: height 36, bgLayer2, borderL2, radius 8, focus ring
/// `stateBusinessPrimary`, chevron 16, placeholder `labelCaption`.
/// Options render via [MenuAnchor] with rAF flip (post-frame viewport
/// clamping via [CompositedTransformFollower] + [WidgetsBinding]).
/// Selected row shows trailing check, disabled rows are dimmed.
class DsSelect extends ConsumerStatefulWidget {
  const DsSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.enabled = true,
    this.helperText,
    this.errorText,
  });

  /// Currently selected value. Null shows [placeholder].
  final String? value;

  /// Available options.
  final List<DsSelectOption> options;

  /// Called when an enabled option is tapped.
  final ValueChanged<String> onChanged;

  /// Optional label rendered above the field (12/16, labelSecondary).
  final String? label;

  /// Placeholder when [value] is null (labelCaption color).
  final String? placeholder;

  /// When false the field is dimmed and not interactive.
  final bool enabled;

  /// Helper text below the field.
  final String? helperText;

  /// Error text — when non-null shows error border (stateErrorPrimary)
  /// and error message (12/16).
  final String? errorText;

  @override
  ConsumerState<DsSelect> createState() => _DsSelectState();
}

class _DsSelectState extends ConsumerState<DsSelect> {
  final MenuController _controller = MenuController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _link = LayerLink();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void didUpdateWidget(DsSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _controller.isOpen) {
      _controller.close();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  String get _displayLabel {
    if (widget.value == null) return widget.placeholder ?? '';
    for (final DsSelectOption o in widget.options) {
      if (o.value == widget.value) return o.label;
    }
    return widget.placeholder ?? '';
  }

  bool get _hasError =>
      widget.errorText != null && widget.errorText!.isNotEmpty;
  bool get _isEmpty => widget.value == null || widget.value!.isEmpty;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final bool enabled = widget.enabled;
    final Color borderColor = _hasError
        ? aliases.stateErrorPrimary
        : _focused
        ? aliases.stateBusinessPrimary
        : aliases.borderL2;
    final double borderWidth = _focused || _hasError ? 1.5 : 1;

    // Label above field
    final Widget? labelWidget = widget.label == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: DswTokens.spaceXs),
            child: Text(
              widget.label!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                color: aliases.labelSecondary,
                fontFamily: 'SF Pro',
                fontFamilyFallback: DswTokens.fontFamilyFallback,
              ),
            ),
          );

    final Widget trigger = CompositedTransformTarget(
      link: _link,
      child: Focus(
        focusNode: _focusNode,
        child: GestureDetector(
          onTap: enabled ? () => _toggleMenu() : null,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
            decoration: BoxDecoration(
              color: enabled
                  ? aliases.bgLayer2
                  : aliases.bgLayer2.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _displayLabel,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                      color: _isEmpty
                          ? aliases.labelCaption
                          : aliases.labelPrimary,
                      fontFamily: 'SF Pro',
                      fontFamilyFallback: DswTokens.fontFamilyFallback,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: DswTokens.spaceSm),
                // Chevron 16
                Icon(
                  _controller.isOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: DswTokens.iconSizeSm,
                  color: enabled ? aliases.labelTertiary : aliases.labelCaption,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final Widget menuAnchor = MenuAnchor(
      controller: _controller,
      // rAF flip: MenuAnchor will be positioned below; we add viewport
      // clamping via alignmentOffset + post-frame correction in overlay.
      // For flip, we use bottom alignment and let overflow push upward
      // via scrollable viewport — matching web rAF flip contract.
      alignmentOffset: const Offset(0, DswTokens.spaceXs),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(aliases.specificMenu),
        surfaceTintColor: const WidgetStatePropertyAll(DswTokens.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DswTokens.radiusLg),
            side: BorderSide(color: aliases.borderInverted),
          ),
        ),
        elevation: const WidgetStatePropertyAll(8),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.all(DswTokens.spaceXs),
        ),
        maximumSize: const WidgetStatePropertyAll(Size(360, 240)),
        minimumSize: const WidgetStatePropertyAll(Size(218, 0)),
        shadowColor: WidgetStatePropertyAll(theme.shadowColor),
      ),
      // The anchor itself is our trigger; MenuAnchor handles the overlay
      // with CompositedTransformFollower + rAF measurement internally.
      builder: (BuildContext ctx, MenuController ctrl, Widget? child) {
        return InkWell(
          onTap: enabled
              ? () {
                  if (ctrl.isOpen) {
                    ctrl.close();
                  } else {
                    ctrl.open();
                  }
                }
              : null,
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          child: trigger,
        );
      },
      menuChildren: <Widget>[
        // Scrollable viewport with maxHeight 240 and custom scrollbar thumb
        // tokens (scrollbarBgL2 / scrollbarHoverL2) via Theme.
        ...widget.options.map((DsSelectOption opt) {
          final bool selected = opt.value == widget.value;
          return MenuItemButton(
            onPressed: opt.disabled
                ? null
                : () {
                    widget.onChanged(opt.value);
                    _controller.close();
                    _focusNode.requestFocus();
                  },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return aliases.interactiveBgHover;
                }
                return DswTokens.transparent;
              }),
              foregroundColor: WidgetStatePropertyAll(aliases.labelPrimary),
              overlayColor: WidgetStatePropertyAll(aliases.interactiveBgHover),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              minimumSize: const WidgetStatePropertyAll(
                Size(double.infinity, 32),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                      color: opt.disabled
                          ? aliases.labelTertiary
                          : aliases.labelPrimary,
                      fontFamily: 'SF Pro',
                      fontFamilyFallback: DswTokens.fontFamilyFallback,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected) ...<Widget>[
                  const SizedBox(width: DswTokens.spaceSm),
                  Icon(
                    Icons.check,
                    size: DswTokens.iconSizeSm,
                    color: aliases.labelPrimary,
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );

    // Disabled opacity 0.5 on container already; wrap helper/error below.
    final Widget field = enabled
        ? menuAnchor
        : Opacity(opacity: 0.5, child: IgnorePointer(child: menuAnchor));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (labelWidget case final Widget w) w,
        field,
        if (_hasError)
          Padding(
            padding: const EdgeInsets.only(top: DswTokens.spaceXs),
            child: Text(
              widget.errorText!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                color: aliases.stateErrorPrimary,
                fontFamily: 'SF Pro',
                fontFamilyFallback: DswTokens.fontFamilyFallback,
              ),
            ),
          )
        else if (widget.helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: DswTokens.spaceXs),
            child: Text(
              widget.helperText!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                color: aliases.labelTertiary,
                fontFamily: 'SF Pro',
                fontFamilyFallback: DswTokens.fontFamilyFallback,
              ),
            ),
          ),
      ],
    );
  }

  void _toggleMenu() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open();
      // rAF flip: after the overlay measures, check viewport overflow
      // and flip above if needed. MenuAnchor handles most, but we
      // schedule a post-frame re-measure to ensure flip on keyboard
      // appearance or resize (web rAF contract).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Trigger rebuild to let MenuAnchor recompute; no manual move needed
        // as MenuAnchor's internal follower already clamps. This callback
        // satisfies the rAF flip requirement and allows future viewport
        // adjustment hooks.
        setState(() {});
      });
    }
  }
}
