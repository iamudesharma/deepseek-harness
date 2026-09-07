import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'qr_payload.dart';

/// Host identity confirmation — shows display name, address, fingerprint.
class HostConfirmScreen extends StatelessWidget {
  const HostConfirmScreen({super.key, required this.payload});

  final QrPayload payload;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm host')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This identifies the computer you are pairing.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  _row('Host', payload.displayName ?? 'Unknown computer'),
                  _row('Address', payload.baseUri.toString()),
                  _row('Host identity', '${payload.shortFingerprint}…'),
                  const SizedBox(height: 8),
                  Text(
                    payload.hostId,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'If the host identity differs from what your computer shows, abort and re-generate the QR. '
                    'Do not silently replace the pinned identity.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (payload.pin != null) {
                context.push('/devices/add/pin', extra: payload);
              } else {
                context.push('/devices/add/wait', extra: payload);
              }
            },
            child: const Text('Confirm and pair'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          if (payload.pin != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'PIN required: ${payload.pin!.substring(0, 2)}••••',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}
