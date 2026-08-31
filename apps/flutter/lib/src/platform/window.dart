import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'window_stub.dart' if (dart.library.io) 'window_io.dart' as backend;

/// Keys for persisted AppFrame layout widths.
const String kWindowSidebarWidthKey = 'dsh_sidebar_width';
const String kWindowDetailsWidthKey = 'dsh_details_width';

/// Initialize the native window and restore persisted layout preference.
///
/// On web this is a no-op (browser `Window` is not owned by the app).
/// On macOS/desktop it:
///
/// * calls `window_manager.ensureInitialized()` + `waitUntilReadyToShow`
///   with [WindowOptions] whose `minimumSize` is [minSize],
/// * centers and shows the `NSWindow`,
/// * leaves layout width restoration to the caller via
///   [restoreLayoutWidths] (Riverpod's [layoutProvider] reads them).
///
/// Call once before `runApp` (after `WidgetsFlutterBinding.ensureInitialized`):
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initWindow();
///   runApp(const ProviderScope(child: DshApp()));
/// }
/// ```
Future<void> initWindow({Size minSize = const Size(960, 640)}) async {
  if (kIsWeb) return;
  await backend.initWindowBackend(minSize: minSize);
}

/// Persist one or both AppFrame panel widths to [SharedPreferences].
///
/// Mirrors `AppFrame` store persistence in
/// `packages/client/ui-layout/src/client/stores.ts` (localStorage sidebar
/// + details widths). Call from the layout controller on drag end.
///
/// Only non-null widths are written; pass `null` to leave the stored
/// value untouched.
///
/// @param sidebar – sidebar width in px (clamped to contract range by caller).
/// @param details – details width in px (0 means closed, also persisted).
Future<void> persistLayoutWidths({double? sidebar, double? details}) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  if (sidebar != null) {
    await prefs.setDouble(kWindowSidebarWidthKey, sidebar);
  }
  if (details != null) {
    await prefs.setDouble(kWindowDetailsWidthKey, details);
  }
}

/// Restore persisted widths.
///
/// Returns a map with `sidebar`/`details` entries when they exist,
/// otherwise `null` entries so callers can fall back to contract defaults
/// (`kSidebarDefault` / `kDetailsDefault`). Works on both web
/// (`SharedPreferences` via localStorage) and macOS.
///
/// Example:
/// ```dart
/// final widths = await restoreLayoutWidths();
/// if (widths['sidebar'] case final double v?) notifier.setSidebar(v);
/// ```
Future<Map<String, double?>> restoreLayoutWidths() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return <String, double?>{
    'sidebar': prefs.getDouble(kWindowSidebarWidthKey),
    'details': prefs.getDouble(kWindowDetailsWidthKey),
  };
}

/// Update the window minimum size at runtime.
///
/// No-op on web; on desktop delegates to `window_manager.setMinimumSize`.
Future<void> setWindowMinSize(Size size) async {
  if (kIsWeb) return;
  await backend.setWindowMinSizeBackend(size);
}

/// Window manager abstraction that mirrors `window_manager` on desktop
/// and is a stub on web.
///
/// Useful when call sites already branch on `kIsWeb` but prefer an
/// explicit type. Most call sites should use [initWindow],
/// [persistLayoutWidths], and [restoreLayoutWidths] directly.
abstract class WindowManagerAdapter {
  /// Initialize the native window.
  Future<void> init({Size minSize});

  /// Set the minimum window size.
  Future<void> setMinSize(Size size);
}

/// Desktop-backed adapter (macOS) using `window_manager`.
class DesktopWindowAdapter implements WindowManagerAdapter {
  /// Creates the desktop adapter.
  const DesktopWindowAdapter();

  @override
  Future<void> init({Size minSize = const Size(960, 640)}) =>
      initWindow(minSize: minSize);

  @override
  Future<void> setMinSize(Size size) => setWindowMinSize(size);
}

/// Web stub adapter — all operations no-op.
class WebWindowAdapter implements WindowManagerAdapter {
  /// Creates the web adapter.
  const WebWindowAdapter();

  @override
  Future<void> init({Size minSize = const Size(960, 640)}) async {}

  @override
  Future<void> setMinSize(Size size) async {}
}

/// Provider-friendly factory that returns the correct adapter for the
/// current platform (single-app conditional via `kIsWeb`).
WindowManagerAdapter getWindowAdapter() {
  if (kIsWeb) return const WebWindowAdapter();
  return const DesktopWindowAdapter();
}
