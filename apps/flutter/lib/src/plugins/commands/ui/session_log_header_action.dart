/// Session-log download header action — Flutter port of
/// `packages/session-query/session-log-export/src/client/HeaderAction.tsx`.
///
/// Mounts through the `conversation.session.header.utilities` hole
/// (id `session-log-download`, like React). The capsule triggers
/// [SessionExportService.download] for the current session; while busy it
/// disables with the dimmed waiting posture, and failures surface through a
/// SnackBar (the dialog stays host-side). Renders nothing without a current
/// session, matching React's session-scoped mount.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart' show kSessionLogDownloadNamespace;
import '../session_export.dart'
    show SessionExportService, SessionExportException;

/// Session-header entry point for the session-log download.
class SessionLogHeaderAction extends ConsumerStatefulWidget {
  /// Creates the header action.
  const SessionLogHeaderAction({super.key});

  @override
  ConsumerState<SessionLogHeaderAction> createState() =>
      _SessionLogHeaderActionState();
}

class _SessionLogHeaderActionState
    extends ConsumerState<SessionLogHeaderAction> {
  bool _busy = false;

  Future<void> _download(SessionId sessionId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SessionExportService(ref.read(connectionClientProvider))
          .download(sessionId);
    } on SessionExportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session log download failed.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionId? current = ref.watch(currentSessionIdProvider);
    if (current == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final t = ref.bindLocale(kSessionLogDownloadNamespace);
    // React `.sessionLogButton`: 26px capsule, 5/10 padding, 5px gap,
    // 0.5px l4 border, 13px radius, 11/16 primary text, 10px secondary icon.
    final Color foreground = _busy
        ? aliases.labelCaption
        : aliases.labelPrimary;
    return Semantics(
      button: true,
      enabled: !_busy,
      child: InkWell(
        onTap: _busy ? null : () => _download(current),
        borderRadius: BorderRadius.circular(13),
        hoverColor: aliases.interactiveBgHover,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: aliases.borderL4, width: 0.5),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t('header.action'),
                style: TextStyle(
                  fontSize: 11,
                  height: 16 / 11,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.download_rounded,
                size: 10,
                color: _busy ? foreground : aliases.labelSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
