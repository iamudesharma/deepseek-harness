import 'package:url_launcher/url_launcher.dart';

/// Sanitizes [url] to only http/https/mailto, matching the React
/// `sanitizeUrl` allowlist in `packages/client/ui-primitives/src/markdown/render.tsx`.
///
/// Trims surrounding whitespace and rejects relative or unparsable URLs so
/// fragment anchors and bare paths never reach the launcher (React's `new
/// URL(url)` throws for them).
String? sanitizeUrl(String url) {
  final String trimmed = url.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final uri = Uri.parse(trimmed);
    // `Uri.parse` lower-cases the scheme; compare case-insensitively for
    // parity with React's `new URL(url).protocol` check.
    switch (uri.scheme.toLowerCase()) {
      case 'http':
      case 'https':
      case 'mailto':
        // Keep original trimmed casing for mailto case preservation while
        // still validating the scheme.
        return trimmed;
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

/// Returns true if [url] should be opened with `target="_blank"` semantics
/// (http/https only, matching `WebBlock` safeHref subset).
bool isExternalHttpUrl(String url) {
  final safe = sanitizeUrl(url);
  if (safe == null) return false;
  try {
    final scheme = Uri.parse(safe).scheme;
    return scheme == 'http' || scheme == 'https';
  } catch (_) {
    return false;
  }
}

/// Opens [url] externally after sanitizing. Returns false if the URL is
/// blocked or launching fails.
Future<bool> openExternal(String url) async {
  final safe = sanitizeUrl(url);
  if (safe == null) return false;
  final uri = Uri.parse(safe);
  // launchUrl with externalApplication mirrors browser target="_blank"
  // and macOS openExternal.
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
