import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input_trigger_controller.dart';
import '../trigger_source.dart';

/// Keyboard producer for the trigger menu — the missing wiring between
/// `InputTriggerController.arbitrate()` and real composer key events.
///
/// Flutter port of `InputBar.tsx` textarea `onKeyDown` interception: while the
/// controller's menu is open, ArrowUp/ArrowDown/Enter/Escape are routed
/// through [InputTriggerController.arbitrate] first; a `consumed` /
/// `pickHighlighted` outcome returns [KeyEventResult.handled] so the key
/// swallowing never bubbles to the column-wide `ConversationShortcuts`
/// submit/cancel maps. A `pass` outcome returns [ignored] so the field sees
/// the key normally (e.g. Enter with no highlight submits).
class InputKeyboardProducer extends StatefulWidget {
  /// Creates the producer.
  const InputKeyboardProducer({
    super.key,
    required this.controller,
    this.field,
    this.composing = false,
    required this.child,
  });

  /// The controller whose open menu arbitrates the keys; `null` (registry
  /// not activated / no session controller) passes every key through.
  final InputTriggerController? controller;

  /// The live field whose IME composition range is read AT KEY-EVENT TIME.
  /// Build-time composition snapshots go stale between frames, so the guard
  /// must consult the current value when the key arrives.
  final TextEditingController? field;

  /// Static composition fallback for mounts without a field handle (tests).
  final bool composing;

  /// Wrapped field.
  final Widget child;

  @override
  State<InputKeyboardProducer> createState() => _InputKeyboardProducerState();
}

class _InputKeyboardProducerState extends State<InputKeyboardProducer> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(debugLabel: 'input-keyboard-producer');
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) return;
    // Rebuild while focused so the menu highlight follows external changes.
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(InputKeyboardProducer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      setState(() {});
    }
  }

  bool _composingNow() {
    final TextEditingController? field = widget.field;
    if (field != null) {
      final TextRange range = field.value.composing;
      if (range.isValid && !range.isCollapsed) return true;
    }
    return widget.composing;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ArbitrateKey? key = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => ArbitrateKey.up,
      LogicalKeyboardKey.arrowDown => ArbitrateKey.down,
      LogicalKeyboardKey.enter => ArbitrateKey.enter,
      LogicalKeyboardKey.escape => ArbitrateKey.escape,
      _ => null,
    };
    final InputTriggerController? controller = widget.controller;
    if (key == null || controller == null) return KeyEventResult.ignored;
    final ArbitrateOutcome outcome = controller.arbitrate(key, _composingNow());
    switch (outcome) {
      case ArbitrateOutcome.consumed:
      case ArbitrateOutcome.pickHighlighted:
        return KeyEventResult.handled;
      case ArbitrateOutcome.pass:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(focusNode: _focus, onKeyEvent: _onKey, child: widget.child);
  }
}
