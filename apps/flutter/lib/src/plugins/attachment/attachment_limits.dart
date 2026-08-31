import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/drag_drop.dart';

// Single source: `ImageLimits`, `DroppedFile`, and `imageSizeText` live in
// `platform/drag_drop.dart`; this file re-exports them and publishes the
// `imageLimitsProvider` face.
export '../../platform/drag_drop.dart'
    show ImageLimits, DroppedFile, imageSizeText;

/// Host-declared image intake limits — the Dart slice of the `imageLimits`
/// projection key.
///
/// `null` until the sessions contract declares limits on the wire: the
/// intake pre-check then defers entirely to the authoritative rejection,
/// matching React's `imageLimits === undefined` branch. Override in tests
/// and live wiring via `ProviderScope.overrides`.
final imageLimitsProvider = StateProvider<ImageLimits?>((ref) => null);
