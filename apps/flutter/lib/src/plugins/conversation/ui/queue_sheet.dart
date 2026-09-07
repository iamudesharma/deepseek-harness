import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/frames.dart';
import '../../../core/session/session_models.dart';
import '../../../theme/app_theme.dart';
import '../hub.dart';
import '../queue_state.dart';

/// Bottom sheet that lists authoritative queued inbox items and exposes
/// per-item edit/remove/steer via the canonical `session.updateQueue`.
///
/// Only `queued` and `steering` placements are visible (mirrors React's
/// `QueueDock` filtering). `context` items stay invisible until the agent
/// claims them. Host remains authoritative — sheet reflects `queueProvider`
/// which is driven by `session/queue` frames, and actions only complete
/// when the host pushes the updated snapshot.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key, required this.sessionId});
  final String sessionId;

  String _preview(QueuedInboxItem item) {
    final msg = item.message;
    // Try to extract text preview from the queued message's content blocks.
    // The host stores `message` as the original prompt's wire shape; for
    // queued user messages it's typically {content: [{type:'text',text:...}]}.
    final content = msg['content'];
    if (content is List) {
      final texts = content
          .whereType<Map>()
          .map((b) => b['text'])
          .whereType<String>()
          .toList();
      if (texts.isNotEmpty) return texts.join(' ').trim();
    }
    // Fallback to direct text field or id.
    final text = msg['text'];
    if (text is String && text.isNotEmpty) return text;
    return item.id;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        (ref.watch(queueProvider)[sessionId] ?? const <QueuedInboxItem>[])
            .where((i) => i.placement != 'context')
            .toList();
    final aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.low_priority, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${items.length} queued',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 16),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No queued messages',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: aliases.labelSecondary),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final item = items[idx];
                    final preview = _preview(item);
                    final isSteering = item.placement == 'steering';
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.placement} • ${item.id}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            if (!isSteering)
                              IconButton(
                                tooltip: 'Steer',
                                icon: const Icon(
                                  Icons.airplanemode_active,
                                  size: 16,
                                ),
                                onPressed: () async {
                                  final hub = activatedHub;
                                  if (hub == null) return;
                                  try {
                                    await hub.controller.updateQueue(
                                      SessionId(sessionId),
                                      MessageId(item.id),
                                      const QueueActionSteer(),
                                    );
                                  } catch (e) {
                                    if (context.mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text('Steer failed: $e'),
                                            ),
                                          );
                                  }
                                },
                              ),
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              onPressed: () async {
                                final controller = TextEditingController(
                                  text: preview,
                                );
                                final newText = await showDialog<String>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Edit queued message'),
                                    content: TextField(
                                      controller: controller,
                                      autofocus: true,
                                      maxLines: 4,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, controller.text),
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                );
                                controller.dispose();
                                if (newText == null ||
                                    newText.trim().isEmpty ||
                                    newText == preview)
                                  return;
                                final hub = activatedHub;
                                if (hub == null) return;
                                try {
                                  await hub.controller.updateQueue(
                                    SessionId(sessionId),
                                    MessageId(item.id),
                                    QueueActionEdit([
                                      {'type': 'text', 'text': newText},
                                    ]),
                                  );
                                } catch (e) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Edit failed: $e'),
                                      ),
                                    );
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline, size: 16),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Remove queued message?'),
                                    content: Text(
                                      '"$preview" will be removed from the queue.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                final hub = activatedHub;
                                if (hub == null) return;
                                try {
                                  await hub.controller.updateQueue(
                                    SessionId(sessionId),
                                    MessageId(item.id),
                                    const QueueActionRemove(),
                                  );
                                } catch (e) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Remove failed: $e'),
                                      ),
                                    );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            if (items.any((i) => i.placement == 'queued'))
              FilledButton.icon(
                onPressed: () async {
                  final hub = activatedHub;
                  if (hub == null) return;
                  // Steer all queued items via the same hook the empty-draft Enter uses.
                  for (final item in items.where(
                    (i) => i.placement == 'queued',
                  )) {
                    try {
                      await hub.controller.updateQueue(
                        SessionId(sessionId),
                        MessageId(item.id),
                        const QueueActionSteer(),
                      );
                    } catch (_) {}
                  }
                },
                icon: const Icon(Icons.airplanemode_active, size: 16),
                label: const Text('Steer all queued'),
              ),
          ],
        ),
      ),
    );
  }
}
