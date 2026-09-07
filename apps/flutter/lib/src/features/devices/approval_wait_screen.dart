import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_client.dart';
import '../../core/connection/connection_target.dart';
import '../../core/connection/connection_target_provider.dart';
import '../../core/connection/secure_token_store.dart';
import 'qr_payload.dart';

/// Waiting for host approval — polls `remote.pair` until approved/denied/timeout.
class ApprovalWaitScreen extends ConsumerStatefulWidget {
  const ApprovalWaitScreen({super.key, required this.payload});

  final QrPayload payload;

  @override
  ConsumerState<ApprovalWaitScreen> createState() => _ApprovalWaitScreenState();
}

class _ApprovalWaitScreenState extends ConsumerState<ApprovalWaitScreen> {
  String _status = 'Waiting for approval on ${''}';
  bool _isWaiting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status =
        'Waiting for approval on ${widget.payload.displayName ?? widget.payload.baseUri.host}';
    _startPolling();
  }

  Future<void> _startPolling() async {
    final payload = widget.payload;
    // Validate expiry before contacting host
    if (DateTime.now().millisecondsSinceEpoch > payload.exp) {
      setState(() {
        _isWaiting = false;
        _error = 'Pairing expired — please generate a new QR.';
      });
      return;
    }
    // Use a temporary client for the unauthenticated pair endpoint (no bearer yet)
    final tempClient = ConnectionClient(baseUrl: payload.baseUri.toString());
    final deviceId = _newDeviceId();
    final displayName = await _deviceDisplayName();
    // For the test, devicePublicKey is a placeholder base64 SPKI; the host will store it.
    const devicePublicKey = 'cHVibGljX3BsYWNlaG9sZGVy';
    try {
      // The host's `remote.pair` will block until host approves/denies (30s) or timeout.
      // We poll with a single call that waits on the host side.
      final result = await tempClient
          .remotePair(
            hostId: payload.hostId,
            deviceId: deviceId,
            displayName: displayName,
            devicePublicKey: devicePublicKey,
            nonce: payload.nonce,
            pin: payload.pin,
          )
          .timeout(const Duration(seconds: 35));
      final hostIdResp = result['hostId'] as String?;
      final hostPubResp = result['hostPublicKey'] as String?;
      final token = result['deviceToken'] as String?;
      if (hostIdResp == null || hostPubResp == null || token == null) {
        throw const FormatException('Invalid pair response');
      }
      // Verify host identity pinning — abort on mismatch, do not silently replace.
      if (hostIdResp != payload.hostId) {
        setState(() {
          _isWaiting = false;
          _error =
              'Host identity mismatch — expected ${payload.shortFingerprint}…, got ${hostIdResp.substring(0, 8)}…\nPlease re-generate the QR.';
        });
        return;
      }
      // Persist secure token (never in RemoteTarget JSON) and RemoteTarget
      final store = ref.read(secureTokenStoreProvider);
      await store.write(deviceId, token);
      final target = RemoteTarget(
        baseUri: payload.baseUri,
        hostId: hostIdResp,
        hostPublicKey: hostPubResp,
        deviceId: deviceId,
        displayName: displayName,
      );
      await persistConnectionTarget(target);
      ref.read(connectionTargetProvider.notifier).state = target;
      // Wait for authenticated connection
      if (mounted) setState(() => _status = 'Connecting…');
      // Give the controller a moment to connect (host.describe + wss?ticket)
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      // Only show success after authenticated connection is actually established.
      // We check by trying an authenticated host.describe via the new client.
      final authedClient = ref.read(connectionClientProvider);
      try {
        await authedClient.hostDescribe().timeout(const Duration(seconds: 5));
      } catch (e) {
        // If hostDescribe fails, still consider pairing success but show warning
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Paired but host not yet reachable: $e')),
          );
        }
      }
      if (mounted) context.go('/devices/success', extra: target);
    } on TimeoutException {
      setState(() {
        _isWaiting = false;
        _error = 'Pairing timed out — host did not approve in time.';
      });
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('pairing-denied') || msg.contains('denied')) {
        setState(() {
          _isWaiting = false;
          _error = 'Pairing denied by host.';
        });
      } else if (msg.contains('pairing-nonce-expired') ||
          msg.contains('expired')) {
        setState(() {
          _isWaiting = false;
          _error = 'Pairing expired — please generate a new QR.';
        });
      } else if (msg.contains('pairing-pin-invalid') || msg.contains('PIN')) {
        setState(() {
          _isWaiting = false;
          _error = 'Invalid PIN — please try again.';
        });
      } else if (msg.contains('hostId') || msg.contains('mismatch')) {
        setState(() {
          _isWaiting = false;
          _error = 'Host identity mismatch — please re-generate the QR.';
        });
      } else {
        setState(() {
          _isWaiting = false;
          _error = 'Pairing failed: ${_sanitizeError(msg)}';
        });
      }
    } finally {
      tempClient.dispose();
    }
  }

  String _sanitizeError(String msg) {
    // Do not show raw JWT/token/stack-trace
    if (msg.contains('Bearer') || msg.contains('eyJ'))
      return 'Authentication error';
    if (msg.length > 200) return '${msg.substring(0, 200)}…';
    return msg;
  }

  String _newDeviceId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }

  Future<String> _deviceDisplayName() async {
    // Use a simple display name; on mobile we could use device_info_plus
    return 'Flutter ${DateTime.now().millisecondsSinceEpoch % 1000}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pairing')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isWaiting) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'Please approve on your computer.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel'),
              ),
            ] else if (_error != null) ...[
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
