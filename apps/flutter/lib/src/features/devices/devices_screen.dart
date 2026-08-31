import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_client.dart';
import '../../core/connection/connection_controller.dart' as conn;
import '../../core/connection/connection_target.dart';
import '../../core/connection/connection_target_provider.dart';
import '../../core/connection/secure_token_store.dart';
import '../../theme/app_theme.dart';
import 'selected_persistence.dart';

/// Devices screen — paired computers.
///
/// Shows host display name, hostId fingerprint, online/offline state,
/// last connected, selected/active indicator, and actions for
/// Add / Select / Reconnect / Remove. Does not expose bearer token.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  bool _loadingDevices = false;
  List<Map<String, dynamic>> _remoteDevices = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRemoteDevices();
  }

  Future<void> _loadRemoteDevices() async {
    final target = ref.read(connectionTargetProvider);
    if (target is! RemoteTarget) return;
    setState(() => _loadingDevices = true);
    try {
      final client = ref.read(connectionClientProvider);
      final result = await client.callMethod('remote/devices', {});
      final list = result['devices'] as List?;
      _remoteDevices =
          list
              ?.whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList() ??
          [];
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(connectionTargetProvider);
    final connectionState = ref.watch(connectionStateProvider);
    final aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current target card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: aliases.labelPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (target is LocalTarget)
                    ListTile(
                      leading: const Icon(Icons.computer_outlined),
                      title: const Text('This Computer (Local)'),
                      subtitle: Text(
                        '${target.host}:${target.port} • ${connectionState.name}',
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: aliases.stateBusinessTertiary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Active',
                          style: TextStyle(
                            color: aliases.stateBusinessPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  else if (target is RemoteTarget)
                    ListTile(
                      leading: const Icon(Icons.phone_android_outlined),
                      title: Text(target.displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${target.baseUri.host} • ${connectionState.name}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Host: ${target.hostId.substring(0, 8)}…',
                            style: TextStyle(
                              fontSize: 11,
                              color: aliases.labelSecondary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      trailing: _buildStateChip(connectionState, aliases),
                    ),
                  if (connectionState == conn.ConnectionState.needsReauth)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: aliases.stateErrorSecondary.withValues(
                            alpha: 0.15,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                              color: aliases.stateErrorPrimary,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Authentication required — please re-pair.',
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.push('/devices/add'),
                              child: const Text('Re-pair'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Actions
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => context.push('/devices/add'),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Computer'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final controller = ref.read(flutterConnectionProvider);
                  final connectionState = ref.read(connectionStateProvider);
                  if (connectionState == conn.ConnectionState.connected) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Already connected')),
                    );
                    return;
                  }
                  controller.stop();
                  await Future<void>.delayed(const Duration(milliseconds: 150));
                  if (!context.mounted) return;
                  ref.invalidate(flutterConnectionProvider);
                  ref.read(flutterConnectionProvider).start();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Reconnecting…')),
                  );
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reconnect'),
              ),
              if (target is RemoteTarget)
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Remove Computer?'),
                        content: Text(
                          'Remove "${target.displayName}" and delete its credentials? This cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    final store = ref.read(secureTokenStoreProvider);
                    await store.delete(target.deviceId);
                    await clearPersistedTarget();
                    await clearSelectedWorkspaceAndSession();
                    ref.read(connectionTargetProvider.notifier).state =
                        const LocalTarget();
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Computer removed')),
                      );
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Remote devices from host (when connected)
          if (target is RemoteTarget) ...[
            Text(
              'Paired devices on host',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (_loadingDevices)
              const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(
                'Failed to load devices: $_error',
                style: TextStyle(color: aliases.stateErrorPrimary),
              ),
            for (final d in _remoteDevices)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(
                    d['displayName'] as String? ?? d['deviceId'] as String,
                  ),
                  subtitle: Text(
                    'Created: ${DateTime.fromMillisecondsSinceEpoch((d['createdAt'] as num?)?.toInt() ?? 0).toLocal()} • ${d['revoked'] == true ? 'Revoked' : 'Active'}',
                  ),
                  trailing: d['deviceId'] == target.deviceId
                      ? const Chip(
                          label: Text('This device'),
                          visualDensity: VisualDensity.compact,
                        )
                      : IconButton(
                          icon: const Icon(Icons.block_rounded),
                          tooltip: 'Revoke',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Revoke device?'),
                                content: Text(
                                  'Revoke "${d['displayName']}"? It will need to re-pair.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('Revoke'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              final client = ref.read(connectionClientProvider);
                              await client.callMethod('remote/revoke', {
                                'deviceId': d['deviceId'],
                              });
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Device revoked'),
                                  ),
                                );
                              _loadRemoteDevices();
                            } catch (e) {
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Revoke failed: $e')),
                                );
                            }
                          },
                        ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          // Connection banner compact
          _ConnectionStatusCard(state: connectionState),
        ],
      ),
    );
  }

  Widget _buildStateChip(conn.ConnectionState state, DswAliases aliases) {
    final map = {
      conn.ConnectionState.connected: (
        'Online',
        aliases.stateBusinessPrimary,
        aliases.stateBusinessTertiary,
      ),
      conn.ConnectionState.connecting: (
        'Connecting',
        aliases.stateBusinessPrimary,
        aliases.stateBusinessTertiary,
      ),
      conn.ConnectionState.reconnecting: (
        'Reconnecting',
        aliases.stateWarnLabel,
        aliases.stateWarnTertiary,
      ),
      conn.ConnectionState.disconnected: (
        'Offline',
        aliases.stateErrorPrimary,
        aliases.stateErrorSecondary,
      ),
      conn.ConnectionState.needsReauth: (
        'Needs re-auth',
        aliases.stateErrorPrimary,
        aliases.stateErrorSecondary,
      ),
      conn.ConnectionState.idle: (
        'Idle',
        aliases.labelSecondary,
        aliases.bgBase,
      ),
    };
    final entry =
        map[state] ?? ('Unknown', aliases.labelSecondary, aliases.bgBase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (entry.$3 as Color).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        entry.$1,
        style: TextStyle(color: entry.$2 as Color, fontSize: 12),
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({required this.state});
  final conn.ConnectionState state;
  @override
  Widget build(BuildContext context) {
    final aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    String label;
    switch (state) {
      case conn.ConnectionState.connected:
        label = 'Connected';
        break;
      case conn.ConnectionState.connecting:
        label = 'Connecting…';
        break;
      case conn.ConnectionState.reconnecting:
        label = 'Reconnecting…';
        break;
      case conn.ConnectionState.disconnected:
        label = 'Disconnected';
        break;
      case conn.ConnectionState.needsReauth:
        label = 'Authentication required';
        break;
      case conn.ConnectionState.idle:
        label = 'Idle';
        break;
    }
    return Card(
      child: ListTile(
        leading: Icon(
          state == conn.ConnectionState.connected
              ? Icons.check_circle_outline_rounded
              : Icons.sync_rounded,
          color: state == conn.ConnectionState.connected
              ? aliases.stateBusinessPrimary
              : aliases.labelSecondary,
        ),
        title: Text(label),
        subtitle: Text('State: ${state.name}'),
      ),
    );
  }
}
