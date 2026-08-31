import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'qr_payload.dart';

/// Manual entry — host URL/IP, hostId, PIN.
///
/// Validates hostId (43-char base64url), baseUri, and PIN (6-digit) before
/// navigating to host confirmation. Does not log the PIN.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostCtrl = TextEditingController(text: 'https://192.168.1.10:3080');
  final _hostIdCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _nonceCtrl = TextEditingController();

  @override
  void dispose() {
    _hostCtrl.dispose();
    _hostIdCtrl.dispose();
    _pinCtrl.dispose();
    _nonceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual entry')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'Host URL',
                hintText: 'https://192.168.1.10:3080',
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final uri = Uri.tryParse(v.trim());
                if (uri == null || !uri.hasScheme || !uri.hasAuthority)
                  return 'Invalid URL';
                if (uri.scheme != 'https') return 'Use https:// for remote';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hostIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Host ID',
                hintText: '43-char base64url',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(v.trim()))
                  return 'Invalid hostId';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nonceCtrl,
              decoration: const InputDecoration(
                labelText: 'Pairing nonce',
                hintText: 'UUID',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!RegExp(
                  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
                  caseSensitive: false,
                ).hasMatch(v.trim())) {
                  return 'Invalid nonce';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pinCtrl,
              decoration: const InputDecoration(
                labelText: 'PIN (if required)',
                hintText: '6 digits',
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                if (!RegExp(r'^[0-9]{6}$').hasMatch(v))
                  return 'PIN must be 6 digits';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                try {
                  final payload = QrPayload(
                    baseUri: Uri.parse(_hostCtrl.text.trim()),
                    hostId: _hostIdCtrl.text.trim(),
                    hostPublicKey:
                        'placeholder', // Will be fetched from host on pairing
                    nonce: _nonceCtrl.text.trim(),
                    pin: _pinCtrl.text.trim().isEmpty
                        ? null
                        : _pinCtrl.text.trim(),
                    exp: DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000,
                  );
                  if (context.mounted)
                    context.push('/devices/add/confirm', extra: payload);
                } catch (e) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Invalid: $e')));
                }
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
