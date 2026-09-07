import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'qr_payload.dart';

/// 6-digit PIN entry — numeric keyboard, auto-advance, paste, clear, retry.
class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({super.key, required this.payload});

  final QrPayload payload;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _ctrl.text.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) {
      setState(() => _error = 'PIN must be 6 digits');
      return;
    }
    // Do not log the PIN
    final payload = QrPayload(
      baseUri: widget.payload.baseUri,
      hostId: widget.payload.hostId,
      hostPublicKey: widget.payload.hostPublicKey,
      nonce: widget.payload.nonce,
      pin: pin,
      exp: widget.payload.exp,
      displayName: widget.payload.displayName,
    );
    context.push('/devices/add/wait', extra: payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter PIN')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Enter the 6-digit PIN shown on your computer.'),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: 'PIN',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                if (v.length == 6) _submit();
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _submit, child: const Text('Continue')),
            TextButton(
              onPressed: () {
                _ctrl.clear();
                setState(() => _error = null);
              },
              child: const Text('Clear'),
            ),
            if (DateTime.now().millisecondsSinceEpoch > widget.payload.exp)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'PIN expired — please generate a new QR on your computer.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
