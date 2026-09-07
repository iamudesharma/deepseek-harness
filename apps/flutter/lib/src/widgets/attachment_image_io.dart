import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Native implementation — `dart:io` is available, so `Image.file` renders
/// macOS `desktop_drop` `XFile.path` and `file_picker` `PlatformFile.path`
/// thumbnails without breaking the web build via the conditional import seam.
Widget buildNativeThumbnail(String path, DswAliases aliases) {
  final File file = File(path);
  return Image.file(
    file,
    width: 64,
    height: 64,
    fit: BoxFit.cover,
    errorBuilder:
        (BuildContext context, Object error, StackTrace? stackTrace) =>
            Container(
              width: 64,
              height: 64,
              color: aliases.bgOverlay,
              child: Icon(
                Icons.image_outlined,
                size: 22,
                color: aliases.labelCaption,
              ),
            ),
  );
}

/// Native lightbox image via `Image.file` when the attachment resolves to a
/// local path (the `previewUrl ?? path` that `ComposerAttachment.create`
/// stores as `path` on macOS).
Widget buildNativeLightbox(String path, DswAliases aliases, String name) {
  final File file = File(path);
  return Image.file(
    file,
    fit: BoxFit.contain,
    errorBuilder:
        (BuildContext context, Object error, StackTrace? stackTrace) =>
            Container(
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
            ),
  );
}
