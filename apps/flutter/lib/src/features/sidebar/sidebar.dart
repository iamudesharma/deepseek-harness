import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/connection_client.dart';
import '../../core/services/runtime_services.dart';
import '../../core/session/host_session_policy.dart'
    show adoptHostBornSession, isWorkspaceAttachFailure;
import '../../core/session/session_models.dart';
import '../../core/session/sessions_controller.dart';
import '../../core/session/session_provider.dart';
import '../../features/layout/layout_controller.dart';
import '../../features/workspace/workspace_provider.dart';
import '../../plugins/directory_picker/directory_browser.dart';
import '../../plugins/settings/children/general/general_settings_plugin.dart'
    show kSettingsNamespace;
import '../../plugins/workspace/locales.dart'
    show
        kWorkspaceNamespace,
        formatWorkspaceCount,
        formatWorkspaceNamed,
        workspaceCreatedLabel,
        workspaceHoverTimeLabel,
        workspaceTimeLabel;
import '../../theme/app_theme.dart';
import '../../utils/abbreviate_home_path.dart';
import '../../utils/workspace_labels.dart';
import '../../widgets/primitives/hover_card.dart';
import '../../widgets/primitives/state_dot.dart';
import '../../platform/clipboard.dart';
import '../../widgets/primitives/ds_input.dart';
import '../../widgets/primitives/ds_tooltip.dart';
import '../../widgets/primitives/icons.dart';
import 'search_derive.dart';
import 'workspace_view_store.dart';
import '../../plugins/directory_picker/directory_picker_plugin.dart'
    show activatedPickDirectory;
import '../../plugins/permission_presets/permission_session_provider.dart';

// Keep simple provider for backward compat.
final sidebarSearchProvider = StateProvider<String>((ref) => '');
final sidebarWorkspaceProvider = StateProvider<WorkspaceId?>((ref) => null);

/// GroupBy mode: workspace sections or one flat recency list.
enum SessionGroupBy { workspace, flat }

/// Session order: user-arranged only or user-arranged plus activity promotion.
enum SessionOrderBy { manual, updated }

final workspaceGroupByProvider = StateProvider<SessionGroupBy>(
  (ref) => SessionGroupBy.workspace,
);
final workspaceOrderByProvider = StateProvider<SessionOrderBy>(
  (ref) => SessionOrderBy.updated,
);
final workspaceExpandedProvider = StateProvider<Map<String, bool>>((ref) => {});
final workspaceSessionOrderProvider = StateProvider<Map<String, List<String>>>(
  (ref) => {},
);

/// All session summaries filtered by search query and workspace.
/// Mirrors web Sidebar search + workspace scoping.
final filteredSessionsProvider = Provider<List<SessionSummary>>((ref) {
  final String query = ref.watch(sidebarSearchProvider).trim().toLowerCase();
  final List<SessionSummary> sorted = ref.watch(sortedSessionsProvider);
  Iterable<SessionSummary> filtered = sorted;
  if (query.isNotEmpty) {
    filtered = filtered.where((s) {
      final String title = (s.title ?? '').toLowerCase();
      final String id = s.sessionId.value.toLowerCase();
      final String? cwd = s.cwd?.toLowerCase();
      return title.contains(query) ||
          id.contains(query) ||
          (cwd?.contains(query) ?? false);
    });
  }
  return filtered.toList(growable: false);
});

// Debounced search: sanitizes NUL and caps at 500 code units, 250ms debounce.
final debouncedSidebarQueryProvider = StateProvider<String>((ref) => '');
const String _kUngroupedKey = '';
const int _kCollapsedSessionLimit = 5;

String _sanitizeSearchQuery(String value) {
  final withoutNul = value.replaceAll('\u0000', '');
  if (withoutNul.length <= 500) return withoutNul;
  var end = 500;
  final last = withoutNul.codeUnitAt(end - 1);
  final next = withoutNul.codeUnitAt(end);
  if (last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF)
    end--;
  return withoutNul.substring(0, end);
}

Future<void> _handleNewSession(WidgetRef ref, BuildContext context) async {
  final scaffold = ScaffoldMessenger.of(context);
  try {
    final client = ref.read(connectionClientProvider);
    SessionId newId;
    try {
      newId = await client.createSession();
    } catch (e) {
      if (isWorkspaceAttachFailure(e)) {
        newId = await client.createSession();
      } else {
        rethrow;
      }
    }
    // Seed the permission projection immediately so the composer chip never
    // flickers hidden on a blank session — the history tail already carries
    // `permissions` at creation (host_session_policy + live_sync's
    // SessionProjectionFrame both do this, but the new-session navigation races
    // the mux push; a direct history pull guarantees the seat is visible on
    // first frame, mirroring the active-session posture).
    try {
      final res = await client.getSessionHistory(newId);
      final perm = res.projections?.values['permissions'];
      if (perm is Map) {
        ref.read(permissionSelectProvider(newId.value).notifier).state =
            PermissionSelect.fromJson(perm.cast<String, dynamic>());
      }
    } catch (_) {
      // Live SessionProjectionFrame remains the authority; a failed re-pull
      // keeps the seat hidden until the push lands (the pre-existing posture).
    }
    // Project the host-born session before the confirming list pull lands
    // (host_session_policy.dart): the returned id is immediately addressable.
    ref.read(sessionsProvider.notifier).addSession(adoptHostBornSession(newId));
    final sessions = await client.getSessions();
    ref.read(sessionsProvider.notifier).setAll(sessions);
    ref.read(sessionsProvider.notifier).setCurrent(newId);
    if (context.mounted) context.go('/sessions/${newId.value}');
  } catch (e) {
    if (context.mounted) {
      scaffold.showSnackBar(
        SnackBar(content: Text('Failed to create session: $e')),
      );
    }
  }
}

enum SessionGroup { today, yesterday, lastWeek, older }

/// Group-header copy for the recency buckets — `workspace` namespace keys
/// added for this Flutter surface (React renders recency through the
/// `time.*` hover keys instead).
String sessionGroupLabel(SessionGroup group, Translate t) => switch (group) {
  SessionGroup.today => t('group.today'),
  SessionGroup.yesterday => t('group.yesterday'),
  SessionGroup.lastWeek => t('group.lastWeek'),
  SessionGroup.older => t('group.older'),
};

SessionGroup groupForSession(SessionSummary session, DateTime now) {
  final DateTime updated = DateTime.fromMillisecondsSinceEpoch(
    session.updatedAt,
  );
  final DateTime todayStart = DateTime(now.year, now.month, now.day);
  final DateTime yesterdayStart = todayStart.subtract(const Duration(days: 1));
  final DateTime weekStart = todayStart.subtract(const Duration(days: 7));
  if (!updated.isBefore(todayStart)) return SessionGroup.today;
  if (!updated.isBefore(yesterdayStart)) return SessionGroup.yesterday;
  if (!updated.isBefore(weekStart)) return SessionGroup.lastWeek;
  return SessionGroup.older;
}

