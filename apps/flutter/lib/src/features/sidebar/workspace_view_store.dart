import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar.dart';

const String _kPersistKey = 'dsh.workspace.view.v5';

/// Snapshot of the workspace view store — mirrors `WorkspaceViewState` in
/// `packages/client/ui-workspace/src/client/stores.ts` persisted under
/// `dsh.workspace.view.v5` via `defineStore` `persist`.
class WorkspaceViewSnapshot {
  const WorkspaceViewSnapshot({
    required this.groupBy,
    required this.orderBy,
    required this.groupExpansion,
    required this.sessionOrderByAccount,
    required this.sessionUpdatedAtByAccount,
  });

  final SessionGroupBy groupBy;
  final SessionOrderBy orderBy;
  final Map<String, bool> groupExpansion;
  final Map<String, List<String>> sessionOrderByAccount;
  final Map<String, Map<String, int>> sessionUpdatedAtByAccount;

  Map<String, dynamic> toJson() => {
        'groupBy': groupBy == SessionGroupBy.workspace ? 'workspace' : 'flat',
        'orderBy': orderBy == SessionOrderBy.manual ? 'manual' : 'updated',
        'groupExpansion': groupExpansion,
        'sessionOrderByAccount': sessionOrderByAccount,
        'sessionUpdatedAtByAccount': sessionUpdatedAtByAccount,
      };

  static WorkspaceViewSnapshot fromJson(Map<String, dynamic> json) {
    final groupByStr = json['groupBy'] as String?;
    final orderByStr = json['orderBy'] as String?;
    final groupBy = groupByStr == 'flat' ? SessionGroupBy.flat : SessionGroupBy.workspace;
    final orderBy = orderByStr == 'manual' ? SessionOrderBy.manual : SessionOrderBy.updated;
    final groupExpansion = (json['groupExpansion'] as Map?)?.map((k, v) => MapEntry(k as String, v as bool)) ?? <String, bool>{};
    final sessionOrderByAccount = (json['sessionOrderByAccount'] as Map?)?.map((k, v) => MapEntry(k as String, (v as List).whereType<String>().toList())) ?? <String, List<String>>{};
    final sessionUpdatedAtByAccount = (json['sessionUpdatedAtByAccount'] as Map?)?.map((k, v) => MapEntry(k as String, (v as Map).map((kk, vv) => MapEntry(kk as String, (vv as num).toInt())))) ?? <String, Map<String, int>>{};
    return WorkspaceViewSnapshot(
      groupBy: groupBy,
      orderBy: orderBy,
      groupExpansion: Map<String, bool>.from(groupExpansion),
      sessionOrderByAccount: Map<String, List<String>>.from(sessionOrderByAccount),
      sessionUpdatedAtByAccount: Map<String, Map<String, int>>.from(sessionUpdatedAtByAccount),
    );
  }

  static const WorkspaceViewSnapshot initial = WorkspaceViewSnapshot(
    groupBy: SessionGroupBy.workspace,
    orderBy: SessionOrderBy.updated,
    groupExpansion: <String, bool>{},
    sessionOrderByAccount: <String, List<String>>{},
    sessionUpdatedAtByAccount: <String, Map<String, int>>{},
  );
}

/// Load persisted view snapshot from SharedPreferences (or `null` if absent/corrupt).
Future<WorkspaceViewSnapshot?> loadWorkspaceView() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPersistKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return WorkspaceViewSnapshot.fromJson(decoded);
    if (decoded is Map) return WorkspaceViewSnapshot.fromJson(decoded.cast<String, dynamic>());
  } catch (_) {}
  return null;
}

/// Persist snapshot to SharedPreferences.
Future<void> persistWorkspaceView(WorkspaceViewSnapshot snapshot) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPersistKey, jsonEncode(snapshot.toJson()));
  } catch (_) {}
}

/// Provider that initializes workspace view providers from persisted state and
/// keeps them in sync. Call `ref.watch(workspaceViewPersistenceProvider)` once
/// at app start (e.g. in sidebar) to activate.
final workspaceViewPersistenceProvider = Provider<void>((ref) {
  // Load once asynchronously and hydrate the four StateProviders.
  loadWorkspaceView().then((snapshot) {
    if (snapshot == null) return;
    // Hydrate only if the providers still hold initial values (avoid clobbering user edits that happened before load).
    // We set regardless — load is early.
    ref.read(workspaceGroupByProvider.notifier).state = snapshot.groupBy;
    ref.read(workspaceOrderByProvider.notifier).state = snapshot.orderBy;
    ref.read(workspaceExpandedProvider.notifier).state = snapshot.groupExpansion;
    ref.read(workspaceSessionOrderProvider.notifier).state = snapshot.sessionOrderByAccount;
    // sessionUpdatedAt tracking is kept in memory only for promotion logic; we store it but don't expose a provider yet.
    // For now, we keep it in a separate provider below.
    ref.read(workspaceSessionUpdatedAtProvider.notifier).state = snapshot.sessionUpdatedAtByAccount;
  });

  void save() {
    final snap = WorkspaceViewSnapshot(
      groupBy: ref.read(workspaceGroupByProvider),
      orderBy: ref.read(workspaceOrderByProvider),
      groupExpansion: Map<String, bool>.from(ref.read(workspaceExpandedProvider)),
      sessionOrderByAccount: Map<String, List<String>>.from(ref.read(workspaceSessionOrderProvider)),
      sessionUpdatedAtByAccount: Map<String, Map<String, int>>.from(ref.read(workspaceSessionUpdatedAtProvider)),
    );
    persistWorkspaceView(snap);
  }

  ref.listen<SessionGroupBy>(workspaceGroupByProvider, (_, __) => save());
  ref.listen<SessionOrderBy>(workspaceOrderByProvider, (_, __) => save());
  ref.listen<Map<String, bool>>(workspaceExpandedProvider, (_, __) => save());
  ref.listen<Map<String, List<String>>>(workspaceSessionOrderProvider, (_, __) => save());
  ref.listen<Map<String, Map<String, int>>>(workspaceSessionUpdatedAtProvider, (_, __) => save());
});

/// Additional provider for the promotion timestamps map — not previously exposed,
/// now persisted alongside the view store (mirrors `sessionUpdatedAtByAccount`).
final workspaceSessionUpdatedAtProvider = StateProvider<Map<String, Map<String, int>>>((ref) => {});
