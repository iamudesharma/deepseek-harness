import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Two-state toggle — Flutter port of `Switch.tsx` + `Switch.module.css`.
///
/// Fully controlled: the visual state keys off [value] the way the CSS keys
/// off `aria-checked`, so the two cannot disagree. [semanticLabel] is
/// required (a render site cannot ship the control without an accessible
/// name); [tooltip] carries the hover text, typically why a locked toggle is
/// disabled. Null [onChanged] renders the disabled state (opacity 0.5).
class DsSwitch extends StatefulWidget {
  /// Creates a toggle.
  const DsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.tooltip,
  });

  /// Current state; the control is fully controlled.
  final bool value;

  /// Called with the state the tap asks for; null disables input.
  final ValueChanged<bool>? onChanged;

  /// Localized accessible name, owned by the render site.
  final String semanticLabel;

  /// Localized hover text, typically why the toggle is locked.
  final String? tooltip;

  @override
  State<DsSwitch> createState() => _DsSwitchState();
}

class _DsSwitchState extends State<DsSwitch> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool enabled = widget.onChanged != null;
    final track = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 36,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: widget.value ? aliases.brandPrimary : aliases.borderL3,
        border: _focused
            ? Border.all(color: aliases.brandPrimary, width: 2)
            : null,
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 120),
        alignment: widget.value
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: aliases.labelPrimaryForeground,
          ),
        ),
      ),
    );
    final control = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: (node, event) {
          if (!enabled) return KeyEventResult.ignored;
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            _toggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: enabled ? _toggle : null,
          behavior: HitTestBehavior.opaque,
          child: track,
        ),
      ),
    );
    final labeled = Semantics(
      label: widget.semanticLabel,
      toggled: widget.value,
      enabled: enabled,
      button: true,
      excludeSemantics: true,
      onTap: enabled ? _toggle : null,
      child: control,
    );
    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) return labeled;
    return Tooltip(message: tooltip, child: labeled);
  }
}