Map<SessionGroup, List<SessionSummary>> groupSessions(
  List<SessionSummary> sessions, {
  DateTime? now,
}) {
  final DateTime refNow = now ?? DateTime.now();
  final Map<SessionGroup, List<SessionSummary>> out = {
    SessionGroup.today: [],
    SessionGroup.yesterday: [],
    SessionGroup.lastWeek: [],
    SessionGroup.older: [],
  };
  for (final s in sessions) {
    final g = groupForSession(s, refNow);
    out[g]!.add(s);
  }
  out.removeWhere((_, v) => v.isEmpty);
  return out;
}

/// Workspace-grouped derivation — React `deriveGroups` analog.
class WorkspaceGroup {
  const WorkspaceGroup({
    required this.key,
    required this.workspaceId,
    required this.label,
    required this.cwd,
    required this.createdAt,
    required this.sessionCount,
    required this.expanded,
    required this.containsCurrent,
    required this.sessions,
  });
  final String key;
  final WorkspaceId? workspaceId;
  final String label;
  final String? cwd;
  final int? createdAt;
  final int sessionCount;
  final bool expanded;
  final bool containsCurrent;
  final List<SessionSummary> sessions;
}

List<WorkspaceGroup> deriveWorkspaceGroups(
  List<SessionSummary> sessions,
  List<WorkspaceView> workspaces,
  SessionId? current,
  Set<String> expandedKeys,
  String query, {
  String ungroupedLabel = 'Ungrouped',
}) {
  final filtered = query.isEmpty
      ? sessions
      : sessions.where((s) {
          final title = (s.title ?? '').toLowerCase();
          final id = s.sessionId.value.toLowerCase();
          final cwd = (s.cwd ?? '').toLowerCase();
          final q = query.toLowerCase();
          return title.contains(q) || id.contains(q) || cwd.contains(q);
        }).toList();
  final byId = {for (final s in filtered) s.sessionId: s};
  final accounted = <SessionId>{};
  // Precompute session-to-workspace ownership for current key and grouping.
  final bool hasSessionIdsLocal = workspaces.any(
    (w) => w.sessionIds.isNotEmpty,
  );
  final Map<SessionId, String> ownerForKey = {};
  if (hasSessionIdsLocal) {
    for (final w in workspaces) {
      for (final sid in w.sessionIds) {
        ownerForKey.putIfAbsent(sid, () => w.workspaceId.value);
      }
    }
  }
  final String? currentKey = current == null
      ? null
      : (() {
          final key = ownerForKey[current];
          if (key != null) return key;
          final cur = byId[current];
          if (cur?.cwd != null) {
            for (final w in workspaces) {
              final cwd = w.cwd;
              if (cwd != null && cur!.cwd!.startsWith(cwd))
                return w.workspaceId.value;
            }
          }
          return _kUngroupedKey;
        })();
  // Determine mapping: prefer host-provided sessionIds membership (workspace.list), fallback to cwd prefix.
  Map<String, List<SessionSummary>> byWorkspace = {};
  final List<SessionSummary> ungrouped = [];
  if (hasSessionIdsLocal) {
    for (final s in filtered) {
      if (s.origin == 'subagent') continue;
      if (s.blank && s.sessionId != current) continue;
      final ownerKey = ownerForKey[s.sessionId];
      if (ownerKey != null) {
        accounted.add(s.sessionId);
        byWorkspace.putIfAbsent(ownerKey, () => []).add(s);
      } else {
        ungrouped.add(s);
      }
    }
  } else {
    for (final s in filtered) {
      if (s.origin == 'subagent') continue;
      if (s.blank && s.sessionId != current) continue;
      WorkspaceView? matched;
      for (final w in workspaces) {
        if (w.cwd != null &&
            s.cwd != null &&
            (s.cwd == w.cwd || s.cwd!.startsWith('${w.cwd}/'))) {
          matched = w;
          break;
        }
      }
      if (matched != null) {
        accounted.add(s.sessionId);
        byWorkspace.putIfAbsent(matched.workspaceId.value, () => []).add(s);
      } else {
        ungrouped.add(s);
      }
    }
  }
  // If no cwd match but synthetic workspaces (default/project-a) used, distribute round-robin for visual grouping.
  // Fallback: if ungrouped == all and workspaces non-empty, keep ungrouped as separate bucket.
  final List<WorkspaceGroup> groups = [];
  for (final w in workspaces) {
    final list = byWorkspace[w.workspaceId.value] ?? [];
    // Sort by updatedAt descending (like host session.list order).
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final key = w.workspaceId.value;
    final expanded = expandedKeys.contains(key);
    groups.add(
      WorkspaceGroup(
        key: key,
        workspaceId: w.workspaceId,
        label: w.name,
        cwd: w.cwd,
        createdAt: w.createdAt,
        sessionCount: list.length,
        expanded: expanded || expandedKeys.isEmpty && groups.isEmpty,
        containsCurrent: currentKey == key,
        sessions: expanded || expandedKeys.contains(key) || expandedKeys.isEmpty
            ? list
            : [],
      ),
    );
  }
  // For truly ungrouped, push after real workspaces if any remain.
  if (ungrouped.isNotEmpty) {
    ungrouped.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final expanded =
        expandedKeys.contains(_kUngroupedKey) || expandedKeys.isEmpty;
    groups.add(
      WorkspaceGroup(
        key: _kUngroupedKey,
        workspaceId: null,
        label: ungroupedLabel,
        cwd: null,
        createdAt: null,
        sessionCount: ungrouped.length,
        expanded: expanded,
        containsCurrent: currentKey == _kUngroupedKey,
        sessions: expanded ? ungrouped : [],
      ),
    );
  }
  // If collapsed group, show only first N but caller caps.
  return groups;
}

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key, this.collapsed, this.onNewSession});
  final bool? collapsed;
  final VoidCallback? onNewSession;
  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  bool _settled = true;
  bool _everWide = true;
  bool _pointerInside = false;
  Timer? _lingerTimer;
  Timer? _settleTimer;
  bool? _prevCollapsed;

  static const Duration _collapseSettle = Duration(milliseconds: 150);
  static const Duration _linger = Duration(milliseconds: 2000);

  @override
  void dispose() {
    _lingerTimer?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }

  void _armLinger() {
    if (_lingerTimer != null) return;
    _lingerTimer = Timer(_linger, () {
      _lingerTimer = null;
      if (mounted) setState(() => _pointerInside = false);
    });
  }

  void _cancelLinger() {
    _lingerTimer?.cancel();
    _lingerTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(workspaceViewPersistenceProvider);
    final bool isCollapsed =
        widget.collapsed ??
        ref.watch(layoutProvider.select((s) => s.sidebarCollapsed));
    // Settle handling mirrors SidebarRoot.tsx: wide stays mounted while collapse animates (150ms fade).
    if (_prevCollapsed != isCollapsed) {
      if (!isCollapsed) {
        _settleTimer?.cancel();
        _settled = false;
        _everWide = true;
        _cancelLinger();
      } else {
        // Collapse -> start fade-out; settle after 150ms
        _settleTimer?.cancel();
        _settleTimer = Timer(_collapseSettle, () {
          _settleTimer = null;
          if (mounted && _prevCollapsed == true)
            setState(() => _settled = true);
        });
      }
      _prevCollapsed = isCollapsed;
      if (!isCollapsed) _everWide = true;
    }
    // Ensure everWide tracks first wide mount
    if (!isCollapsed) _everWide = true;
    final bool wide = !isCollapsed || !_settled;
    final bool showRail = !wide && _everWide;
    final bool reduced =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // Pointer tracking for scrollbar linger — mirrors SidebarRoot.tsx pointerInside + linger
    Widget content;
    if (wide) {
      // Wide (expanded or fading) — ExpandedSidebar with fading opacity when collapsing
      final bool fading = isCollapsed && !_settled;
      final Widget expanded = _ExpandedSidebar(
        aliases: aliases,
        onNewSession: widget.onNewSession,
      );
      content = fading && !reduced
          ? AnimatedOpacity(
              opacity: 0,
              duration: _collapseSettle,
              child: IgnorePointer(ignoring: true, child: expanded),
            )
          : AnimatedOpacity(
              opacity: 1,
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              child: expanded,
            );
    } else {
      // Settled collapsed rail
      final Widget rail = _CollapsedRail(
        aliases: aliases,
        onNewSession: widget.onNewSession,
      );
      content = showRail && !reduced
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 49, end: 0),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              builder: (context, dx, child) => Transform.translate(
                offset: Offset(dx, 0),
                child: Opacity(
                  opacity: 1 - (dx / 49).clamp(0, 1),
                  child: child,
                ),
              ),
              child: rail,
            )
          : rail;
    }

    final ThemeData columnTheme = _pointerInside
        ? theme
        : theme.copyWith(
            scrollbarTheme: theme.scrollbarTheme.copyWith(
              thumbColor: const WidgetStatePropertyAll(DswTokens.transparent),
              trackColor: const WidgetStatePropertyAll(DswTokens.transparent),
            ),
          );

    return MouseRegion(
      onEnter: (_) {
        _cancelLinger();
        setState(() => _pointerInside = true);
      },
      onExit: (_) => _armLinger(),
      child: Theme(
        data: columnTheme,
        child: Material(color: aliases.specificSidebarFill, child: content),
      ),
    );
  }
}

