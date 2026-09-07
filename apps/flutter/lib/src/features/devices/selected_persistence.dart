import 'package:shared_preferences/shared_preferences.dart';

import '../../core/session/session_models.dart';

const _kSelectedWorkspaceKey = 'dsh_selected_workspace';
const _kSelectedSessionKey = 'dsh_selected_session';

/// Persist the selected workspace id (host-authoritative, from `workspace.list`).
Future<void> persistSelectedWorkspaceId(String workspaceId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSelectedWorkspaceKey, workspaceId);
}

/// Persist the selected session id (host-authoritative, from `session.create`/list).
Future<void> persistSelectedSessionId(String sessionId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSelectedSessionKey, sessionId);
}

/// Both persisted selection ids in one read.
typedef SelectedIds = ({WorkspaceId? workspaceId, SessionId? sessionId});

/// Read both persisted ids (null when absent).
Future<SelectedIds> restoreSelectedIds() async {
  final prefs = await SharedPreferences.getInstance();
  final ws = prefs.getString(_kSelectedWorkspaceKey);
  final sess = prefs.getString(_kSelectedSessionKey);
  return (
    workspaceId: ws == null ? null : WorkspaceId(ws),
    sessionId: sess == null ? null : SessionId(sess),
  );
}

/// Clear only the persisted workspace id (host no longer lists it).
Future<void> clearSelectedWorkspaceId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSelectedWorkspaceKey);
}

/// Clear only the persisted session id (host no longer lists it).
Future<void> clearSelectedSessionId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSelectedSessionKey);
}

/// Clear both selections (device removed / logout / re-pair).
Future<void> clearSelectedWorkspaceAndSession() async {
  await clearSelectedWorkspaceId();
  await clearSelectedSessionId();
}
