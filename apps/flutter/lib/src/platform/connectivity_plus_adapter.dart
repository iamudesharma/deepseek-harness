import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'connectivity.dart';

/// Real monitor backed by `connectivity_plus`.
///
/// On Web this is never instantiated (the provider returns [NoopConnectivityMonitor]
/// when `kIsWeb` is true), so the `connectivity_plus` import does not affect
/// the Web bundle's reachability handling.
class ConnectivityPlusMonitor implements ConnectivityMonitor {
  ConnectivityPlusMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<AppConnectivityState> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return AppConnectivityState.none;
    }
    if (results.contains(ConnectivityResult.wifi)) {
      return AppConnectivityState.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return AppConnectivityState.mobile;
    }
    if (results.contains(ConnectivityResult.ethernet)) {
      return AppConnectivityState.ethernet;
    }
    if (results.contains(ConnectivityResult.vpn)) {
      return AppConnectivityState.vpn;
    }
    return AppConnectivityState.other;
  }

  @override
  Stream<AppConnectivityState> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map((results) {
        if (results.contains(ConnectivityResult.none) || results.isEmpty) {
          return AppConnectivityState.none;
        }
        if (results.contains(ConnectivityResult.wifi)) {
          return AppConnectivityState.wifi;
        }
        if (results.contains(ConnectivityResult.mobile)) {
          return AppConnectivityState.mobile;
        }
        if (results.contains(ConnectivityResult.ethernet)) {
          return AppConnectivityState.ethernet;
        }
        if (results.contains(ConnectivityResult.vpn)) {
          return AppConnectivityState.vpn;
        }
        return AppConnectivityState.other;
      });
}
