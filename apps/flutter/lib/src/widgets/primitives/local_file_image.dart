/// Assistant-prose image destinations — the Dart slice of React
/// `AssistantMarkdown.localPathMediaUrl` + `MarkdownPathImages`.
///
/// Prose may reference Host-local absolute media paths. Those map to the
/// authenticated `/api/file` route ([localPathMediaUrl]); everything else
/// keeps default network rendering. Unmappable destinations render inert
/// alt text (React renders them byte-identical without vocabulary).
library;

import 'dart:convert';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';
import '../../core/files/media_file_client.dart';
import '../../theme/app_theme.dart';

/// Builds the image widget for one prose image destination.
/// @param ref - reader for the connection origin.
/// @param uri - parsed markdown image destination.
/// @param alt - alt text for inert/error rendering.
/// @returns the file, network, or inert-alt widget (never null).
Widget buildProseImage(WidgetRef ref, Uri uri, String? alt) {
  final href = uri.toString();
  final origin = ref.read(connectionClientProvider).baseUrl;
  final fileUrl = localPathMediaUrl(origin, href);
  if (fileUrl != null) {
    return LocalFileImage(fileUrl: fileUrl, alt: alt);
  }
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return Image.network(
      href,
      errorBuilder: (_, _, _) => _inertAlt(alt, href),
    );
  }
  return _inertAlt(alt, href);
}

/// Inert alt-text rendering for destinations with no vocabulary.
Widget _inertAlt(String? alt, String href) {
  final text = (alt?.isNotEmpty ?? false) ? alt! : href;
  return Text(text, textDirection: TextDirection.ltr);
}

/// One Host-local prose image, loaded through the authenticated file route.
///
/// Shows a spinner while loading and falls back to inert alt text when the
/// file is unavailable, too large, or denied (mirroring the Host fail-closed
/// statuses with client-side alt rendering).
class LocalFileImage extends ConsumerWidget {
  /// Creates the image for one authenticated file URL.
  const LocalFileImage({super.key, required this.fileUrl, this.alt});

  /// Authenticated `/api/file` URL from [localPathMediaUrl].
  final String fileUrl;

  /// Alt text for the failure fallback.
  final String? alt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(mediaFileClientProvider);
    return FutureBuilder<String>(
      future: media.fetchDataUrl(fileUrl),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const SizedBox(
            height: 24,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final dataUrl = snapshot.data;
        if (dataUrl == null || dataUrl.isEmpty) {
          return _inertAlt(alt, fileUrl);
        }
        try {
          final bytes = base64Decode(dataUrl.split(',').last);
          return Image.memory(
            bytes,
            errorBuilder: (_, _, _) => _inertAlt(alt, fileUrl),
          );
        } catch (_) {
          return _inertAlt(alt, fileUrl);
        }
      },
    );
  }
}
