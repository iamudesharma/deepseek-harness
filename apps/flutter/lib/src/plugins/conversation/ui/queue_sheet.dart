import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/frames.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../core/session/session_models.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../features/conversation/message_provider.dart'
    show Message, MessageRole, optimisticMessagesProvider;
import '../../../theme/app_theme.dart';
import '../../conversation/locales.dart' show kConversationNamespace;
import '../hub.dart';
import '../queue_state.dart';

/// Bottom sheet listing the session's queue with per-item edit/remove/steer.
///
/// Flutter port of React `QueueDock` (`queue/QueueDock.tsx`) in sheet chrome:
/// only `queued` rows show (React filters `placement === 'queued'`), plus
/// local submission echoes (still-pending optimistic prompts not yet admitted
/// by queue `rpcId`, React `pendingQueue`) with sending status and disabled
/// actions until their host rows arrive. Actions run through the canonical
/// `session.updateQueue`; failures surface localized notices and the busy row
/// disables its actions while its RPC is in flight.
class QueueSheet extends ConsumerStatefulWidget {
  const QueueSheet({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<QueueSheet> createState() => _QueueSheetState();
}

/// Text content of a queued wire message, or null for non-text rows
/// (React `row.text === null` disables edit with the unsupported hint).
String? _rowText(Map<String, Object?> msg) {
  final content = msg['content'];
  if (content is List) {
    final texts = content
        .whereType<Map>()
        .map((b) => b['text'])
        .whereType<String>()
        .toList();
    if (texts.isNotEmpty) return texts.join(' ').trim();
  }
  final text = msg['text'];
  if (text is String && text.isNotEmpty) return text;
  return null;
}

class _QueueSheetState extends ConsumerState<QueueSheet> {
  /// Item id with an in-flight `updateQueue` RPC (React `busy`).
  String? _busyId;

  String _fill(String template, Map<String, String> values) {
    var out = template;
    values.forEach((key, value) {
      out = out.replaceAll('{$key}', value);
    });
    return out;
  }

  Future<bool> _applyAction(
    String itemId,
    QueueAction action,
    String failure,
  ) async {
    final hub = activatedHub;
    if (hub == null) return false;
    setState(() => _busyId = itemId);
    try {
      await hub.controller.updateQueue(
        SessionId(widget.sessionId),
        MessageId(itemId),
        action,
      );
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure)));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          if (_busyId == itemId) _busyId = null;
        });
      }
    }
  }

  Future<void> _editRow(
    String itemId,
    String initial,
    String Function(String) t,
  ) async {
    final controller = TextEditingController(text: initial);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('queue.edit')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('queue.cancelEdit')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(t('queue.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newText == null || newText.trim().isEmpty || newText == initial) {
      return;
    }
    await _applyAction(
      itemId,
      QueueActionEdit([
        {'type': 'text', 'text': newText},
      ]),
      t('queue.editFailed'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.bindLocale(kConversationNamespace);
    final running = ref.watch(
      sessionsProvider.select(
        (s) => s.byId[SessionId(widget.sessionId)]?.running ?? false,
      ),
    );
    final rows =
        (ref.watch(queueProvider)[widget.sessionId] ??
                const <QueuedInboxItem>[])
            .where((i) => i.placement == 'queued')
            .toList();
    // Local submission echoes: optimistic user prompts carrying a requestId
    // the host has not admitted yet (React `pendingQueue`: queued placement,
    // requestId absent from admitted queue rpcIds).
    final admitted = rows.map((r) => r.rpcId).whereType<String>().toSet();
    final pending = ref
        .watch(optimisticMessagesProvider(widget.sessionId))
        .where(
          (m) =>
              m.role == MessageRole.user &&
              m.requestId != null &&
              !admitted.contains(m.requestId),
        )
        .toList();
    final rowCount = rows.length + pending.length;

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
                Icon(
                  Icons.low_priority,
                  size: 14,
                  color: aliases.labelTertiary,
                ),
                const SizedBox(width: 10),
                Text(
                  _fill(t('queue.count'), {'n': '$rowCount'}),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXs13,
                    height: 24 / 13,
                    fontWeight: FontWeight.w500,
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
            const SizedBox(height: 8),
            if (rowCount > 0)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length + pending.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: aliases.borderL1,
                    indent: 12,
                    endIndent: 5,
                  ),
                  itemBuilder: (context, idx) {
                    if (idx < rows.length) {
                      return _QueueRow(
                        key: ValueKey('queue-${rows[idx].id}'),
                        text: _rowText(rows[idx].message),
                        fallback: rows[idx].id,
                        status: null,
                        running: running,
                        aliases: aliases,
                        t: t.call,
                        onEdit: _busyId != null
                            ? null
                            : () => _editRow(
                                rows[idx].id,
                                _rowText(rows[idx].message) ?? '',
                                t.call,
                              ),
                        onRemove: _busyId != null
                            ? null
                            : () => _applyAction(
                                rows[idx].id,
                                const QueueActionRemove(),
                                t('queue.removeFailed'),
                              ),
                        onSteer: _busyId != null || !running
                            ? null
                            : () => _applyAction(
                                rows[idx].id,
                                const QueueActionSteer(),
                                t('queue.steerFailed'),
                              ),
                      );
                    }
                    final Message echo = pending[idx - rows.length];
                    return _QueueRow(
                      key: ValueKey('queue-pending-${echo.requestId}'),
                      text: echo.content,
                      fallback: echo.requestId!,
                      status: t('queue.sending'),
                      running: running,
                      aliases: aliases,
                      t: t.call,
                      onEdit: null,
                      onRemove: null,
                      onSteer: null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One queue row: preview text, optional sending status, edit/remove/steer
/// actions (React `.row`: 36px, 13px preview, 28px circle actions).
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.text,
    required this.fallback,
    required this.status,
    required this.running,
    required this.aliases,
    required this.t,
    required this.onEdit,
    required this.onRemove,
    required this.onSteer,
  });

  /// Text preview, or null for non-text rows (edit disabled).
  final String? text;
  final String fallback;
  final String? status;
  final bool running;
  final DswAliases aliases;
  final String Function(String key) t;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final VoidCallback? onSteer;

  @override
  Widget build(BuildContext context) {
    final bool editable = text != null;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Icon(Icons.low_priority, size: 14, color: aliases.labelTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text ?? fallback,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.labelPrimaryDimmed,
              ),
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: 10),
            Text(
              status!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXs13,
                color: aliases.labelTertiary,
              ),
            ),
          ],
          const SizedBox(width: 10),
          _QueueAction(
            tooltip: editable ? t('queue.edit') : t('queue.edit.unsupported'),
            icon: Icons.edit_outlined,
            aliases: aliases,
            onPressed: editable ? onEdit : null,
          ),
          _QueueAction(
            tooltip: t('queue.remove'),
            icon: Icons.delete_outline,
            aliases: aliases,
            onPressed: onRemove,
          ),
          Tooltip(
            message: running ? t('queue.steer') : t('queue.steer.unavailable'),
            waitDuration: const Duration(milliseconds: 500),
            child: _QueueAction(
              tooltip: null,
              icon: Icons.send_outlined,
              aliases: aliases,
              onPressed: onSteer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 28px circle row action (React `.action`): tertiary glyph, hover tint,
/// 0.45 opacity while disabled.
class _QueueAction extends StatelessWidget {
  const _QueueAction({
    required this.tooltip,
    required this.icon,
    required this.aliases,
    required this.onPressed,
  });

  final String? tooltip;
  final IconData icon;
  final DswAliases aliases;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Widget button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          hoverColor: aliases.interactiveBgHover,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Icon(icon, size: 14, color: aliases.labelTertiary),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    // Disabled buttons fire no hover events, so the unsupported hint stays
    // a native title (React QueueDock).
    if (!enabled) {
      return Tooltip(message: tooltip, child: button);
    }
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 500),
      child: button,
    );
  }
}
