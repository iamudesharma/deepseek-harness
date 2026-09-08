/// Session-header open-in-app action — Flutter port of
/// `packages/client/ui-open-in-app/src/client/index.ts` `apply()`.
///
/// Mounts through the `conversation.session.header.utilities` hole
/// (id `open-in-app`, order -10, like React). Reads the current session's
/// `cwd` from `sessionsProvider` (React `byId[sessionId]?.cwd`) and renders
/// the shared [OpenInAppButton] split button. Renders nothing until the host
/// reports a nameable app and the session has a known directory, matching
/// React's `if (currentEntry === undefined || cwd === '') return null`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../widgets/open_in_app_button.dart';

/// Session-header entry point for open-in-app.
class OpenInAppHeaderAction extends ConsumerWidget {
  /// Creates the header action.
  const OpenInAppHeaderAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentSessionIdProvider);
    final sessions = ref.watch(sessionsProvider);
    final cwd = current == null ? null : sessions.byId[current]?.cwd;
    if (cwd == null || cwd.isEmpty) return const SizedBox.shrink();
    return OpenInAppButton(path: cwd);
  }
}