class _CollapsedRail extends ConsumerWidget {
  const _CollapsedRail({required this.aliases, this.onNewSession});
  final DswAliases aliases;
  final VoidCallback? onNewSession;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    final Translate t = tw;
    final Translate tc = ref.bindLocale(kCommonNamespace);
    final SessionsState sessions = ref.watch(sessionsProvider);
    final SessionId? current = sessions.current;
    final List<SessionSummary> sorted = ref.watch(filteredSessionsProvider);
    return Material(
      color: aliases.specificSidebarFill,
      child: NavigationRail(
        backgroundColor: aliases.specificSidebarFill,
        selectedIndex: current == null
            ? null
            : _indexForCurrent(sorted, current),
        onDestinationSelected: (int index) {
          if (index < 0 || index >= sorted.length) return;
          final target = sorted[index].sessionId;
          ref.read(sessionsProvider.notifier).setCurrent(target);
          context.go('/sessions/${target.value}');
        },
        labelType: NavigationRailLabelType.none,
        useIndicator: true,
        indicatorColor: aliases.specificSidebarNavItemActive,
        leading: Column(
          children: [
            const SizedBox(height: DswTokens.spaceSm),
            // Rail controls carry DsTooltip plates only — SidebarRoot.tsx:159/178
            // wraps the toggle + New Session rail buttons in Tooltip (delayMs 500)
            // while the expanded sidebar keeps plain labeled controls.
            DsTooltip(
              message: t('session.new'),
              side: DsTooltipSide.right,
              waitDuration: const Duration(milliseconds: 500),
              child: IconButton(
                icon: DsIcons.plus(size: 24, color: aliases.labelPrimary),
                style: IconButton.styleFrom(
                  backgroundColor: aliases.buttonPrimaryFill,
                  foregroundColor: aliases.labelPrimaryForeground,
                ),
                onPressed:
                    onNewSession ?? () => _handleNewSession(ref, context),
              ),
            ),
            const SizedBox(height: DswTokens.spaceSm),
            Divider(color: aliases.borderL2, height: 1),
            // Rail region controls — React WorkspaceBrowser rail icons (search / add workspace) on shared rail path.
            const SizedBox(height: DswTokens.spaceSm),
            DsTooltip(
              message: tw('search.sessions.aria'),
              side: DsTooltipSide.right,
              waitDuration: const Duration(milliseconds: 500),
              child: IconButton(
                icon: DsIcons.search(size: 18, color: aliases.labelTertiary),
                onPressed: () =>
                    ref.read(layoutProvider.notifier).toggleSidebar(),
              ),
            ),
            DsTooltip(
              message: tw('workspace.add'),
              side: DsTooltipSide.right,
              waitDuration: const Duration(milliseconds: 500),
              child: IconButton(
                icon: Icon(
                  Icons.create_new_folder_outlined,
                  size: 18,
                  color: aliases.labelTertiary,
                ),
                onPressed: () async {
                  ref.read(layoutProvider.notifier).toggleSidebar();
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (!context.mounted) return;
                  String? path;
                  if (kIsWeb) {
                    final client = ref.read(connectionClientProvider);
                    final svc = WorkspacesService(client);
                    Future<DirectoryListing> list({
                      String? path,
                      DirectoryListSignal? signal,
                    }) async {
                      final map = await svc.listDirectory(
                        path: path,
                        signal: signal,
                      );
                      return DirectoryListing.fromJson(
                        map.cast<String, dynamic>(),
                      );
                    }

                    Future<String> create({
                      required String path,
                      required String name,
                    }) => svc.createDirectory(path: path, name: name);
                    if (!context.mounted) return;
                    path = await showDialog<String>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => DirectoryBrowser(
                        open: true,
                        listDirectory: list,
                        createDirectory: create,
                        onOpen: (p) => Navigator.pop(ctx, p),
                        onClose: () => Navigator.pop(ctx),
                      ),
                    );
                  } else {
                    final picker = activatedPickDirectory;
                    path = await picker?.pick();
                  }
                  if (path == null || path.isEmpty) return;
                  final client = ref.read(connectionClientProvider);
                  try {
                    await client.workspaceCreate(path: path);
                    ref.invalidate(workspaceListProvider);
                  } catch (e) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to create workspace: $e'),
                        ),
                      );
                  }
                },
              ),
            ),
          ],
        ),
        trailing: Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: DswTokens.spaceLg),
              child: DsTooltip(
                message: t('toggle.open'),
                side: DsTooltipSide.right,
                waitDuration: const Duration(milliseconds: 500),
                child: IconButton(
                  icon: DsIcons.chevronRight(
                    size: 24,
                    color: aliases.labelTertiary,
                  ),
                  onPressed: () =>
                      ref.read(layoutProvider.notifier).toggleSidebar(),
                ),
              ),
            ),
          ),
        ),
        destinations: [
          for (final s in sorted.take(6))
            NavigationRailDestination(
              icon: Icon(
                s.running ? Icons.circle : Icons.chat_bubble_outline,
                size: 18,
                color: s.running
                    ? aliases.stateSuccessPrimary
                    : aliases.labelTertiary,
              ),
              selectedIcon: Icon(
                Icons.chat_bubble,
                size: 18,
                color: aliases.labelPrimary,
              ),
              label: Text(s.title ?? s.sessionId.value),
            ),
          if (sorted.length > 6)
            NavigationRailDestination(
              icon: Badge(
                label: Text('${sorted.length - 6}'),
                child: Icon(Icons.more_horiz, color: aliases.labelTertiary),
              ),
              label: Text(tc('more')),
            ),
        ],
      ),
    );
  }

  int? _indexForCurrent(List<SessionSummary> sorted, SessionId current) {
    final idx = sorted.indexWhere((s) => s.sessionId == current);
    if (idx == -1) return null;
    if (idx >= 6) return null;
    return idx;
  }
}

