/// Composer docks + queue surface: bottom strip under the chat view showing
/// registered docks and the authoritative pending-inbox count.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/frames.dart' show QueuedInboxItem;
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../features/conversation/message_provider.dart'
    show MessageRole, optimisticMessagesProvider;
import '../../../theme/app_theme.dart';
import '../../conversation/locales.dart' show kConversationNamespace;
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

    // React `QueueDock.rowCount`: durable `queued` rows plus local submission
    // echoes not yet admitted by queue rpcId.
    final queued =
        ref
            .watch(queueProvider)[sessionId]
            ?.where((i) => i.placement == 'queued')
            .toList() ??
        const <QueuedInboxItem>[];
    final admitted = queued.map((r) => r.rpcId).whereType<String>().toSet();
    final pendingCount = ref
        .watch(optimisticMessagesProvider(sessionId))
        .where(
          (m) =>
              m.role == MessageRole.user &&
              m.requestId != null &&
              !admitted.contains(m.requestId),
        )
        .length;
    final queueCount = queued.length + pendingCount;

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
    final t = ref.bindLocale(kConversationNamespace);

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
                label: t('queue.count').replaceAll('{n}', '$queueCount'),
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
