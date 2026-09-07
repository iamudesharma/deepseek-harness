import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_controller.dart' as conn;

/// Sidebar footer entry for Devices — shows connection state and navigates to /devices.
class SidebarDeviceEntry extends ConsumerWidget {
  const SidebarDeviceEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conn.connectionStateProvider);
    final isNeedsReauth = state == conn.ConnectionState.needsReauth;
    return ListTile(
      dense: true,
      leading: Icon(
        isNeedsReauth ? Icons.lock_outline_rounded : Icons.devices_outlined,
        size: 18,
        color: isNeedsReauth ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text(
        isNeedsReauth ? 'Authentication required' : 'Devices',
        style: TextStyle(
          fontSize: 13,
          color: isNeedsReauth ? Theme.of(context).colorScheme.error : null,
        ),
      ),
      subtitle: Text(state.name, style: const TextStyle(fontSize: 11)),
      trailing: isNeedsReauth
          ? const Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Colors.orange,
            )
          : null,
      onTap: () => context.push('/devices'),
    );
  }
}