class _ExpandedSidebar extends ConsumerStatefulWidget {
  const _ExpandedSidebar({required this.aliases, this.onNewSession});
  final DswAliases aliases;
  final VoidCallback? onNewSession;
  @override
  ConsumerState<_ExpandedSidebar> createState() => _ExpandedSidebarState();
}

class _ExpandedSidebarState extends ConsumerState<_ExpandedSidebar> {
  late final TextEditingController _searchController;
  Timer? _debounce;
  String _localQuery = '';
  // Remote search state — mirrors WorkspaceBrowser RemoteSearchState (query/status/items/hasMore)
  String _remoteQuery = '';
  List<SessionSearchItem> _remoteItems = const [];
  bool _remoteHasMore = false;
  String _remoteStatus = 'idle'; // idle|loading|ready|error
  Timer? _searchDebounce;
  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(sidebarSearchProvider),
    );
    _localQuery = _searchController.text;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    final sanitized = _sanitizeSearchQuery(v);
    ref.read(sidebarSearchProvider.notifier).state = sanitized;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _localQuery = sanitized.trim());
    });
    // Host search debounce — mirrors WorkspaceBrowser SEARCH_DEBOUNCE_MS = 250
    final normalized = sanitized.trim();
    _searchDebounce?.cancel();
    if (normalized.isEmpty) {
      setState(() {
        _remoteQuery = '';
        _remoteItems = const [];
        _remoteHasMore = false;
        _remoteStatus = 'idle';
      });
      return;
    }
    setState(() {
      _remoteQuery = normalized;
      _remoteStatus = 'loading';
      _remoteItems = const [];
      _remoteHasMore = false;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      try {
        final client = ref.read(connectionClientProvider);
        final result = await client.sessionSearch(query: normalized);
        if (!mounted || _remoteQuery != normalized) return;
        final itemsRaw = result['items'] as List<dynamic>? ?? const [];
        final items = itemsRaw.whereType<Map>().map((e) {
          final m = e.cast<String, dynamic>();
          final sid = m['sessionId'] as String? ?? '';
          final snippet = m['snippet'] as String? ?? '';
          return SessionSearchItem(sessionId: SessionId(sid), snippet: snippet);
        }).toList();
        final hasMore = result['hasMore'] as bool? ?? false;
        setState(() {
          _remoteItems = items;
          _remoteHasMore = hasMore;
          _remoteStatus = 'ready';
        });
      } catch (_) {
        if (!mounted || _remoteQuery != normalized) return;
        setState(() {
          _remoteItems = const [];
          _remoteHasMore = false;
          _remoteStatus = 'error';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Activate durable view persistence (dsh.workspace.view.v5 via SharedPreferences)
    ref.watch(workspaceViewPersistenceProvider);
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    final Translate t = tw;
    final Translate tc = ref.bindLocale(kCommonNamespace);
    final Translate ts = ref.bindLocale(kSettingsNamespace);
    final DswAliases aliases = widget.aliases;
    final List<SessionSummary> filtered = ref.watch(filteredSessionsProvider);
    final SessionsState sessions = ref.watch(sessionsProvider);
    final SessionId? current = sessions.current;
    final groupBy = ref.watch(workspaceGroupByProvider);
    final orderBy = ref.watch(workspaceOrderByProvider);
    final expandedMap = ref.watch(workspaceExpandedProvider);
    final expandedKeys = expandedMap.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();
    // If no explicit expansion, expand first group by default.
    final workspacesAsync = ref.watch(workspaceListProvider);
    final List<WorkspaceView> workspaces =
        workspacesAsync.valueOrNull ?? const <WorkspaceView>[];
    // Flat list mode: show all sessions as one draggable list.
    final isSearching = _localQuery.isNotEmpty;
    // Derive ranked host search results when searching — mirrors tree.ts deriveSearchResults
    final List<SessionSummary> sortedForSearch = ref.watch(
      sortedSessionsProvider,
    );
    final List<SessionSearchItem> remoteForDerive = _remoteStatus == 'ready'
        ? _remoteItems
        : const <SessionSearchItem>[];
    final SearchResultSet? searchDerived = isSearching
        ? deriveSearchResults(
            sortedForSearch,
            workspaces,
            _localQuery,
            remoteForDerive,
            _remoteHasMore,
            20,
            <SessionId>{},
          )
        : null;
    final bool searchPending = _remoteStatus == 'loading';
    final bool searchError = _remoteStatus == 'error';
    // Header switch: section label shows sessions vs workspaces based on groupBy.
    final String sectionLabel = groupBy == SessionGroupBy.flat
        ? tw('section.sessions')
        : tw('section.workspaces');
    return Material(
      color: aliases.specificSidebarFill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: section label + searching slot + view options + add workspace.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DswTokens.spaceLg,
              DswTokens.spaceMd,
              DswTokens.spaceSm,
              DswTokens.spaceSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    sectionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      fontWeight: FontWeight.w600,
                      color: aliases.labelCaption,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                // View options menu — React ViewOptionsMenu: groupBy workspace/flat + orderBy manual/updated.
                PopupMenuButton<String>(
                  tooltip: tw('viewOptions.label'),
                  icon: Icon(
                    Icons.tune,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                  color: aliases.specificMenu,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 16,
                  onSelected: (value) {
                    if (value == 'workspace' || value == 'flat') {
                      ref
                          .read(workspaceGroupByProvider.notifier)
                          .state = value == 'workspace'
                          ? SessionGroupBy.workspace
                          : SessionGroupBy.flat;
                    } else if (value == 'manual' || value == 'updated') {
                      ref
                          .read(workspaceOrderByProvider.notifier)
                          .state = value == 'manual'
                          ? SessionOrderBy.manual
                          : SessionOrderBy.updated;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Text(
                        tw('groupBy.label'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelCaption,
                        ),
                      ),
                    ),
                    CheckedPopupMenuItem<String>(
                      value: 'workspace',
                      checked: groupBy == SessionGroupBy.workspace,
                      child: Text(tw('groupBy.workspace')),
                    ),
                    CheckedPopupMenuItem<String>(
                      value: 'flat',
                      checked: groupBy == SessionGroupBy.flat,
                      child: Text(tw('groupBy.flat')),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Text(
                        tw('orderBy.label'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelCaption,
                        ),
                      ),
                    ),
                    CheckedPopupMenuItem<String>(
                      value: 'manual',
                      checked: orderBy == SessionOrderBy.manual,
                      child: Text(tw('orderBy.manual')),
                    ),
                    CheckedPopupMenuItem<String>(
                      value: 'updated',
                      checked: orderBy == SessionOrderBy.updated,
                      child: Text(tw('orderBy.updated')),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: tw('workspace.add'),
                  icon: Icon(
                    Icons.create_new_folder_outlined,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: aliases.bgOverlay,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    String? path;
                    if (kIsWeb) {
                      final client = ref.read(connectionClientProvider);
                      final svc = WorkspacesService(client);
                      Future<DirectoryListing> list({
                        String? path,
                        DirectoryListSignal? signal,
                      }) async {
                        final map = await svc.listDirectory(
                          path: path,
                          signal: signal,
                        );
                        return DirectoryListing.fromJson(
                          map.cast<String, dynamic>(),
                        );
                      }

                      Future<String> create({
                        required String path,
                        required String name,
                      }) => svc.createDirectory(path: path, name: name);
                      path = await showDialog<String>(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => DirectoryBrowser(
                          open: true,
                          listDirectory: list,
                          createDirectory: create,
                          onOpen: (p) => Navigator.pop(ctx, p),
                          onClose: () => Navigator.pop(ctx),
                        ),
                      );
                    } else {
                      final picker = activatedPickDirectory;
                      if (picker == null) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Directory picker unavailable'),
                          ),
                        );
                        return;
                      }
                      path = await picker.pick();
                    }
                    if (path == null || path.isEmpty) return;
                    final client = ref.read(connectionClientProvider);
                    try {
                      await client.workspaceCreate(path: path);
                      ref.invalidate(workspaceListProvider);
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Workspace "$path" created')),
                        );
                    } catch (e) {
                      if (!context.mounted) return;
                      final shouldRetry = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(tw('folderError.title')),
                          content: Text('$e'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(tc('cancel')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(tw('folderError.retry')),
                            ),
                          ],
                        ),
                      );
                      if (shouldRetry == true && context.mounted) {
                        String? retryPath;
                        if (kIsWeb) {
                          final client2 = ref.read(connectionClientProvider);
                          final svc2 = WorkspacesService(client2);
                          Future<DirectoryListing> list2({
                            String? path,
                            DirectoryListSignal? signal,
                          }) async {
                            final map = await svc2.listDirectory(
                              path: path,
                              signal: signal,
                            );
                            return DirectoryListing.fromJson(
                              map.cast<String, dynamic>(),
                            );
                          }

                          Future<String> create2({
                            required String path,
                            required String name,
                          }) => svc2.createDirectory(path: path, name: name);
                          retryPath = await showDialog<String>(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => DirectoryBrowser(
                              open: true,
                              listDirectory: list2,
                              createDirectory: create2,
                              onOpen: (p) => Navigator.pop(ctx, p),
                              onClose: () => Navigator.pop(ctx),
                            ),
                          );
                        } else {
                          final picker = activatedPickDirectory;
                          retryPath = await picker?.pick();
                        }
                        if (retryPath != null && retryPath.isNotEmpty) {
                          try {
                            await client.workspaceCreate(path: retryPath);
                            ref.invalidate(workspaceListProvider);
                          } catch (e2) {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed: $e2')),
                              );
                          }
                        }
                      }
                    }
                  },
                ),
                IconButton(
                  tooltip: t('toggle.collapse'),
                  icon: Icon(
                    Icons.chevron_left,
                    size: 18,
                    color: aliases.labelTertiary,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      ref.read(layoutProvider.notifier).toggleSidebar(),
                ),
              ],
            ),
          ),
          // New session button.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceLg),
            child: SizedBox(
              height: 36,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: aliases.buttonPrimaryFill,
                  foregroundColor: aliases.labelPrimaryForeground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                  ),
                ),
                onPressed:
                    widget.onNewSession ??
                    () => _handleNewSession(ref, context),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  t('session.new.label'),
                  style: const TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: DswTokens.spaceMd),
          // Search — React: click expands, sanitize, debounce, host search.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceLg),
            child: DsSearchInput(
              hintText: tw('search.placeholder'),
              icon: Icon(Icons.search, size: 16, color: aliases.labelTertiary),
              controller: _searchController,
              onChanged: _onSearchChanged,
            ),
          ),
          if (isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DswTokens.spaceLg,
                vertical: DswTokens.spaceSm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: aliases.labelCaption,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Showing matches for "$_localQuery" · ${_localQuery.isEmpty ? 0 : filtered.length} results',
                      style: TextStyle(
                        fontSize: 11,
                        color: aliases.labelCaption,
                      ),
                    ),
                  ),
                  if (_localQuery.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      child: Text(
                        tw('search.clear'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: DswTokens.spaceSm),
          Divider(height: 1, color: aliases.borderL2),
          // Session list: workspace-grouped tree vs flat list vs empty.
          Expanded(
            child: isSearching
                ? (searchDerived == null ||
                          (searchDerived.items.isEmpty && !searchPending)
                      ? _EmptyState(aliases: aliases, hasQuery: true)
                      : _SearchResultsView(
                          derived: searchDerived!,
                          current: current,
                          aliases: aliases,
                          pending: searchPending,
                          error: searchError,
                          onOpen: (id) {
                            ref.read(sessionsProvider.notifier).setCurrent(id);
                            // ignore: use_build_context_synchronously
                            context.go('/sessions/${id.value}');
                          },
                        ))
                : filtered.isEmpty
                ? _EmptyState(aliases: aliases, hasQuery: false)
                : groupBy == SessionGroupBy.flat
                ? _FlatList(
                    sessions: filtered,
                    current: current,
                    aliases: aliases,
                    query: _localQuery,
                    orderBy: orderBy,
                  )
                : _WorkspaceTree(
                    sessions: filtered,
                    workspaces: workspaces,
                    current: current,
                    aliases: aliases,
                    query: _localQuery,
                    expandedKeys: expandedKeys,
                    orderBy: orderBy,
                    onToggle: (key) {
                      final map = Map<String, bool>.from(
                        ref.read(workspaceExpandedProvider),
                      );
                      map[key] = !(map[key] ?? false);
                      ref.read(workspaceExpandedProvider.notifier).state = map;
                    },
                    onCreateIn: (wsId) async {
                      final client = ref.read(connectionClientProvider);
                      try {
                        final newId = await client.createSession(
                          workspaceId: wsId.value,
                        );
                        try {
                          final res = await client.getSessionHistory(newId);
                          final perm = res.projections?.values['permissions'];
                          if (perm is Map) {
                            ref
                                .read(
                                  permissionSelectProvider(newId.value)
                                      .notifier,
                                )
                                .state = PermissionSelect.fromJson(
                              perm.cast<String, dynamic>(),
                            );
                          }
                        } catch (_) {}
                        // Project the host-born session before the confirming
                        // list pull lands (host_session_policy.dart).
                        ref
                            .read(sessionsProvider.notifier)
                            .addSession(adoptHostBornSession(newId));
                        final all = await client.getSessions();
                        ref.read(sessionsProvider.notifier).setAll(all);
                        ref.read(sessionsProvider.notifier).setCurrent(newId);
                        if (context.mounted)
                          context.go('/sessions/${newId.value}');
                      } catch (e) {
                        if (context.mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                      }
                    },
                  ),
          ),
          Divider(height: 1, color: aliases.borderL2),
          Padding(
            padding: const EdgeInsets.all(DswTokens.spaceSm),
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: aliases.labelTertiary,
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Text(
                    formatWorkspaceCount(
                      tw(
                        filtered.length == 1
                            ? 'sessions.count.one'
                            : 'sessions.count.other',
                      ),
                      filtered.length,
                    ),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelCaption,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Devices',
                  icon: Icon(
                    Icons.devices_outlined,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                  onPressed: () => context.push('/devices'),
                ),
                TextButton(
                  onPressed: () => context.go('/settings'),
                  child: Text(
                    ts('trigger'),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat list — newest-first, draggable sessions (Reorderable stub).
class _FlatList extends ConsumerWidget {
  const _FlatList({
    required this.sessions,
    required this.current,
    required this.aliases,
    required this.query,
    required this.orderBy,
  });
  final List<SessionSummary> sessions;
  final SessionId? current;
  final DswAliases aliases;
  final String query;
  final SessionOrderBy orderBy;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty)
      return _EmptyState(aliases: aliases, hasQuery: query.isNotEmpty);
    List<SessionSummary> rows = List.of(sessions);
    // orderBy updated: sort by recency; manual keeps input order (already recency but stable).
    if (orderBy == SessionOrderBy.updated) {
      rows.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: DswTokens.spaceSm),
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      onReorder: (oldIndex, newIndex) {
        // Local reorder only — mirrors SessionTree drag that calls insertSessionBefore for real workspaces.
        if (newIndex > oldIndex) newIndex -= 1;
        final moved = rows.removeAt(oldIndex);
        rows.insert(newIndex, moved);
        // Persist to provider for visual feedback.
        final orderMap = Map<String, List<String>>.from(
          ref.read(workspaceSessionOrderProvider),
        );
        orderMap['__flat__'] = rows.map((s) => s.sessionId.value).toList();
        ref.read(workspaceSessionOrderProvider.notifier).state = orderMap;
      },
      itemBuilder: (context, index) {
        final s = rows[index];
        return ReorderableDragStartListener(
          key: ValueKey(s.sessionId.value),
          index: index,
          child: _SessionRow(
            summary: s,
            selected: s.sessionId == current,
            aliases: aliases,
          ),
        );
      },
    );
  }
}

/// Workspace tree — grouped sections, draggable workspaces + sessions.
class _WorkspaceTree extends ConsumerWidget {
  const _WorkspaceTree({
    required this.sessions,
    required this.workspaces,
    required this.current,
    required this.aliases,
    required this.query,
    required this.expandedKeys,
    required this.orderBy,
    required this.onToggle,
    required this.onCreateIn,
  });
  final List<SessionSummary> sessions;
  final List<WorkspaceView> workspaces;
  final SessionId? current;
  final DswAliases aliases;
  final String query;
  final Set<String> expandedKeys;
  final SessionOrderBy orderBy;
  final ValueChanged<String> onToggle;
  final ValueChanged<WorkspaceId> onCreateIn;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    final groups = deriveWorkspaceGroups(
      sessions,
      workspaces,
      current,
      expandedKeys,
      query,
      ungroupedLabel: tw('group.ungrouped'),
    );
    if (groups.isEmpty)
      return _EmptyState(aliases: aliases, hasQuery: query.isNotEmpty);
    // Apply orderBy for sessions within each group when updated: activity promotion handled by recency sort.
    // Manual keeps stored order; for demo we sort by recency when updated.
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: DswTokens.spaceSm),
      buildDefaultDragHandles: false,
      itemCount: groups.length,
      onReorder: (int oldIndex, int newIndex) async {
        if (newIndex > oldIndex) newIndex -= 1;
        final WorkspaceGroup moved = groups[oldIndex];
        if (moved.workspaceId == null) return;
        final String? anchor = newIndex >= groups.length
            ? null
            : groups[newIndex].workspaceId?.value;
        if (anchor == moved.workspaceId!.value) return;
        try {
          await ref
              .read(connectionClientProvider)
              .workspaceInsertBefore(
                workspaceId: moved.workspaceId!.value,
                beforeWorkspaceId: anchor,
              );
          ref.invalidate(workspaceListProvider);
        } catch (e) {
          debugPrint('workspace reorder rejected: $e');
        }
      },
      itemBuilder: (BuildContext context, int index) {
        final g = groups[index];
        return ReorderableDragStartListener(
          key: ValueKey(g.key),
          index: index,
          child: _ProjectSection(
            group: g,
            current: current,
            aliases: aliases,
            query: query,
            orderBy: orderBy,
            onToggle: onToggle,
            onCreateIn: onCreateIn,
          ),
        );
      },
    );
  }
}

class _ProjectSection extends ConsumerWidget {
  const _ProjectSection({
    required this.group,
    required this.current,
    required this.aliases,
    required this.query,
    required this.orderBy,
    required this.onToggle,
    required this.onCreateIn,
  });
  final WorkspaceGroup group;
  final SessionId? current;
  final DswAliases aliases;
  final String query;
  final SessionOrderBy orderBy;
  final ValueChanged<String> onToggle;
  final ValueChanged<WorkspaceId> onCreateIn;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    final Translate tc = ref.bindLocale(kCommonNamespace);
    final sessions = group.sessions;
    final displaySessions = group.expanded
        ? sessions
        : sessions.take(_kCollapsedSessionLimit).toList();
    final overflow = sessions.length - displaySessions.length;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        color: group.containsCurrent
            ? aliases.specificSidebarNavItemActive.withValues(alpha: 0.08)
            : null,
        border: group.containsCurrent
            ? Border.all(
                color: aliases.specificSidebarNavItemActive.withValues(
                  alpha: 0.2,
                ),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Project header row — folder + title + chevron + actions with HoverCard parity (React ProjectRowItem).
          Builder(
            builder: (context) {
              final hostAsync = ref.watch(hostDescribeProvider);
              final String? home = hostAsync.valueOrNull?['home'] as String?;
              final Widget headerRow = InkWell(
                borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                onTap: () => onToggle(group.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DswTokens.spaceSm,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        group.expanded
                            ? Icons.folder_open
                            : Icons.folder_outlined,
                        size: 16,
                        color: group.containsCurrent
                            ? aliases.stateBusinessPrimary
                            : aliases.labelTertiary,
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        group.expanded
                            ? Icons.expand_less
                            : Icons.chevron_right,
                        size: 14,
                        color: aliases.labelTertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          group.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeS14,
                            fontWeight: FontWeight.w500,
                            color: aliases.labelPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: aliases.bgOverlay,
                          borderRadius: BorderRadius.circular(
                            DswTokens.radiusFull,
                          ),
                        ),
                        child: Text(
                          '${group.sessionCount}',
                          style: TextStyle(
                            fontSize: 10,
                            color: aliases.labelTertiary,
                          ),
                        ),
                      ),
                      if (group.workspaceId != null) ...[
                        PopupMenuButton<String>(
                          tooltip: formatWorkspaceNamed(
                            tw('actions.workspace.aria'),
                            group.label,
                          ),
                          icon: Icon(
                            Icons.more_horiz,
                            size: 16,
                            color: aliases.labelTertiary,
                          ),
                          color: aliases.specificMenu,
                          onSelected: (v) async {
                            if (v == 'rename') {
                              final ctrl = TextEditingController(
                                text: group.label,
                              );
                              final newName = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(tw('rename.workspace.title')),
                                  content: TextField(
                                    controller: ctrl,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      labelText: tw('field.workspaceName'),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text(tc('cancel')),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, ctrl.text.trim()),
                                      child: Text(tw('rename')),
                                    ),
                                  ],
                                ),
                              );
                              if (newName != null &&
                                  newName.isNotEmpty &&
                                  newName != group.label &&
                                  context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Rename "$newName" — wiring to workspace.rename pending host support',
                                    ),
                                  ),
                                );
                              }
                            } else if (v == 'delete') {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(tw('delete.workspace')),
                                  content: Text(
                                    formatWorkspaceNamed(
                                      tw('delete.desc'),
                                      group.label,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(tc('cancel')),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(tc('delete')),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Delete — pending host workspace.delete wire',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(tw('rename')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(tc('delete')),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: formatWorkspaceNamed(
                            tw('actions.newSession.aria'),
                            group.label,
                          ),
                          icon: Icon(
                            Icons.add,
                            size: 16,
                            color: aliases.labelSecondary,
                          ),
                          onPressed: () => onCreateIn(group.workspaceId!),
                        ),
                      ],
                    ],
                  ),
                ),
              );
              if (group.createdAt != null)
                return DsHoverCard(
                  trigger: headerRow,
                  content: _WorkspaceHoverContent(
                    label: group.label,
                    cwd: group.cwd,
                    createdAt: group.createdAt,
                    home: home,
                  ),
                  copyText: group.cwd,
                  onCopy: group.cwd == null
                      ? null
                      : () => copyToClipboard(group.cwd!),
                );
              return headerRow;
            },
          ),
          // Session rows — reorderable within group, host-persisted when manual (React SessionTree parity).
          if (displaySessions.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: displaySessions.length,
              onReorder: (int oldIndex, int newIndex) async {
                if (newIndex > oldIndex) newIndex -= 1;
                final SessionSummary moved = displaySessions[oldIndex];
                final List<SessionSummary> newOrder = List<SessionSummary>.from(
                  displaySessions,
                );
                newOrder.removeAt(oldIndex);
                newOrder.insert(newIndex, moved);
                final String anchorKey = group.workspaceId?.value ?? '';
                final orderMap = Map<String, List<String>>.from(
                  ref.read(workspaceSessionOrderProvider),
                );
                orderMap[anchorKey] = newOrder
                    .map((s) => s.sessionId.value)
                    .toList();
                ref.read(workspaceSessionOrderProvider.notifier).state =
                    orderMap;
                if (orderBy == SessionOrderBy.updated ||
                    group.workspaceId == null)
                  return;
                final String? anchor = newIndex >= newOrder.length - 1
                    ? null
                    : newOrder[newIndex + 1].sessionId.value;
                if (anchor == moved.sessionId.value) return;
                try {
                  await ref
                      .read(connectionClientProvider)
                      .workspaceInsertSessionBefore(
                        workspaceId: group.workspaceId!.value,
                        sessionId: moved.sessionId.value,
                        beforeSessionId: anchor,
                      );
                } catch (e) {
                  debugPrint('session reorder rejected: $e');
                }
              },
              itemBuilder: (BuildContext context, int index) {
                final s = displaySessions[index];
                return ReorderableDragStartListener(
                  key: ValueKey(s.sessionId.value),
                  index: index,
                  child: _SessionRow(
                    summary: s,
                    selected: s.sessionId == current,
                    aliases: aliases,
                    isInWorkspace: true,
                  ),
                );
              },
            ),
          if (overflow > 0)
            TextButton(
              onPressed: () => onToggle(group.key),
              child: Text(
                formatWorkspaceCount(tw('sessions.expand'), overflow),
                style: TextStyle(fontSize: 11, color: aliases.labelSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.summary,
    required this.selected,
    required this.aliases,
    this.isInWorkspace = false,
  });
  final SessionSummary summary;
  final bool selected;
  final DswAliases aliases;
  final bool isInWorkspace;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    final Translate tc = ref.bindLocale(kCommonNamespace);
    final String title = summary.blank
        ? tw('session.new')
        : summary.displayTitle;
    final String subtitle = _subtitleFor(summary, tw);
    final List<SessionStatus> statuses = summary.sessionStatuses();
    final SessionStatus primary = statuses.first;
    final bool showDot = primary.state != 'done' || summary.completed;
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceSm,
        vertical: 2,
      ),
      child: Material(
        color: selected
            ? aliases.specificSidebarNavItemActive
            : DswTokens.transparent,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          hoverColor: aliases.specificSidebarNavItemHover,
          onTap: () {
            ref.read(sessionsProvider.notifier).setCurrent(summary.sessionId);
            context.go('/sessions/${summary.sessionId.value}');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceSm,
              vertical: DswTokens.spaceSm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: showDot
                      ? _StatusDot(status: primary, aliases: aliases)
                      : const SizedBox(width: 8, height: 8),
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: aliases.labelPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DswTokens.spaceSm),
                Text(
                  workspaceTimeLabel(
                    summary.updatedAt,
                    DateTime.now().millisecondsSinceEpoch,
                    tw,
                  ),
                  style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                ),
                // Row actions menu — React SessionNodeItem menu: rename/fork/archive.
                PopupMenuButton<String>(
                  tooltip: formatWorkspaceNamed(
                    tw('actions.session.aria'),
                    summary.displayTitle,
                  ),
                  icon: Icon(
                    Icons.more_horiz,
                    size: 14,
                    color: aliases.labelTertiary,
                  ),
                  color: aliases.specificMenu,
                  onSelected: (v) async {
                    final client = ref.read(connectionClientProvider);
                    if (v == 'rename') {
                      final ctrl = TextEditingController(
                        text: summary.displayTitle,
                      );
                      final newTitle = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(tw('rename.session.title')),
                          content: TextField(
                            controller: ctrl,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: tw('field.sessionName'),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(tc('cancel')),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, ctrl.text.trim()),
                              child: Text(tw('rename')),
                            ),
                          ],
                        ),
                      );
                      if (newTitle != null &&
                          newTitle.isNotEmpty &&
                          context.mounted) {
                        try {
                          await client.callMethod('session.rename', {
                            'agentId': summary.sessionId.value,
                            'title': newTitle,
                          });
                          final all = await client.getSessions();
                          ref.read(sessionsProvider.notifier).setAll(all);
                        } catch (e) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Rename failed: $e')),
                            );
                        }
                      }
                    } else if (v == 'fork') {
                      try {
                        final child = await client.callMethod('session.fork', {
                          'agentId': summary.sessionId.value,
                        });
                        final childId =
                            (child['result'] ?? child)['sessionId']
                                as String? ??
                            (child['value'] as String?);
                        if (childId != null) {
                          final all = await client.getSessions();
                          ref.read(sessionsProvider.notifier).setAll(all);
                          final newSid = SessionId(childId);
                          ref
                              .read(sessionsProvider.notifier)
                              .setCurrent(newSid);
                          if (context.mounted) context.go('/sessions/$childId');
                        }
                      } catch (e) {
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Fork failed: $e')),
                          );
                      }
                    } else if (v == 'archive') {
                      try {
                        await client.callMethod('workspace.archiveSession', {
                          'sessionId': summary.sessionId.value,
                        });
                        ref.invalidate(workspaceListProvider);
                      } catch (e) {
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Archive failed: $e')),
                          );
                      }
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(value: 'rename', child: Text(tw('rename'))),
                    PopupMenuItem(value: 'fork', child: Text(tw('menu.fork'))),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(tw('menu.archiveSession')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return DsHoverCard(
      trigger: row,
      content: _SessionHoverContent(summary: summary),
      copyText: summary.blank ? null : summary.displayTitle,
      onCopy: summary.blank
          ? null
          : () => copyToClipboard(summary.displayTitle),
      enabled: true,
    );
  }

  String _subtitleFor(SessionSummary s, Translate tw) {
    if (s.blank) return tw('session.blank');
    if (s.agentPreset != null) return s.agentPreset!;
    if (s.cwd != null) return s.cwd!;
    return s.running ? tw('status.running') : tw('status.idle');
  }
}

