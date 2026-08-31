import 'package:flutter/widgets.dart';

/// Stub window backend used on web and non-IO targets.
///
/// All operations are no-ops so `flutter build web` never pulls in
/// `dart:io` / `dart:ffi` / `window_manager` transitive dependencies.

/// Initialize the window (no-op on web).
Future<void> initWindowBackend({Size minSize = const Size(960, 640)}) async {}

/// Update the window's minimum size (no-op on web).
Future<void> setWindowMinSizeBackend(Size size) async {}

/// Currently no-op; exists for interface parity with the IO backend.
Future<void> showWindowBackend() async {}
