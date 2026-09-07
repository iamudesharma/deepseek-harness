import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'qr_payload.dart';
import 'qr_scanner_stub.dart'
    if (dart.library.io) 'qr_scanner_mobile.dart'
    as scanner_impl;

/// Entry point for Add Computer — Scan QR or Manual.
class AddComputerScreen extends StatelessWidget {
  const AddComputerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Computer')),
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
                    'Pair a new computer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'On your computer, run `dsh web --remote` and scan the QR code, or enter the details manually.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      if (!scanner_impl.isSupported) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'QR scanning is only available on Android/iOS. Use manual entry.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                      final payload = await scanner_impl.scan(context);
                      if (payload == null) return;
                      if (!context.mounted) return;
                      context.push('/devices/add/confirm', extra: payload);
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan QR'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/devices/add/manual'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Manual entry'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How it works',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Your computer shows a QR with baseUri, hostId, nonce and optional PIN.\n'
                    '2. You scan it and verify the host fingerprint.\n'
                    '3. Your device sends deviceId/publicKey/nonce/PIN to the host.\n'
                    '4. The host asks for explicit approval (“Allow Pixel 7?”).\n'
                    '5. After approval you receive a bearer token and connect.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