class _SearchResultsView extends ConsumerWidget {
  const _SearchResultsView({
    required this.derived,
    required this.current,
    required this.aliases,
    required this.pending,
    required this.error,
    required this.onOpen,
  });
  final SearchResultSet derived;
  final SessionId? current;
  final DswAliases aliases;
  final bool pending;
  final bool error;
  final ValueChanged<SessionId> onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: DswTokens.spaceSm),
            itemCount: derived.items.length,
            itemBuilder: (context, index) {
              final r = derived.items[index];
              final selected = r.id == current;
              final snippet = r.snippet;
              // Find source for statuses
              // We reconstruct a minimal summary for status dot
              final fake = SessionSummary(
                sessionId: r.id,
                updatedAt: 0,
                running: r.running,
                blank: false,
                pendingInteraction: r.pendingInteraction,
                completed: r.completed,
                runningSubagentCount: r.runningSubagentCount,
              );
              final statuses = fake.sessionStatuses();
              final primary = statuses.first;
              final showDot = primary.state != 'done' || fake.completed;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DswTokens.spaceSm,
                  vertical: 2,
                ),
                child: Material(
                  color: selected
                      ? aliases.specificSidebarNavItemActive
                      : DswTokens.transparent,
                  borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                    onTap: () => onOpen(r.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DswTokens.spaceSm,
                        vertical: DswTokens.spaceSm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: showDot
                                ? _StatusDot(status: primary, aliases: aliases)
                                : const SizedBox(width: 8, height: 8),
                          ),
                          const SizedBox(width: DswTokens.spaceSm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: DswTokens.fontSizeS14,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: aliases.labelPrimary,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  r.workspace,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: aliases.labelTertiary,
                                  ),
                                ),
                                if (snippet != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    snippet,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: aliases.labelSecondary,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (pending)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: aliases.labelTertiary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  tw('search.pending'),
                  style: TextStyle(fontSize: 11, color: aliases.labelCaption),
                ),
              ],
            ),
          ),
        if (error)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              tw('search.unavailable'),
              style: TextStyle(fontSize: 11, color: aliases.stateErrorPrimary),
            ),
          ),
        if (derived.hasMore)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              formatWorkspaceCount(tw('search.hasMore'), 20),
              style: TextStyle(fontSize: 11, color: aliases.labelCaption),
            ),
          ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.status,
    required this.aliases,
    this.size = 8,
  });
  final SessionStatus status;
  final DswAliases aliases;
  final double size;
  @override
  Widget build(BuildContext context) {
    // Map StateDotState to Flutter colors — mirrors ui-primitives StateDot.tsx
    final Color color = switch (status.state) {
      'ongoing' => aliases.stateBusinessPrimary,
      'warning' => aliases.stateWarnPrimary,
      'error' => aliases.stateErrorPrimary,
      'done' => aliases.stateSuccessPrimary,
      _ => aliases.labelTertiary,
    };
    final bool showHalo =
        status.state == 'ongoing' || status.state == 'warning';
    if (showHalo) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.6),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.12), width: 2),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Hover header for workspace group — mirrors Rows.tsx WorkspaceHoverContent.
