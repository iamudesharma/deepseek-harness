import 'package:flutter/material.dart';

import 'qr_payload.dart';

/// Stub for Web/macOS — no camera, manual entry only.
bool get isSupported => false;

Future<QrPayload?> scan(BuildContext context) async {
  // Web/macOS: show a dialog that manual entry is required.
  if (context.mounted) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR scanning not available'),
        content: const Text(
          'QR scanning is only available on Android/iOS. Please use manual entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  return null;
}
