import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Focus-aware popover scaffold shared by the welcome pickers (workspace,
/// preset, model) — replaces the bare Stack+barrier pattern so every menu
/// behaves like React's document-level Menu listeners:
///
/// * **Escape** dismisses (captured via [Focus] while the overlay owns focus).
/// * **Tab / Shift+Tab** stays trapped inside the popover scope (wraps between
///   the capture node and the menu's own focusable items).
/// * **Barrier tap** still dismisses (the barrier is this scaffold's own
///   bottom layer, not a caller-owned sibling).
/// * **Focus return** restores the node that held focus when the popover
///   opened, so closing never strands keyboard focus.
///
/// Decoration only: the caller supplies the anchored/centered menu itself as
/// [child]; no second overlay system is introduced.
class DshMenuScaffold extends StatefulWidget {
  /// Creates the popover scaffold.
  const DshMenuScaffold({
    super.key,
    required this.onClose,
    required this.child,
    this.barrierColor = Colors.transparent,
  });

  /// Called on Escape, barrier tap, or any other close request.
  final VoidCallback onClose;

  /// The popover content, positioned spatially by the caller.
  final Widget child;

  /// Barrier scrim color.
  final Color barrierColor;

  @override
  State<DshMenuScaffold> createState() => _DshMenuScaffoldState();
}

class _DshMenuScaffoldState extends State<DshMenuScaffold> {
  final FocusNode _capture = FocusNode(debugLabel: 'dsh-menu-scaffold-capture');
  final FocusScopeNode _scope = FocusScopeNode(
    debugLabel: 'dsh-menu-scaffold-scope',
  );
  FocusNode? _previousFocus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _previousFocus = FocusManager.instance.primaryFocus;
      _capture.requestFocus();
    });
  }

  @override
  void dispose() {
    _capture.dispose();
    _scope.dispose();
    super.dispose();
  }

  void _close() {
    final FocusNode? previous = _previousFocus;
    if (previous != null && previous.canRequestFocus) {
      previous.requestFocus();
    }
    widget.onClose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }

    // Trap Tab inside the popover: cycle through the menu's focusable
    // descendants (wrapping) instead of letting it escape to the page.
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _scope.previousFocus();
      } else {
        _scope.nextFocus();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Full-viewport overlay: expand to whatever bounds the caller gives
    // (bounded Scaffold body, or the test tree), so the Stack always has
    // finite constraints even when mounted as a loose child.
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: ColoredBox(color: widget.barrierColor),
            ),
          ),
          Positioned.fill(
            child: FocusScope(
              node: _scope,
              child: Focus(
                focusNode: _capture,
                onKeyEvent: _onKey,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