class _WorkspaceHoverContent extends ConsumerWidget {
  const _WorkspaceHoverContent({
    required this.label,
    required this.cwd,
    required this.createdAt,
    required this.home,
  });
  final String label;
  final String? cwd;
  final int? createdAt;
  final String? home;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    final String abbreviated = cwd == null
        ? ''
        : abbreviateHomePath(cwd!, home);
    // Hover-card body colors are the fixed dark-surface values from
    // Rows.module.css (figma 169:16903): #FFFFFF title, #CFD3D6 secondary text,
    // identical in both themes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DswTokens.neutralBluish00,
          ),
        ),
        if (abbreviated.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            abbreviated,
            style: const TextStyle(
              fontSize: 12,
              color: DswTokens.neutralBluish300,
            ),
          ),
        ],
        if (createdAt != null) ...[
          const SizedBox(height: 4),
          Text(
            workspaceCreatedLabel(createdAt!, tw),
            style: const TextStyle(
              fontSize: 12,
              color: DswTokens.neutralBluish300,
            ),
          ),
        ],
      ],
    );
  }
}

/// Hover content for session row — mirrors Rows.tsx SessionHoverContent.
class _SessionHoverContent extends ConsumerWidget {
  const _SessionHoverContent({required this.summary});
  final SessionSummary summary;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    final statuses = summary.sessionStatuses();
    final title = summary.blank ? tw('session.new') : summary.displayTitle;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Same fixed dark-surface contract as _WorkspaceHoverContent; status dots
    // reuse the shared StateDot primitive exactly as Rows.tsx does.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DswTokens.neutralBluish00,
          ),
        ),
        if (!summary.blank) ...[
          const SizedBox(height: 2),
          Text(
            workspaceHoverTimeLabel(summary.updatedAt, now, tw),
            style: const TextStyle(
              fontSize: 12,
              color: DswTokens.neutralBluish300,
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final s in statuses)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                StateDot(state: _stateDotState(s.state)),
                const SizedBox(width: 8),
                Text(
                  s.label,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 20 / 12,
                    color: DswTokens.neutralBluish400,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Maps a [SessionStatus.state] string onto the shared dot's closed union;
/// the backstop mirrors Rows.tsx, where only these four states are produced.
StateDotState _stateDotState(String state) {
  switch (state) {
    case 'warning':
      return StateDotState.warning;
    case 'ongoing':
      return StateDotState.ongoing;
    case 'error':
      return StateDotState.error;
    default:
      return StateDotState.done;
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.aliases, required this.hasQuery});
  final DswAliases aliases;
  final bool hasQuery;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate tw = ref.bindLocale(kWorkspaceNamespace);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.chat_bubble_outline,
              size: 28,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: DswTokens.spaceSm),
            Text(
              hasQuery ? tw('empty.noMatches') : tw('empty.none'),
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                fontWeight: FontWeight.w500,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasQuery ? tw('empty.noMatchesHint') : tw('empty.noneHint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                color: aliases.labelCaption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
