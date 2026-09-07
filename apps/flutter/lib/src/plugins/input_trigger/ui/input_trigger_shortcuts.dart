/// Composer-side shortcut layer for the input-trigger workstream: attaches the
/// real chip undo/redo handlers to the `UndoIntent` / `RedoIntent` classes the
/// conversation seam declared (`ui/conversation_shortcuts.dart`) — via this
/// plugin's own Shortcuts/Actions wrapper, so the composer seam stays
/// untouched and the intents gain handlers exactly where the trigger pipeline
/// is mounted.
///
/// Undo/redo mutate the controller's chip transaction draft; when a composer
/// mounts this layer through [ComposerTriggerBinding] overrides, the restored
/// draft is pushed back into the composer field in the same step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../conversation/ui/conversation_shortcuts.dart'
    show RedoIntent, UndoIntent, redoActivators, undoActivators;
import '../input_trigger_service.dart';

/// Wraps [child] with Cmd/Ctrl+Z (undo) and Cmd/Ctrl+Shift+Z | Ctrl+Y (redo)
/// bindings that drive the active session's [InputTriggerController].
///
/// By default the handlers resolve the session controller through the
/// registry. A mounted composer supplies [undo]/[redo] overrides instead so
/// restored drafts are pushed back into its own field (the binding bridge),
/// and [invocable] to port the React InputBar guard that blocks undo/redo
/// while the machine is busy or the input locked (the keystroke stays
/// consumed either way — only the mutation is gated).
class InputTriggerShortcuts extends ConsumerWidget {
  /// Creates the layer.
  const InputTriggerShortcuts({
    super.key,
    required this.registry,
    required this.sessionId,
    required this.child,
    this.invocable,
    this.undo,
    this.redo,
  });

  /// The trigger registry resolving per-session controllers.
  final TriggerSourceRegistry registry;

  /// Session whose controller receives undo/redo.
  final String sessionId;

  /// Gate consulted before either handler mutates; null = always allowed.
  final bool Function()? invocable;

  /// Undo override replacing the default registry resolution.
  final VoidCallback? undo;

  /// Redo override replacing the default registry resolution.
  final VoidCallback? redo;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final SingleActivator activator in undoActivators)
          activator: const UndoIntent(),
        for (final SingleActivator activator in redoActivators)
          activator: const RedoIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          UndoIntent: CallbackAction<UndoIntent>(
            onInvoke: (_) {
              if (invocable?.call() == false) return null;
              final override = undo;
              if (override != null) {
                override();
              } else {
                registry.controllerFor(sessionId).undo();
              }
              return null;
            },
          ),
          RedoIntent: CallbackAction<RedoIntent>(
            onInvoke: (_) {
              if (invocable?.call() == false) return null;
              final override = redo;
              if (override != null) {
                override();
              } else {
                registry.controllerFor(sessionId).redo();
              }
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
