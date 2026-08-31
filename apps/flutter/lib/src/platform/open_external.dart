import 'package:url_launcher/url_launcher.dart';

/// Sanitizes [url] to only http/https/mailto, matching the React
/// `sanitizeUrl` allowlist in `packages/client/ui-primitives/src/markdown/render.tsx`.
String? sanitizeUrl(String url) {
  try {
    final uri = Uri.parse(url);
    switch (uri.scheme) {
      case 'http':
      case 'https':
      case 'mailto':
        return url;
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
