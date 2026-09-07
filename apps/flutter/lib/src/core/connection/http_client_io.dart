import 'package:http/http.dart' as http;

/// Native HTTP client — delegates to `package:http`'s `IOClient`.
///
/// Imported only when `dart.library.io` is available (macOS, Linux, Windows,
/// Android, iOS) via the conditional import in `connection_client.dart`, so
/// the web-only `dart:js_interop` / `package:web` graph is never analyzed for
/// native builds.
http.Client createHttpClient() => http.Client();
