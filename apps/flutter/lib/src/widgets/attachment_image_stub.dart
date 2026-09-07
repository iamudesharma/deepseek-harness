import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Web stub — no `dart:io` import, so `Image.file` is unavailable.
///
/// Returns the fallback icon exactly matching the native seam's placeholder
/// so visual parity is identical when a file path is accidentally rendered on
/// web (should not happen; web delivers `blob:`/`data:` URLs).
Widget buildNativeThumbnail(String path, DswAliases aliases) {
  return Container(
    width: 64,
    height: 64,
    color: aliases.bgOverlay,
    child: Icon(Icons.image_outlined, size: 22, color: aliases.labelCaption),
  );
}

/// Web stub for the lightbox full-size preview.
///
/// File paths are not renderable on web; return the placeholder the rail's
/// `_placeholder` also uses (so the io and web lightboxes share the same
/// fallback contract).
Widget buildNativeLightbox(String path, DswAliases aliases, String name) {
  return Container(
    width: 320,
    height: 200,
    decoration: BoxDecoration(
      color: aliases.bgLayer2,
      borderRadius: BorderRadius.circular(DswTokens.radiusLg),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.image, size: 48, color: aliases.labelCaption),
        const SizedBox(height: 8),
        Text(name, style: TextStyle(color: aliases.labelSecondary)),
      ],
    ),
  );
}
