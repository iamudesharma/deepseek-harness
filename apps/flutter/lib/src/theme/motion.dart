import 'package:flutter/material.dart';

/// Reduced-motion flag — Dart mirror of `prefers-reduced-motion` from the
/// React CSS media queries.
///
/// Reads the ambient [MediaQueryData.disableAnimations]; callers passing a
/// duration should collapse long/repeating animation to a near-instant one
/// (or disable it) when this is true, matching React's media-query-driven
/// duration overrides.
bool prefersReducedMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
