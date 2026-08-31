import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

/// True when the app runs as a native touch device (Android/iOS).
///
/// Platform-only check — used for narrow-mobile UI tweaks inside the
/// conversation (e.g. composer `narrowMobile`). Does NOT decide the shell;
/// that decision is width-aware via [isMobileShell].
///
/// The test harness runs as Android by default, so tests that need a desktop
/// shell must explicitly set `debugDefaultTargetPlatformOverride` to macOS
/// or iOS and pump a desktop-width [MediaQuery]. Reading
/// [defaultTargetPlatform] respects the override.
bool get isMobileLayout {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Width-aware shell decision: native mobile renders the bare navigation
/// shell ONLY when width < 768 (sidebarCollapse). Wider native windows
/// (tablet, desktop-sized emulator) keep the three-column [AppFrame].
///
/// Mirrors the production responsive rule: `!kIsWeb && isMobileLayout && width<768`.
bool isMobileShell(BuildContext context) {
  if (kIsWeb) return false;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return false;
  }
  return MediaQuery.sizeOf(context).width < 768;
}
