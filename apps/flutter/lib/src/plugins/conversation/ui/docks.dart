/// Composer docks + queue surface: bottom strip under the chat view showing
/// registered docks and the authoritative pending-inbox count.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../hub.dart';
import 'queue_sheet.dart';
import '../queue_state.dart';

/// Bottom dock strip for one session.
class DocksRow extends ConsumerWidget {
  /// Creates the strip for one session.
  const DocksRow({super.key, required this.sessionId});

  /// Owning session id.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = activatedHub;
    if (hub == null) return const SizedBox.shrink();

    final queueCount =
        ref
            .watch(queueProvider)[sessionId]
            ?.where((i) => i.placement != 'context')
            .length ??
        0;

    // No docks and no queued rows → no strip at all (the React input dock
    // renders null when its entries are empty).
    if (queueCount == 0 && hub.controller.dockIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (queueCount > 0)
            InkWell(
              onTap: () => showModalBottomSheet(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => QueueSheet(sessionId: sessionId),
              ),
              borderRadius: BorderRadius.circular(10),
              child: _Chip(
                icon: Icons.low_priority,
                label: '$queueCount queued',
              ),
            ),
          for (final id in hub.controller.dockIds)
            KeyedSubtree(
              key: ValueKey('dock-$id'),
              child: hub.controller.dock(id)(context),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: aliases.labelSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
