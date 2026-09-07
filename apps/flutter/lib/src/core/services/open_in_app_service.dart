import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../connection/connection_client.dart';
import '../connection/http_client.dart'
    if (dart.library.io) '../connection/http_client_io.dart'
    if (dart.library.js_interop) '../connection/http_client_web.dart'
    as http_client_factory;

/// Host open-in-app catalog entry — mirrors `OpenInAppApp` in
/// `packages/host/open-in-app/src/catalog.ts` (only `id` is needed on the
/// wire; `label` comes from the Flutter locale dictionary).
class OpenInAppApp {
  const OpenInAppApp({required this.id, required this.labelKey});
  final String id;
  final String labelKey;
}

/// Known catalog ids → locale keys — mirrors `APP_LABEL_KEY` in
/// `packages/client/ui-open-in-app/src/client/OpenInAppAction.tsx`.
const Map<String, String> _kAppLabelKeys = <String, String>{
  'finder': 'app.finder',
  'explorer': 'app.explorer',
  'filemanager': 'app.filemanager',
  'cursor': 'app.cursor',
  'vscode': 'app.vscode',
  'vscodeinsiders': 'app.vscodeinsiders',
  'windsurf': 'app.windsurf',
  'zed': 'app.zed',
  'sublimetext': 'app.sublimetext',
  'xcode': 'app.xcode',
  'androidstudio': 'app.androidstudio',
  'intellij': 'app.intellij',
  'pycharm': 'app.pycharm',
  'webstorm': 'app.webstorm',
  'phpstorm': 'app.phpstorm',
  'goland': 'app.goland',
  'rider': 'app.rider',
  'rustrover': 'app.rustrover',
  'fork': 'app.fork',
  'sourcetree': 'app.sourcetree',
  'github': 'app.github',
  'tower': 'app.tower',
  'gitkraken': 'app.gitkraken',
  'smartgit': 'app.smartgit',
  'sublimemerge': 'app.sublimemerge',
  'ghostty': 'app.ghostty',
  'warp': 'app.warp',
  'iterm': 'app.iterm',
  'kitty': 'app.kitty',
  'terminal': 'app.terminal',
  'windowsterminal': 'app.windowsterminal',
  'gitbash': 'app.gitbash',
  'gnometerminal': 'app.gnometerminal',
  'konsole': 'app.konsole',
};

/// Service for the host's `open-in-app` HTTP routes.
///
/// Mirrors `OpenInAppController` in `packages/client/ui-open-in-app/src/client/controller.ts`
/// but via raw `http` (not Typert) because the host mounts these on `webServer`
/// directly (`/open-in-app/apps`, `/open-in-app/icon/:id`, `/open-in-app/open`).
class OpenInAppService {
  OpenInAppService(this._client);

  final ConnectionClient _client;

  static const String _kChoiceKey = 'dsh.open-in-app.choice';

  /// `GET /open-in-app/apps` → `{apps: string[]}` in host menu order.
  Future<List<String>> listApps() async {
    final uri = _uri('/open-in-app/apps');
    final headers = await _headers();
    final resp = await _http().get(uri, headers: headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('GET /open-in-app/apps failed: ${resp.statusCode} ${resp.body}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['apps'] is List) {
      return (decoded['apps'] as List).whereType<String>().toList();
    }
    return const [];
  }

  /// `GET /open-in-app/icon/:id` URL for `Image.network` (with credentials).
  String iconUrl(String appId) {
    final base = _baseUri();
    // Use Uri.replace to keep scheme/host/port from DSH_HOST_URL.
    final uri = base.replace(path: '/open-in-app/icon/$appId');
    return uri.toString();
  }

  /// `POST /open-in-app/open {app, path}` — launches `app` on `path`.
  Future<void> open({required String appId, required String path}) async {
    final uri = _uri('/open-in-app/open');
    final headers = await _headers();
    headers['content-type'] = 'application/json';
    final resp = await _http().post(
      uri,
      headers: headers,
      body: jsonEncode(<String, String>{'app': appId, 'path': path}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('POST /open-in-app/open failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Last chosen app id persisted across restarts — mirrors
  /// `createSnapshotStore('', {persist: {name: 'dsh.open-in-app.choice'}})`.
  Future<String?> getChoice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kChoiceKey);
  }

  Future<void> setChoice(String appId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kChoiceKey, appId);
  }

  /// Filter raw ids to only those with a locale entry, like React's
  /// `apps.filter(entry.labelKey !== undefined)`.
  List<OpenInAppApp> filterNameable(List<String> ids) {
    final out = <OpenInAppApp>[];
    for (final id in ids) {
      final key = _kAppLabelKeys[id];
      if (key != null) out.add(OpenInAppApp(id: id, labelKey: key));
    }
    return out;
  }

  Uri _baseUri() {
    final baseUrl = _client.baseUrl;
    // Strip ?token=... like ConnectionClient._uri does — token is for
    // GET /?token= → Set-Cookie, not for /open-in-app/* query.
    final uri = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);
    final q = Map<String, String>.from(uri.queryParameters)..remove('token');
    return uri.replace(queryParameters: q.isEmpty ? null : q);
  }

  Uri _uri(String path) => _baseUri().replace(path: path);

  http.Client _http() {
    // Use the same factory as ConnectionClient so web gets BrowserClient
    // withCredentials:true and IO gets the pinned fingerprint handling.
    try {
      return http_client_factory.createHttpClient();
    } catch (_) {
      return http.Client();
    }
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'accept': 'application/json'};
    if (kIsWeb) {
      // Web: BrowserClient sends Cookie automatically if the browser has it.
      // Ensure the cookie is minted for the authority if a token is present.
      try {
        final baseUrl = _client.baseUrl;
        final uri = Uri.tryParse(baseUrl);
        final token = uri?.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          // ignore: avoid_dynamic_calls
          final dynamic c = _client;
          try {
            // ignore: avoid_dynamic_calls
            final Future<String?> Function(String)? getter =
                c.getBrowserCookie as Future<String?> Function(String)?;
            if (getter != null) await getter(baseUrl);
          } catch (_) {}
        }
      } catch (_) {}
      return headers;
    }
    // IO: replicate ConnectionClient._headersWithAuth for the open-in-app
    // fence (Host/Origin + Cookie/Bearer). We can't reach into privates, so
    // we do a best-effort: try to get the Cookie via the same exchange as
    // browser_cookie_io.dart, and try to get a Bearer via tokenStore.
    try {
      final baseUrl = _client.baseUrl;
      // ignore: avoid_dynamic_calls
      final dynamic c = _client;
      try {
        // ignore: avoid_dynamic_calls
        final Future<String?> Function(String)? getter =
            c.getBrowserCookie as Future<String?> Function(String)?;
        if (getter != null) {
          final cookie = await getter(baseUrl);
          if (cookie != null) headers['cookie'] = cookie;
        }
      } catch (_) {}
      try {
        // ignore: avoid_dynamic_calls
        final Future<String?> Function()? bearerFn =
            c._bearerToken as Future<String?> Function()?;
        if (bearerFn != null) {
          final bearer = await bearerFn();
          if (bearer != null) headers['authorization'] = 'Bearer $bearer';
        }
      } catch (_) {}
    } catch (_) {}
    return headers;
  }
}
