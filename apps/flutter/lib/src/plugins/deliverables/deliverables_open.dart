/// Host path-opening facts for the produced-files row — the Dart slice of
/// React `ui-deliverables` `apply()` (`canOpenWorkspacePath` capability poll)
/// plus the `session/openWorkspacePath` handoff (`ui-chat` `openFile` owner).
///
/// React gates the affordance on `isLoopback && hostCanOpen`; Flutter has no
/// browser-privilege half, so the gate is the Host's own answer: the opener
/// capability is a host-desktop fact, and `openWorkspacePath` runs on the
/// host machine either way — never a client-side launcher open.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection_client.dart';

/// Whether the host desktop can open Session workspace paths.
///
/// `false` on transport failure so a disconnected client loses only the
/// affordance, never its data; invalidate after reconnect to re-poll (React
/// re-polls on `connection/reset`).
final canOpenHostPathProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(connectionClientProvider);
  try {
    return await client.canOpenWorkspacePath();
  } catch (_) {
    return false;
  }
});

/// Opens [path] through the host's native opener (React `openFile('.')`
/// show-in-folder uses the same seam with the directory dot).
Future<void> openHostPath(ConnectionClient client, String path) {
  return client.openWorkspacePath(path: path);
}
