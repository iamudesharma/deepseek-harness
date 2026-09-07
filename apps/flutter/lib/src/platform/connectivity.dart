import 'dart:async';

/// Connectivity abstraction for lifecycle/network handling.
///
/// Uses `connectivity_plus` on mobile/desktop where available; on Web the
/// host is same-origin and network loss surfaces as HTTP/WebSocket errors,
/// so the provider degrades to a no-op (the controller's backoff loop
/// already handles it). A fake implementation is used in tests to simulate
/// `wifi → none → wifi` etc. deterministically.
///
/// There is one authoritative connection state; this monitor never drives its
/// own reconnect loop — it only nudges the existing
/// `FlutterConnectionController` to retry immediately via
/// `handleNetworkOnline()` when the OS reports that connectivity returned.
enum AppConnectivityState { none, wifi, mobile, ethernet, vpn, other }

/// Monitor interface — platform seam for connectivity.
abstract class ConnectivityMonitor {
  /// Current connectivity.
  Future<AppConnectivityState> checkConnectivity();

  /// Stream of connectivity changes.
  Stream<AppConnectivityState> get onConnectivityChanged;
}

/// No-op monitor (Web/tests without override) — always reports `wifi`
/// (i.e., assume online; the controller's loop handles actual reachability).
class NoopConnectivityMonitor implements ConnectivityMonitor {
  const NoopConnectivityMonitor();

  @override
  Future<AppConnectivityState> checkConnectivity() async =>
      AppConnectivityState.wifi;

  @override
  Stream<AppConnectivityState> get onConnectivityChanged =>
      const Stream.empty();
}
