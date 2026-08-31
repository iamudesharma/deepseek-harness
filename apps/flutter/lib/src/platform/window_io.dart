import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window backend using `window_manager` (`NSWindow` on macOS).
///
/// Only imported when `dart.library.io` is available via conditional
/// import in `window.dart`, so `flutter build web` never sees
/// `dart:ffi` or `window_manager`'s native bindings.

/// Initialize the native window.
///
/// Sets a sensible default [WindowOptions] with [minSize] as the
/// platform `minimumSize`, centers the window, and ensures it is
/// shown + focused. Called once from `main()` via [initWindow].
Future<void> initWindowBackend({Size minSize = const Size(960, 640)}) async {
  await windowManager.ensureInitialized();
  final WindowOptions options = WindowOptions(
    size: const Size(1280, 800),
    minimumSize: minSize,
    center: true,
    backgroundColor:
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark
        ? const Color(0xFF0F1115)
        : const Color(0xFFFFFFFF),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    windowButtonVisibility: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  // Enforce minSize again after show for macOS live-resize safety.
  await windowManager.setMinimumSize(minSize);
}

/// Update the window minimum size at runtime.
Future<void> setWindowMinSizeBackend(Size size) async {
  await windowManager.setMinimumSize(size);
}

/// Ensure the window is visible.
Future<void> showWindowBackend() async {
  await windowManager.show();
}
