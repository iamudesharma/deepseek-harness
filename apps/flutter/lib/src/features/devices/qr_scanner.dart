import 'package:flutter/widgets.dart';

import 'qr_payload.dart';
import 'qr_scanner_stub.dart'
    if (dart.library.io) 'qr_scanner_mobile.dart'
    as impl;

/// QR scanner seam — mobile-only, Web/macOS fall back to manual entry.
///
/// Returns a [QrPayload] on successful scan, or `null` if cancelled.
/// The Web build never imports `mobile_scanner`; it always uses the stub
/// via the `dart.library.io` guard.
class QrScanner {
  static bool get isSupported => impl.isSupported;
  static Future<QrPayload?> scan(BuildContext context) => impl.scan(context);
}
