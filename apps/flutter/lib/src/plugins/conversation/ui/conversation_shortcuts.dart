/// Composer keyboard platform seam — Flutter port of InputBar.tsx key
/// handling for the shortcuts that exist in this slice:
///   Enter        → submit (plain newline is NOT inserted)
///   Shift+Enter  → native newline (inserted by the field itself)
///   Escape       → cancel the in-flight turn / close pending overlays
/// Chip undo/redo (Cmd/Ctrl+Z|Y) belongs to the input-trigger workstream;
/// the intents are declared here so dependents can attach handlers without
/// changing this seam.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intent submitted on plain Enter.
class SubmitIntent extends Intent {
  const SubmitIntent();
}

/// Intent fired on Escape.
class CancelIntent extends Intent {
  const CancelIntent();
}

/// Undo intent (Cmd/Ctrl+Z). Handler attached by input-trigger WS.
class UndoIntent extends Intent {
  const UndoIntent();
}

/// Redo intent (Cmd/Ctrl+Shift+Z | Ctrl+Y).
class RedoIntent extends Intent {
  const RedoIntent();
}

/// macOS accelerator style: metaKey on Apple platforms, ctrl elsewhere.
bool get useMetaAccelerator =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Undo activators: Cmd+Z on Apple hosts, Ctrl+Z elsewhere — the platform
/// split of the React InputBar's uniform `metaKey || ctrlKey` check. Every
/// variant carries an accelerator: bare Shift+Z (typing a capital Z) never
/// matches.
List<SingleActivator> get undoActivators => useMetaAccelerator
    ? <SingleActivator>[
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
      ]
    : <SingleActivator>[
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
      ];

/// Redo activators: Cmd+Shift+Z (Apple) / Ctrl+Shift+Z or Ctrl+Y (elsewhere),
/// same accelerator rule as [undoActivators].
List<SingleActivator> get redoActivators => useMetaAccelerator
    ? <SingleActivator>[
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
      ]
    : <SingleActivator>[
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true),
      ];

/// Platform seam wrapping [child] with the composer shortcut map.
///
/// Single-character activations use [SingleActivator] with the platform
/// accelerator so Web (Ctrl) and macOS (Cmd) behave identically to the
/// React `e.metaKey || e.ctrlKey` check.
class ConversationShortcuts extends StatelessWidget {
  const ConversationShortcuts({
    super.key,
    required this.child,
    this.onSubmit,
    this.onCancel,
    this.onUndo,
    this.onRedo,
  });

  final Widget child;
  final VoidCallback? onSubmit;
  final VoidCallback? onCancel;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // includeRepeats: false is the e.repeat guard (InputBar.tsx): a
        // held-down Enter must not machine-gun sends.
        const SingleActivator(
          LogicalKeyboardKey.enter,
          includeRepeats: false,
        ): () =>
            onSubmit?.call(),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            onCancel?.call(),
        // Undo/redo accept the platform accelerator on every host: Cmd on
        // Apple, Ctrl elsewhere (React InputBar accepts meta||ctrl). The
        // bindings stay installed even with null handlers so the native text
        // stack never runs them — the machine owns the undo/redo log.
        for (final SingleActivator activator in undoActivators)
          activator: () => onUndo?.call(),
        for (final SingleActivator activator in redoActivators)
          activator: () => onRedo?.call(),
      },
      child: Focus(autofocus: false, canRequestFocus: false, child: child),
    );
  }
}
