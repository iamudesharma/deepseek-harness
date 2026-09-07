import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../core/connection/connection_target.dart';

/// Whether the current platform should apply mobile background suspend/resume.
///
/// Mirrors the existing mobile seam in `layout.dart` (`isMobileLayout`) but
/// without a BuildContext: `!kIsWeb && (android || iOS)`. Desktop (macOS,
/// Windows, Linux) and Web never suspend, preserving existing
/// `LocalTarget` behavior.
bool get isMobileLifecyclePlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Whether mobile lifecycle handling should be applied for [target].
///
/// Only a remote, bearer-authenticated target on a mobile platform suspends
/// sockets on background and resumes with a fresh generation. Local loopback
/// (macOS/Web) and Web never apply mobile-only lifecycle logic.
bool shouldApplyMobileLifecycle(ConnectionTarget target) {
  if (!isMobileLifecyclePlatform) return false;
  return target.isRemote;
}
