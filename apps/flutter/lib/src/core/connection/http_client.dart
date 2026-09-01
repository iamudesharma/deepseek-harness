import 'package:http/http.dart' as http;

/// Create an HTTP client for the current platform.
///
/// Web override (`http_client_web.dart`) returns a `BrowserClient` with
/// `withCredentials = true` so CORS credential flows work. Native
/// (`http_client_io.dart`) returns an `IOClient`. This stub is the fallback
/// for analyzer coverage and for platforms where neither `dart.library.io`
/// nor `dart.library.js_interop` matches — it returns the default
/// `http.Client()` which is itself conditionally dispatched by `package:http`.
http.Client createHttpClient() => http.Client();
