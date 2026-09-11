import 'package:flutter/material.dart';

/// Link categories with distinct leading glyphs — port of `LinkIconKind` in
/// `LinkIcon.tsx`. `url` and `folder` are destination categories the consumer
/// states directly; the rest are file categories [classifyLinkPath] derives.
enum LinkIconKind { url, folder, code, image, document, other }

/// Code, web, and data extensions sharing the code glyph (verbatim port of
/// `CODE_EXTENSIONS` in `LinkIcon.tsx`).
const Set<String> kLinkCodeExtensions = {
  'ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs', 'cts', 'mts', 'css', 'scss', 'sass',
  'less', 'html', 'htm', 'vue', 'svelte', 'astro', 'json', 'jsonc', 'json5',
  'yaml', 'yml', 'toml', 'xml', 'ini', 'env', 'sh', 'bash', 'zsh', 'fish',
  'ps1', 'bat', 'cmd', 'py', 'pyi', 'rb', 'rs', 'go', 'java', 'kt', 'kts',
  'c', 'cc', 'cpp', 'cxx', 'h', 'hh', 'hpp', 'cs', 'php', 'swift', 'sql',
  'csv', 'tsv', 'proto', 'graphql', 'gql', 'lua', 'r', 'pl', 'scala', 'clj',
  'cljs', 'ex', 'exs', 'erl', 'hs', 'dart',
};

/// Image extensions sharing the image glyph (verbatim port).
const Set<String> kLinkImageExtensions = {
  'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'avif', 'bmp', 'ico', 'tif',
  'tiff', 'heic', 'heif',
};

/// Document extensions sharing the document glyph (verbatim port).
const Set<String> kLinkDocumentExtensions = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
};

/// Derives a file path's link-icon category from its extension.
///
/// Unknown and missing extensions fall to [LinkIconKind.other]; never
/// returns [LinkIconKind.url] or [LinkIconKind.folder]. Exact port of
/// `classifyLinkPath` (either separator counts).
/// @param path - file path as the producing tool spelled it.
LinkIconKind classifyLinkPath(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf('\\');
  final name = path.substring((slash > backslash ? slash : backslash) + 1);
  final dot = name.lastIndexOf('.');
  if (dot < 0) return LinkIconKind.other;
  final extension = name.substring(dot + 1).toLowerCase();
  if (kLinkCodeExtensions.contains(extension)) return LinkIconKind.code;
  if (kLinkImageExtensions.contains(extension)) return LinkIconKind.image;
  if (kLinkDocumentExtensions.contains(extension)) {
    return LinkIconKind.document;
  }
  return LinkIconKind.other;
}

/// Leading category glyph for clickable artifact links — Flutter port of
/// `LinkIcon.tsx`.
///
/// Glyphs are the closest Material outlines (the React SVGs are bespoke
/// 20px artwork; no pixel parity claimed) and ride the ambient icon color
/// like `fill="currentColor"`.
class DsLinkIcon extends StatelessWidget {
  /// Creates a link icon.
  const DsLinkIcon({super.key, required this.kind, this.size = 14});

  /// Link category.
  final LinkIconKind kind;

  /// Glyph size; defaults to 14, the inline link text size.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      switch (kind) {
        LinkIconKind.url => Icons.language_outlined,
        LinkIconKind.folder => Icons.folder_outlined,
        LinkIconKind.code => Icons.code_outlined,
        LinkIconKind.image => Icons.image_outlined,
        LinkIconKind.document => Icons.description_outlined,
        LinkIconKind.other => Icons.insert_drive_file_outlined,
      },
      size: size,
    );
  }
}
