import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Web HTTP client — `BrowserClient` with credentials.
///
/// Only imported when `dart.library.js_interop` is available (Flutter Web)
/// via the conditional import in `connection_client.dart`, so native builds
/// never see `dart:js_interop` / `package:web` and stay free of the
/// `JSObject`/`JSAny` compile errors that break macOS.
http.Client createHttpClient() => BrowserClient()..withCredentials = true;
