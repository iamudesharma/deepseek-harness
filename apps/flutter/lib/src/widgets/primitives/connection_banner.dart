import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart' as conn;
import '../../theme/app_theme.dart';

/// Connection status banner — Flutter port of the web connection chrome.
///
/// Shows context-aware messaging for each [conn.ConnectionState]. Returns
/// [SizedBox.shrink] when [state] is [conn.ConnectionState.connected] or
/// [conn.ConnectionState.idle]. Pure build.
class DsConnectionBanner extends ConsumerWidget {
  const DsConnectionBanner({super.key, required this.state});

  /// Current connection state.
  final conn.ConnectionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // No banner when connected/idle.
    if (state == conn.ConnectionState.connected ||
        state == conn.ConnectionState.idle) {
      return const SizedBox.shrink();
    }

    late final Color bg;
    late final Color fg;
    late final Color border;
    late final IconData icon;
    late final String label;
    late final String detail;

    switch (state) {
      case conn.ConnectionState.connecting:
        bg = aliases.stateBusinessTertiary;
        fg = aliases.stateBusinessPrimary;
        border = aliases.stateBusinessPrimary.withValues(alpha: 0.2);
        icon = Icons.sync_rounded;
        label = 'Connecting';
        detail = 'Establishing connection…';
        break;
      case conn.ConnectionState.reconnecting:
        bg = aliases.stateWarnTertiary;
        fg = aliases.stateWarnLabel;
        border = aliases.stateWarnPrimary.withValues(alpha: 0.25);
        icon = Icons.sync_rounded;
        label = 'Reconnecting';
        detail = 'Connection lost — retrying…';
        break;
      case conn.ConnectionState.disconnected:
        bg = aliases.stateErrorSecondary.withValues(alpha: 0.15);
        fg = aliases.stateErrorPrimary;
        border = aliases.stateErrorPrimary.withValues(alpha: 0.2);
        icon = Icons.cloud_off_rounded;
        label = 'Disconnected';
        detail = 'No active connection.';
        break;
      case conn.ConnectionState.needsReauth:
        bg = aliases.stateErrorSecondary.withValues(alpha: 0.15);
        fg = aliases.stateErrorPrimary;
        border = aliases.stateErrorPrimary.withValues(alpha: 0.2);
        icon = Icons.lock_outline_rounded;
        label = 'Needs re-auth';
        detail = 'Session expired — please re-pair.';
        break;
      case conn.ConnectionState.connected:
      case conn.ConnectionState.idle:
        // Handled above.
        bg = DswTokens.transparent;
        fg = aliases.labelPrimary;
        border = aliases.borderL2;
        icon = Icons.check_circle_outline;
        label = '';
        detail = '';
        break;
    }

    final bool isBusy =
        state == conn.ConnectionState.connecting ||
        state == conn.ConnectionState.reconnecting;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceMd,
        vertical: DswTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: border),
      ),
      child: Row(
        children: <Widget>[
          if (isBusy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else
            Icon(icon, size: 14, color: fg),
          const SizedBox(width: DswTokens.spaceSm),
          Text(
            label,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          const SizedBox(width: DswTokens.spaceSm),
          Expanded(
            child: Text(
              detail,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
