import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_controller.dart' as conn;
import '../../core/connection/connection_target.dart';

/// Shown only after the authenticated connection is actually established.
class PairingSuccessScreen extends ConsumerWidget {
  const PairingSuccessScreen({super.key, required this.target});

  final RemoteTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conn.connectionStateProvider);
    final isConnected = state == conn.ConnectionState.connected;
    return Scaffold(
      appBar: AppBar(title: const Text('Paired')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isConnected
                  ? Icons.check_circle_outline_rounded
                  : Icons.sync_rounded,
              size: 64,
              color: isConnected ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              isConnected
                  ? 'Connected to ${target.displayName}'
                  : 'Paired — connecting…',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${target.baseUri.host} • ${target.hostId.substring(0, 8)}…',
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'State: ${state.name}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Done'),
            ),
            if (!isConnected) ...[
              const SizedBox(height: 8),
              const Text(
                'Waiting for authenticated host.describe + wss?ticket…',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
