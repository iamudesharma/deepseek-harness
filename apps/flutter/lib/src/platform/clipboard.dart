import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Clipboard helper that works on both web and macOS via Flutter's
/// [Clipboard] abstraction.
///
/// Flutter already routes `Clipboard.setData` to the browser's
/// `navigator.clipboard.writeText` on web and to `NSPasteboard` on
/// macOS, so no `dart:html` / `package:web` import is needed — that
/// keeps the desktop artifact clean. Platform checks are retained for
/// messaging and for secure-context guidance on web.
class ClipboardHelper {
  /// Copy [text] to the system clipboard.
  ///
  /// @param text – non-empty string to copy; empty input returns `false`
  /// without touching the clipboard.
  /// @returns `true` when [Clipboard.setData] resolved, `false` on
  /// empty input or platform error.
  static Future<bool> copy(String text) async {
    if (text.isEmpty) return false;
    try {
      // Clipboard.setData is the Flutter-level adapter:
      // - web: delegates to navigator.clipboard.writeText (requires HTTPS)
      // - macOS/desktop: NSPasteboard via the engine.
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Copy [text] and show a [SnackBar] on [BuildContext].
  ///
  /// Shows a success SnackBar on `true`, an error SnackBar on `false`.
  /// Uses platform-tuned messaging (e.g. web secure-context hint).
  ///
  /// @param context – scaffold context for the SnackBar.
  /// @param text – string to copy.
  /// @param successMessage – optional override for the success label.
  /// @returns `true` when copied, `false` otherwise.
  static Future<bool> copyWithFeedback(
    BuildContext context,
    String text, {
    String successMessage = 'Copied to clipboard',
  }) async {
    final bool ok = await copy(text);
    if (!context.mounted) return ok;
    final String message = ok ? successMessage : _failureMessage();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return ok;
  }

  static String _failureMessage() {
    if (kIsWeb) {
      return 'Copy failed — browser may require HTTPS or user gesture';
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return 'Copy failed — pasteboard unavailable';
    }
    return 'Copy failed';
  }

  /// Whether the current platform likely supports clipboard writes.
  ///
  /// Always `true` via Flutter's adapter, but web insecure contexts
  /// (`http:`) may still deny; this getter is informative only.
  static bool get isSupported {
    // Flutter supports clipboard on all targets we build (web + macOS).
    // Branch retained so call sites can gate UI (e.g. hide copy button
    // in hypothetical server rendering).
    if (kIsWeb) return true;
    return true;
  }
}

/// Convenience top-level for call sites that prefer a function over a
/// class namespace.
///
/// Mirrors [ClipboardHelper.copy].
Future<bool> copyToClipboard(String text) => ClipboardHelper.copy(text);

/// Convenience top-level with SnackBar feedback.
///
/// Mirrors [ClipboardHelper.copyWithFeedback].
Future<bool> copyToClipboardWithFeedback(
  BuildContext context,
  String text, {
  String successMessage = 'Copied to clipboard',
}) => ClipboardHelper.copyWithFeedback(
  context,
  text,
  successMessage: successMessage,
);
