/// Chat view — folds the session's live history window into typed nodes and
/// renders them through the chat-node seam (registry override first, native
/// renderers as the built-in presentation).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_event_map.dart';
import '../../../core/connection/connection_client.dart' hide ConnectionState;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../platform/clipboard.dart';
import '../../../theme/app_theme.dart';
import '../../../features/conversation/message_provider.dart';
import '../../../widgets/primitives/disclosure_row.dart';
import '../../../widgets/primitives/markdown.dart';
import '../../../widgets/primitives/state_dot.dart';
import '../locales.dart';
import '../nodes/conversation_nodes.dart';
import '../nodes/turn_navigator.dart';
import '../hub.dart';
import 'ansi_span.dart';
import '../../tool/ui/keyed_tool_card.dart'
    show ToolNodeAdapter, ToolNodeAdapterWithSubCalls, ToolSubCallAdapter;
import '../../tool/tool_models.dart' show ToolCall, ToolCallStatus, kindForTool;

/// In-memory reader position resilient to transcript width reflow.
class ChatScrollPosition {
  const ChatScrollPosition({
    required this.anchorKey,
    required this.anchorTop,
    required this.scrollTop,
  });
  final String anchorKey;
  final double anchorTop;
  final double scrollTop;
}

class _PagingAnchor {
  const _PagingAnchor({required this.key, required this.top});
  final String key;
  final double top;
}

const double _followThreshold = 24;

/// Per-session scroll memory surviving view switches (in-memory, never persisted).
final Map<String, ChatScrollPosition?> _chatScrollPositions = {};

String _kindKey(ConversationNode node) => switch (node) {
  UserMessageNode() => 'user',
  ContextNode() => 'context',
  SystemPromptNode() => 'system-prompt',
  AssistantNode() => 'assistant-step',
  ToolNode() => 'tool-call',
  TurnErrorNode() => 'turn-error',
  MarkerNode() => 'marker',
  TurnTailNode() => 'turn-tail',
  TurnProcessNode() => 'turn-process',
  ModelRetryNode() => 'model-retry',
  StepGroupNode() => 'step-group',
  CompactionNode() => 'compaction',
  CommandNode() => 'command',
  ManualCompactionNode() => 'manual-compaction',
};

class _ToolSubCallAdapterImpl implements ToolSubCallAdapter {
  _ToolSubCallAdapterImpl(this.sub);
  final ToolSubCall sub;
  @override
  String get subCallId => sub.subCallId;
  @override
  String get name => sub.name;
  @override
  bool get isError => sub.isError;
  @override
  String? get result => sub.result;
  @override
  List<ToolSubCallAdapter> get children =>
      sub.children.map(_ToolSubCallAdapterImpl.new).toList(growable: false);
}

/// Scrollable node list for one session — native Flutter port of React ChatView
/// (scrollport, semantic anchor, bottom-follow, prepend anchoring,
/// streaming tail, view-state).
class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  late final ScrollController _controller;
  bool _atBottom = true;
  double _observedTop = 0;
  _PagingAnchor? _anchor;
  String? _firstKey;
  String? _lastKey;
  String _followSig = '';
  bool _opened = false;
  bool? _lastLoadingOlder;
  List<String> _currentKeys = const [];
  int? _activeTurn;
  List<TurnNavigationItem> _cachedTurnItems = const [];
  // Cached items reference for scroll-based active turn sync.

  // Row keys for anchor measurements.
  final Map<String, GlobalKey> _rowKeys = {};

  GlobalKey _keyFor(String key) => _rowKeys.putIfAbsent(key, () => GlobalKey());

  /// Flow-local top of a row relative to the scrollport (viewport-independent).
  double _flowTop(GlobalKey key) {
    final rowCtx = key.currentContext;
    final scrollCtx = context.findRenderObject() as RenderBox?;
    if (rowCtx == null || scrollCtx == null) return 0;
    final rowBox = rowCtx.findRenderObject() as RenderBox?;
    if (rowBox == null) return 0;
    return rowBox.localToGlobal(Offset.zero).dy -
        scrollCtx.localToGlobal(Offset.zero).dy;
  }

  /// Find the element for a stable anchor key (mirrors React's anchorElement).
  GlobalKey? _anchorKey(String key) {
    final gk = _rowKeys[key];
    if (gk?.currentContext != null) return gk;
    return null;
  }

  /// Select a visible stable node identity, falling back only when layout
  /// has not exposed a visible box yet (mirrors React's pagingAnchor).
  _PagingAnchor? _pagingAnchor() {
    if (!_controller.hasClients || _currentKeys.isEmpty) return null;
    final scrollBox = context.findRenderObject() as RenderBox?;
    if (scrollBox == null) {
      // Fallback to first key proxy
      if (_firstKey != null) {
        final gk = _rowKeys[_firstKey!];
        if (gk != null) return _PagingAnchor(key: _firstKey!, top: _flowTop(gk));
      }
      return null;
    }
    final viewportHeight = _controller.position.viewportDimension;
    // Binary-search-like scan for first visible row using GlobalKeys
    for (final key in _currentKeys) {
      final gk = _rowKeys[key];
      if (gk == null || gk.currentContext == null) continue;
      final rowBox = gk.currentContext!.findRenderObject() as RenderBox?;
      if (rowBox == null) continue;
      final top = _flowTop(gk);
      final bottom = top + rowBox.size.height;
      if (bottom > 0 && top < viewportHeight) {
        return _PagingAnchor(key: key, top: top);
      }
      if (top >= viewportHeight) break;
    }
    // Fallback to first key when no visible box yet (pre-paint)
    if (_firstKey != null) {
      final gk = _rowKeys[_firstKey!];
      if (gk != null) return _PagingAnchor(key: _firstKey!, top: _flowTop(gk));
    }
    return null;
  }

  /// Anchored older page load: capture paging anchor before the prepend.
  void _loadOlderAnchored() {
    if (!_controller.hasClients) {
      ref.read(liveHistoryProvider(widget.sessionId).notifier).loadOlder();
      return;
    }
    final anchor = _pagingAnchor();
    if (anchor != null) {
      _anchor = anchor;
    } else if (_firstKey != null) {
      final gk = _rowKeys[_firstKey!];
      final top = gk != null ? _flowTop(gk) : 0;
      _anchor = _PagingAnchor(key: _firstKey!, top: top.toDouble());
    }
    ref.read(liveHistoryProvider(widget.sessionId).notifier).loadOlder();
  }

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialRestore());
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      // Save under the OLD id: `widget` already points at the new session.
      _saveCurrentFor(oldWidget.sessionId);
      _opened = false;
      _anchor = null;
      _firstKey = null;
      _lastKey = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _initialRestore());
    }
  }

  @override
  void dispose() {
    _saveCurrentFor(widget.sessionId);
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _saveCurrentFor(String sessionId) {
    if (!_controller.hasClients) return;
    final pos = _controller.position.pixels;
    final isAtBottom =
        _controller.position.maxScrollExtent - pos <= _followThreshold + 1;
    if (isAtBottom) {
      _chatScrollPositions[sessionId] = null;
    } else {
      // Use last anchor or lastKey as fallback.
      final anchorKey = _anchor?.key ?? _lastKey ?? '';
      final anchorTop = _anchor?.top ?? 0;
      if (anchorKey.isNotEmpty) {
        _chatScrollPositions[sessionId] = ChatScrollPosition(
          anchorKey: anchorKey,
          anchorTop: anchorTop,
          scrollTop: pos,
        );
      }
    }
    _observedTop = pos;
  }

  void _initialRestore() {
    if (!_controller.hasClients) return;
    final saved = _chatScrollPositions[widget.sessionId];
    if (saved == null) {
      _toBottom(jump: true);
    } else {
      // Best-effort restore: jump to saved scrollTop, then try to align anchor.
      final target = saved.scrollTop.clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      _controller.jumpTo(target);
      _observedTop = target;
      // Try to adjust for anchorTop drift: measure anchor row if available.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = saved.anchorKey;
        final gk = _rowKeys[key];
        final ctx = gk?.currentContext;
        if (ctx != null && _controller.hasClients) {
          final box = ctx.findRenderObject() as RenderBox?;
          final scrollBox = context.findRenderObject() as RenderBox?;
          if (box != null && scrollBox != null) {
            final anchorTopNow =
                box.localToGlobal(Offset.zero).dy -
                scrollBox.localToGlobal(Offset.zero).dy;
            final delta = anchorTopNow - saved.anchorTop;
            if (delta.abs() > 0.5) {
              final next = (_controller.position.pixels + delta).clamp(
                0.0,
                _controller.position.maxScrollExtent,
              );
              _controller.jumpTo(next);
              _observedTop = next;
            }
          }
        }
        _atBottom =
            _controller.position.maxScrollExtent -
                _controller.position.pixels <=
            _followThreshold + 1;
        setState(() {});
      });
      _atBottom =
          _controller.position.maxScrollExtent - target <= _followThreshold + 1;
      setState(() {});
    }
    _opened = true;
  }

  void _toBottom({bool jump = false}) {
    if (!_controller.hasClients) return;
    // Capture at call time: the post-frame callback must not write the store
    // under a NEW session's key if the widget switched in the same frame.
    final String sessionId = widget.sessionId;
    _anchor = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      if (jump) {
        _controller.jumpTo(max);
      } else {
        _controller.animateTo(
          max,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
      _observedTop = max;
      _atBottom = true;
      _chatScrollPositions[sessionId] = null;
      setState(() {});
    });
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final floor = pos.maxScrollExtent;
    final movedByReader =
        (pos.pixels - _observedTop.clamp(0.0, floor)).abs() > 0.5;
    final isAtBottom = movedByReader
        ? floor - pos.pixels <= _followThreshold + 1
        : _atBottom;
    if (!movedByReader && isAtBottom) {
      // Programmatic shrink-clamp landed on floor; keep pinned.
      _observedTop = pos.pixels;
      return;
    }
    _atBottom = isAtBottom;
    // Update anchor for prepend: keep the paging anchor at same scrollport position.
    if (isAtBottom) {
      _anchor = null;
    } else if (_anchor != null) {
      final updated = _pagingAnchor();
      if (updated != null) _anchor = updated;
    }
    _chatScrollPositions[widget.sessionId] = isAtBottom
        ? null
        : ChatScrollPosition(
            anchorKey: _anchor?.key ?? _lastKey ?? '',
            anchorTop: _anchor?.top ?? 0,
            scrollTop: pos.pixels,
          );
    _observedTop = pos.pixels;
    if (mounted) setState(() {});
    // Keep rail active mark in sync with the reading line.
    _syncActiveTurnFromScroll();
  }

  // Follow sig helper: when tip moves while pinned, auto-follow.
  void _maybeFollow(
    String newSig,
    bool appendedUser,
    bool appendedSteering,
    bool tipMoved,
  ) {
    if (!_controller.hasClients) return;
    if (appendedUser || appendedSteering || (tipMoved && _atBottom)) {
      _toBottom();
    } else if (tipMoved && _atBottom) {
      // Streaming growth while pinned: follow via post-frame jump.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_atBottom && _controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
          _observedTop = _controller.position.pixels;
        }
      });
    }
  }

  /// Sync the active turn rail highlight to the reading line.
  ///
  /// Mirrors React's `syncActiveTurn` (reading line at 20% viewport, fallback
  /// to first/last, bottom-pinned snaps to last). Uses anchor Row measurements
  /// when available, else falls back to scroll fraction.
  void _syncActiveTurnFromScroll() {
    if (_cachedTurnItems.length < 2) return;
    if (!_controller.hasClients) return;
    final items = _cachedTurnItems;
    // Bottom-pinned owns last mark.
    final isAtBottom = _controller.position.maxScrollExtent -
            _controller.position.pixels <=
        _followThreshold + 1;
    if (isAtBottom) {
      final lastTurn = items.last.turn;
      if (_activeTurn != lastTurn) setState(() => _activeTurn = lastTurn);
      return;
    }
    // Try measurement path via anchor keys.
    final outerBox = context.findRenderObject() as RenderBox?;
    if (outerBox != null) {
      final outerTop = outerBox.localToGlobal(Offset.zero).dy;
      final viewportHeight = _controller.position.viewportDimension;
      final readingLine = outerTop +
          (viewportHeight * 0.2).clamp(0, 96).toDouble();
      int? foundTurn;
      // Anchor order equals turn order (appearance).
      for (final item in items) {
        final gk = _rowKeys[item.anchorKey];
        final ctx = gk?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        if (top <= readingLine) foundTurn = item.turn;
        else break;
      }
      foundTurn ??= items.first.turn;
      // Map readingTurn to nearest rail item <= reading (already done via anchors).
      if (foundTurn != _activeTurn) setState(() => _activeTurn = foundTurn);
      return;
    }
    // Fallback: scroll fraction.
    final max = _controller.position.maxScrollExtent;
    final ratio = max <= 0 ? 0 : (_controller.position.pixels / max).clamp(0, 1).toDouble();
    final idx = (ratio * (items.length - 1)).round().clamp(0, items.length - 1);
    final turn = items[idx].turn;
    if (turn != _activeTurn) setState(() => _activeTurn = turn);
  }

  /// Scroll to the node that owns [item.anchorKey].
  void _navigateToTurn(TurnNavigationItem item) {
    if (!_controller.hasClients) return;
    final idx = _cachedTurnItems.indexWhere((e) => e.turn == item.turn);
    if (idx == -1) return;
    // Update active immediately for responsive rail.
    setState(() => _activeTurn = item.turn);
    // Prefer anchor measurement when the row is already mounted.
    final gk = _rowKeys[item.anchorKey];
    final anchorCtx = gk?.currentContext;
    if (anchorCtx != null) {
      Scrollable.ensureVisible(
        anchorCtx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.05,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _observedTop = _controller.position.pixels;
        }
        _syncActiveTurnFromScroll();
      });
      return;
    }
    // Fallback: fraction-based estimate then fine-adjust on next frame.
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigateToTurn(item));
      return;
    }
    final fraction = _cachedTurnItems.length <= 1
        ? 0.0
        : idx / (_cachedTurnItems.length - 1);
    final target = (max * fraction).clamp(0.0, max);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gk2 = _rowKeys[item.anchorKey];
      final ctx2 = gk2?.currentContext;
      if (ctx2 != null && _controller.hasClients) {
        final box = ctx2.findRenderObject() as RenderBox?;
        final outer = context.findRenderObject() as RenderBox?;
        if (box != null && outer != null) {
          final boxTop = box.localToGlobal(Offset.zero).dy;
          final outerTop = outer.localToGlobal(Offset.zero).dy;
          final delta = boxTop - outerTop - 24;
          if (delta.abs() > 0.5) {
            final next = (_controller.position.pixels + delta)
                .clamp(0.0, _controller.position.maxScrollExtent);
            _controller.animateTo(
              next,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        }
      }
      if (_controller.hasClients) _observedTop = _controller.position.pixels;
      _syncActiveTurnFromScroll();
    });
  }

  Future<void> _forkAt(int seq) async {
    if (seq <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fork unavailable: no seq')),
        );
      }
      return;
    }
    final client = ref.read(connectionClientProvider);
    try {
      final res = await client.callMethod('session/fork', {
        'sessionId': widget.sessionId,
        'atSeq': seq,
      });
      String? childId;
      if (res.containsKey('sessionId') && res['sessionId'] is String) {
        childId = res['sessionId'] as String;
      } else if (res.containsKey('value') && res['value'] is String) {
        childId = res['value'] as String;
      } else if (res.containsKey('_primitive') && res['_primitive'] is String) {
        childId = res['_primitive'] as String;
      } else if (res['value'] is Map && (res['value'] as Map)['sessionId'] is String) {
        childId = (res['value'] as Map)['sessionId'] as String;
      }
      // Legacy fallback shape where callMethod unwraps via result.value
      childId ??= res['_list'] is List ? null : null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(childId != null ? 'Forked to $childId' : 'Fork at seq $seq'),
          ),
        );
        if (childId != null) {
          try {
            final all = await client.getSessions();
            ref.read(sessionsProvider.notifier).setAll(all);
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fork failed: $e')),
        );
      }
    }
  }

  List<ConversationNode> _flattenNodes(List<ConversationNode> nodes) {
    final out = <ConversationNode>[];
    for (final n in nodes) {
      if (n is StepGroupNode) {
        // Step header handled separately; children are flat flow items.
        // Keep header as optional compact separator but render children individually.
        // We emit children directly; the header will be rendered inline before them.
        out.addAll(n.children);
      } else {
        out.add(n);
      }
    }
    return out;
  }

  String _followSigFor(
    List<ConversationNode> flat,
    bool running,
    String? lastSteeringId,
    String openState,
  ) {
    final firstKey = flat.isNotEmpty ? flat.first.key : null;
    final lastKey = flat.isNotEmpty ? flat.last.key : null;
    return '$openState:${firstKey ?? ''}:${lastKey ?? ''}:${flat.length}:${running ? 1 : 0}:${lastSteeringId ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(liveHistoryProvider(widget.sessionId));
    final hub = activatedHub;

    final folder = ConversationNodeFolder();
    for (final entry in entries) {
      folder.add(SessionEventEnvelope.fromJson(entry.event.toJson()));
    }
    final rawNodes = folder.snapshot().nodes;
    // Keep rawNodes for step header detection but also flatten for list.
    final flatNodes = _flattenNodes(rawNodes);

    // Determine step headers to render as separators: map step group key -> summary.
    final stepHeaders = <String, StepGroupNode>{};
    for (final n in rawNodes) {
      if (n is StepGroupNode) stepHeaders[n.key] = n;
    }

    // React fidelity: Step/Turn structure is location/bookkeeping, not a
    // visual collapsing container. Flatten every StepGroupNode — no header
    // disclosure, just its children in order (mirrors ChatSnapshotBuilder
    // orderedVisible). Step headers were a Flutter-only invention that hid
    // content behind ExpansionTiles.
    final List<_ChatListItem> items = [];
    for (final n in rawNodes) {
      if (n is StepGroupNode) {
        for (final child in n.children) {
          items.add(_ChatListItem.node(child));
        }
      } else {
        items.add(_ChatListItem.node(n));
      }
    }
    // Fallback: if flattening produced nothing (no steps), use flatNodes.
    if (items.isEmpty) {
      for (final n in flatNodes) {
        items.add(_ChatListItem.node(n));
      }
    }

    // Optimistic user messages — React parity via `session.beginSubmission`
    // (composer clears draft + yields one paint with echo before `session/prompt`).
    // Flutter's `ComposerController.submit` writes to `optimisticMessagesProvider`
    // and `liveMessageListProvider` already merges it, but `ChatView` (the
    // active transcript via `ConversationNodeFolder`) did not — so a new `hi`
    // was invisible until host `user/message` echoed (or until reopen which
    // replays persisted history). Now `ChatView` also renders pending optimistic
    // bubbles and dedupes on host echo (content-trim match), mirroring
    // `liveMessageListProvider`'s dedup and React's echo retirement.
    final optimistic = ref.watch(optimisticMessagesProvider(widget.sessionId));
    if (optimistic.isNotEmpty) {
      // Deduplicate only when the tail is already the host echo of this
      // optimistic (immediate `user/message` after `session/prompt`). Before
      // echo, `items` ends with the previous turn's assistant, so the new
      // `hi` optimistic is shown. After the echo lands via `appendLive`,
      // `items.last` becomes that same `hi` user node — then we hide the
      // optimistic to avoid a duplicate tail bubble. Checking only the tail
      // (not `any` user) preserves repeated `hi` across turns.
      for (final o in optimistic) {
        final t = o.content.trim();
        final hasImages = o.imageUrls.isNotEmpty;
        if (t.isEmpty && !hasImages) continue;
        final tailIsSameUser =
            items.isNotEmpty &&
            items.last.node is UserMessageNode &&
            (items.last.node as UserMessageNode).text.trim() == t;
        if (tailIsSameUser) continue;
        final synth = UserMessageNode(
          key: 'optimistic-${o.id}',
          sourceSeqs: const [],
          text: o.content,
          imageAttachmentIds: o.imageUrls,
        );
        items.add(_ChatListItem.node(synth));
      }
    }

    if (items.isEmpty) {
      return const Center(child: Text('No messages yet'));
    }

    // Streaming / running state for follow sig.
    final summary = ref.watch(sessionByIdProvider(SessionId(widget.sessionId)));
    final running = summary?.running ?? false;
    final hasMore = ref.watch(liveHasMoreProvider(widget.sessionId));
    final loadingOlder = ref.watch(liveLoadingOlderProvider(widget.sessionId));
    // React fidelity: while older history remains pagable, TurnProcess controls stay absent.
    if (hasMore) {
      items.removeWhere((it) => it.node is TurnProcessNode);
    }
    // Keep key order for paging anchor scans
    _currentKeys = items.map((e) => e.key).toList(growable: false);
    // Detect tip movement.
    final newFirstKey = items.isNotEmpty ? items.first.key : null;
    final newLastKey = items.isNotEmpty ? items.last.key : null;
    final newSig = _followSigFor(
      flatNodes,
      running,
      null,
      running ? 'open' : 'open',
    );
    final tipMoved = _followSig != newSig;
    final appendedUser =
        newLastKey != _lastKey &&
        items.isNotEmpty &&
        items.last.node?.kind == _ChatKind.user;
    // Simple steering detection not implemented.
    final appendedSteering = false;

    // Prepend anchoring: preserve the same settled row at same scrollport position.
    // Mirrors React ChatView useLayoutEffect prepend arm (firstSeq < firstSeqRef.current).
    final String? prevFirstKey = _firstKey;
    if (_anchor != null &&
        newFirstKey != null &&
        prevFirstKey != null &&
        newFirstKey != prevFirstKey) {
      final captured = _anchor!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final gk = _rowKeys[captured.key];
        final ctx = gk?.currentContext;
        if (ctx != null && _controller.hasClients) {
          final box = ctx.findRenderObject() as RenderBox?;
          final scrollBox = context.findRenderObject() as RenderBox?;
          if (box != null && scrollBox != null) {
            final nowTop =
                box.localToGlobal(Offset.zero).dy -
                scrollBox.localToGlobal(Offset.zero).dy;
            final delta = nowTop - captured.top;
            if (delta.abs() > 0.5) {
              final next = (_controller.position.pixels + delta).clamp(
                0.0,
                _controller.position.maxScrollExtent,
              );
              _controller.jumpTo(next);
              _observedTop = next;
            }
          }
        }
        _anchor = null;
      });
    }
    // Clear anchor when loading settles without a prepend (empty/failed page).
    if (!loadingOlder && _anchor != null && prevFirstKey == newFirstKey) {
      final wasLoading = _lastLoadingOlder ?? false;
      if (wasLoading) _anchor = null;
    }
    _lastLoadingOlder = loadingOlder;

    // Schedule follow check post-frame if needed. Suppressed while a session
    // switch restore is pending (`_opened == false`): the restore owns the
    // position, and the stale `_atBottom` from the previous session must not
    // snap the restored viewport to the tip.
    if (_opened && (tipMoved || appendedUser || appendedSteering)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeFollow(newSig, appendedUser, appendedSteering, tipMoved),
      );
    }
    // Persist refs for next frame.
    _firstKey = newFirstKey;
    _lastKey = newLastKey;
    _followSig = newSig;

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // Turn navigation rail — parity with React's TurnNavigator.
    final turnItems = ref.watch(turnNavigationItemsProvider(widget.sessionId));
    if (!identical(turnItems, _cachedTurnItems)) {
      _cachedTurnItems = turnItems;
      if (turnItems.isEmpty) {
        _activeTurn = null;
      } else if (_activeTurn == null ||
          !turnItems.any((e) => e.turn == _activeTurn)) {
        _activeTurn = turnItems.last.turn;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncActiveTurnFromScroll();
      });
    }
    final int? effectiveActiveTurn =
        _activeTurn != null && turnItems.any((e) => e.turn == _activeTurn)
            ? _activeTurn
            : (turnItems.isNotEmpty ? turnItems.last.turn : null);

    // ---- StatsLine parity: window fold vs durable sessionStats/tokenUsage projections
    final _WindowStats windowStats = _deriveWindowStats(rawNodes);
    _WindowStats effectiveStats = windowStats;
    TurnTokenUsage? effectiveUsage = _aggregateTokenUsage(rawNodes.whereType<TurnTailNode>().toList());
    final bool hasStats = effectiveStats.steps > 0 || (effectiveUsage != null && (effectiveUsage.billedInputTokens > 0 || effectiveUsage.outputTokens > 0));

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // Ensure observedTop ledger updated for programmatic writes via jumpTo.
            // Listener already handles onScroll; this just ensures we capture metrics.
            return false;
          },
          child: ListView.builder(
            controller: _controller,
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              80 + 8,
            ), // bottom reserves composer height (~80)
            itemCount: items.length + (hasMore ? 1 : 0) + (running ? 1 : 0),
            itemBuilder: (context, index) {
              if (hasMore && index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: TextButton(
                      onPressed: loadingOlder ? null : _loadOlderAnchored,
                      child: Text(loadingOlder ? 'Loading…' : 'Load older'),
                    ),
                  ),
                );
              }
              final adjIndex = hasMore ? index - 1 : index;
              if (adjIndex < items.length) {
                final item = items[adjIndex];
                final node = item.node!;
                final wrapped = _buildNode(context, hub, node, aliases);
                return Container(
                  key: _keyFor(node.key),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: KeyedSubtree(key: ValueKey(node.key), child: wrapped),
                );
              }
              // Running indicator at tail.
              if (running && adjIndex == items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: aliases.labelTertiary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Deep diving…',
                        style: TextStyle(
                          fontSize: 13,
                          color: aliases.labelTertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        // Turn navigation rail — compact overlay on the right gutter.
        // Zero-height overlay like React's sticky slot: does not shift transcript.
        // Hidden when fewer than two turns (React parity: compact rail without placeholder).
        if (turnItems.length >= 2)
          Positioned(
            right: 0,
            top: 12,
            bottom: 96,
            width: 28,
            child: Align(
              alignment: Alignment.centerRight,
              child: TurnNavigatorRail(
                items: turnItems,
                activeTurn: effectiveActiveTurn,
                onNavigate: _navigateToTurn,
              ),
            ),
          ),
        if (!_atBottom)
          Positioned(
            right: 16,
            bottom: 96, // above composer
            child: FloatingActionButton.small(
              heroTag: 'chat_to_bottom_${widget.sessionId}',
              onPressed: () => _toBottom(),
              backgroundColor: aliases.bgLayer2,
              foregroundColor: aliases.labelPrimary,
              elevation: 2,
              child: const Icon(Icons.arrow_downward_rounded, size: 18),
            ),
          ),
      ],
    );
  }

  Widget _buildNode(
    BuildContext context,
    ConversationHub? hub,
    ConversationNode node,
    DswAliases aliases,
  ) {
    final kindKey = _kindKey(node);
    // Skip structural markers entirely (zero-height).
    if (node is MarkerNode) return const SizedBox.shrink();

    // Resolve via registry if available.
    final override = hub?.controller.renderers.resolve(kindKey);
    if (override != null) {
      // Build ChatNodeData with full fidelity for tool-call.
      final data = _chatNodeDataFor(node);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: override(context, data),
      );
    }
    // No override: use builtin.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: _builtin(context, node, aliases),
    );
  }

  ChatNodeData _chatNodeDataFor(ConversationNode node) {
    switch (node) {
      case ToolNode(:final callId, :final name, :final result):
        final lines = [callId, if (result != null) result];
        final raw = _ToolNodeRawAdapter(node);
        return ChatNodeData(
          key: node.key,
          lines: lines,
          toolName: name,
          raw: raw,
        );
      case AssistantNode(:final text):
        return ChatNodeData(
          key: node.key,
          lines: [text],
          toolName: null,
          raw: node,
        );
      case UserMessageNode(:final text):
        return ChatNodeData(key: node.key, lines: [text]);
      case ContextNode(:final text, :final label):
        return ChatNodeData(
          key: node.key,
          lines: [text],
          toolName: label,
          raw: node,
        );
      case TurnErrorNode(:final friendly):
        return ChatNodeData(key: node.key, lines: [friendly]);
      case ModelRetryNode(:final retry):
        return ChatNodeData(key: node.key, lines: ['retry #$retry']);
      case CompactionNode(:final text):
        return ChatNodeData(key: node.key, lines: [text]);
      case CommandNode(:final name):
        return ChatNodeData(key: node.key, lines: [name ?? '']);
      case ManualCompactionNode(:final command):
        return ChatNodeData(key: node.key, lines: [command.commandId]);
      case StepGroupNode(:final key, :final summary):
        return ChatNodeData(key: key, lines: [summary]);
      case MarkerNode(:final label):
        return ChatNodeData(key: node.key, lines: [label]);
      case TurnTailNode(:final turn):
        return ChatNodeData(key: node.key, lines: ['turn $turn']);
      case TurnProcessNode(:final turn):
        return ChatNodeData(key: node.key, lines: ['process $turn']);
      case SystemPromptNode(:final text):
        return ChatNodeData(key: node.key, lines: [text], raw: node);
    }
  }

  Widget _builtin(
    BuildContext context,
    ConversationNode node,
    DswAliases aliases,
  ) {
    switch (node) {
      case UserMessageNode(:final text, :final imageAttachmentIds):
        final int forkSeq = node.sourceSeqs.isNotEmpty ? node.sourceSeqs.first : 0;
        return Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: aliases.bgLayer2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (imageAttachmentIds.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          for (final id in imageAttachmentIds)
                            _UserImage(
                              sessionId: widget.sessionId,
                              attachmentId: id,
                            ),
                        ],
                      ),
                    if (imageAttachmentIds.isNotEmpty && text.isNotEmpty)
                      const SizedBox(height: 8),
                    if (text.isNotEmpty) SelectableText(text),
                    if (text.isEmpty && imageAttachmentIds.isEmpty)
                      const SelectableText('(empty message)'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Copy',
                    child: IconButton(
                      icon: Icon(Icons.copy_outlined, size: 14, color: aliases.labelTertiary),
                      onPressed: text.isEmpty
                          ? null
                          : () => ClipboardHelper.copyWithFeedback(context, text),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(28, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Fork',
                    child: IconButton(
                      icon: Icon(Icons.call_split, size: 14, color: aliases.labelTertiary),
                      onPressed: forkSeq == 0 ? null : () => _forkAt(forkSeq),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(28, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case AssistantNode(
        :final text,
        :final streaming,
        :final interrupted,
        :final reasoning,
      ):
        final hasReasoning = reasoning != null && reasoning.trim().isNotEmpty;
        final hasText = text.trim().isNotEmpty;
        if (!hasText && !hasReasoning) {
          return const SizedBox.shrink();
        }
        // React AssistantMarkdown: reasoning blocks become ReasoningRow siblings
        // of markdown text blocks, with no outer bubble border. Match that
        // hierarchy: Think row + prose as separate siblings, prose via markdown.
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasReasoning)
                  _ReasoningRow(
                    text: reasoning!,
                    running: streaming,
                    aliases: aliases,
                  ),
                if (hasReasoning && hasText) const SizedBox(height: 8),
                if (hasText)
                  DsMarkdown(
                    data: streaming ? '$text ▍' : text,
                    selectable: true,
                  ),
                if (interrupted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '[interrupted]',
                      style: TextStyle(
                        fontSize: 11,
                        color: aliases.labelTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (!streaming && hasText)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _MessageIconActions(
                      text: text,
                      messageKey: node.key,
                      aliases: aliases,
                    ),
                  ),
              ],
            ),
          ),
        );

      case ContextNode(:final text, :final label, :final form, :final sections):
        // Render injected context like React's ContextInjectionRow: a collapsed
        // disclosure with browse icon, title, and summary. Sections (snapshot)
        // show the first entry names in collapsed summary.
        final summary = sections != null && sections.isNotEmpty
            ? sections
                  .map((s) => s['name'] ?? '')
                  .where((n) => n.isNotEmpty)
                  .join(', ')
            : text.split('\n').first.trim();
        return _ContextRow(
          label: label,
          form: form,
          summary: summary,
          text: text,
          sections: sections,
          aliases: aliases,
        );

      case ToolNode():
        // Fallback when no registry override is registered (e.g., tests without host).
        // Render via generic disclosure using the same card logic.
        return _ToolFallbackRow(node: node, aliases: aliases);

      case TurnErrorNode(:final friendly, :final errorCode):
        final List<String> parts = friendly.split('\n');
        final String title = parts.isNotEmpty && parts.first.trim().isNotEmpty
            ? parts.first.trim()
            : 'This turn failed';
        final String message = parts.length > 1
            ? parts.sublist(1).join('\n').trim()
            : '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: StateDot(state: StateDotState.error, size: 10),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXs13,
                          height: 20 / DswTokens.fontSizeXs13,
                          fontWeight: FontWeight.w600,
                          color: aliases.stateErrorPrimary,
                        ),
                      ),
                      if (message.isNotEmpty)
                        TextSpan(
                          text: ' $message',
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXs13,
                            height: 20 / DswTokens.fontSizeXs13,
                            color: aliases.labelSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (errorCode != null && errorCode.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  errorCode,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxxs11,
                    height: 18 / DswTokens.fontSizeXxxs11,
                    color: aliases.labelTertiary,
                    fontFamily: 'SF Mono',
                    fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                  ),
                ),
              ],
            ],
          ),
        );

      case MarkerNode():
        return const SizedBox.shrink();

      case TurnTailNode():
        final int forkSeq = node.closingSeq ?? node.seq;
        return _TurnTailCard(
          node: node,
          aliases: aliases,
          onFork: () => _forkAt(forkSeq),
        );

      case TurnProcessNode(
        :final turn,
        :final messageCount,
        :final toolCallCount,
        :final subagentCount,
      ):
        return _TurnProcessRow(
          turn: turn,
          messageCount: messageCount,
          toolCallCount: toolCallCount,
          subagentCount: subagentCount,
          aliases: aliases,
        );

      case ModelRetryNode():
        return _ModelRetryRow(node: node, aliases: aliases);

      case StepGroupNode():
        // Should have been flattened; this case unreachable.
        return const SizedBox.shrink();

      case CompactionNode(
        :final text,
        :final shadowedItemCount,
        :final shadowedTokenCount,
      ):
        return _CompactionCard(
          text: text,
          shadowedItemCount: shadowedItemCount,
          shadowedTokenCount: shadowedTokenCount,
          aliases: aliases,
        );

      case CommandNode(
        :final commandId,
        :final name,
        :final args,
        :final outcome,
      ):
        final isRunning = outcome == null;
        final title = name ?? 'command';
        final summary = isRunning
            ? 'Running…'
            : (outcome!.text ??
                  (outcome!.kind == 'success' ? 'Completed' : 'Failed'));
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                isRunning
                    ? Icons.pending_outlined
                    : outcome!.kind == 'success'
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 14,
                color: isRunning
                    ? aliases.stateWarnPrimary
                    : outcome!.kind == 'success'
                    ? aliases.stateSuccessPrimary
                    : aliases.stateErrorPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: aliases.labelPrimaryDimmed,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 2,
                height: 2,
                decoration: BoxDecoration(
                  color: aliases.labelCaption,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  style: TextStyle(fontSize: 14, color: aliases.labelTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );

      case SystemPromptNode(:final text):
        return _SystemPromptRow(text: text, aliases: aliases);

      case ManualCompactionNode(:final command, :final compaction):
        if (compaction != null) {
          return _CompactionCard(
            text: compaction.text,
            shadowedItemCount: compaction.shadowedItemCount,
            shadowedTokenCount: compaction.shadowedTokenCount,
            aliases: aliases,
            title: 'compact',
            fallbackSummary: command.outcome?.text,
          );
        }
        final isRunning = command.outcome == null;
        final display = isRunning
            ? 'Compacting…'
            : (command.outcome?.text ?? '');
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                isRunning
                    ? Icons.pending_outlined
                    : command.outcome?.kind == 'success'
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 14,
                color: isRunning
                    ? aliases.stateWarnPrimary
                    : command.outcome?.kind == 'success'
                    ? aliases.stateSuccessPrimary
                    : aliases.stateErrorPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                'compact',
                style: TextStyle(
                  fontSize: 14,
                  color: aliases.labelPrimaryDimmed,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 2,
                height: 2,
                decoration: BoxDecoration(
                  color: aliases.labelCaption,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  display.isNotEmpty ? display : 'Compaction',
                  style: TextStyle(fontSize: 14, color: aliases.labelTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
    }
  }
}

// ---- TurnTail token-format + message-chrome helpers (mirrors token-format.ts + message-chrome.ts) ----

String _formatTokens(int value) {
  String scaled(double candidate) {
    if (candidate >= 100) return candidate.round().toString();
    final r = (candidate * 10).round() / 10;
    if (r == r.roundToDouble()) return r.round().toString();
    return r.toStringAsFixed(1);
  }

  if (value < 1000) return value.toString();
  if (value < 1000000) return '${scaled(value / 1000)}K';
  return '${scaled(value / 1000000)}M';
}

String _formatExactTokens(int value) {
  final digits = value.toString();
  final groups = <String>[];
  for (int end = digits.length; end > 0; end -= 3) {
    final start = (end - 3).clamp(0, digits.length);
    groups.insert(0, digits.substring(start, end));
  }
  return groups.join(',');
}

int _roundedPercentUnits(int cacheReadTokens, int denominator, int decimalPlaces) {
  final unitsPerPercent = decimalPlaces == 0 ? 1 : 10;
  final scale = unitsPerPercent * 100;
  final doubledScale = scale * 2;
  final denominatorQuotient = denominator ~/ doubledScale;
  final denominatorRemainder = denominator % doubledScale;
  int lower = 0;
  int upper = scale;
  while (lower < upper) {
    final candidate = (lower + upper + 1) ~/ 2;
    final factor = candidate * 2 - 1;
    final threshold = factor * denominatorQuotient +
        ((factor * denominatorRemainder + doubledScale - 1) ~/ doubledScale);
    if (cacheReadTokens >= threshold) {
      lower = candidate;
    } else {
      upper = candidate - 1;
    }
  }
  return lower;
}

String _displayPercentUnits(int units, int decimalPlaces) {
  if (decimalPlaces == 0) return units.toString();
  final whole = units ~/ 10;
  final tenths = units % 10;
  return tenths == 0 ? whole.toString() : '$whole.$tenths';
}

String? _formatCacheHitPercent(int cacheReadTokens, int promptTokens, [int decimalPlaces = 0]) {
  if (promptTokens == 0) return null;
  final missed = promptTokens - cacheReadTokens;
  if (missed == 0) return '100';
  final roundedUnits = _roundedPercentUnits(cacheReadTokens, promptTokens, decimalPlaces);
  final fullHitUnits = decimalPlaces == 0 ? 100 : 1000;
  if (roundedUnits < fullHitUnits) return _displayPercentUnits(roundedUnits, decimalPlaces);
  int distinguishingPlaces = 1;
  int scaledDoubleGap = missed * 200;
  final denominatorTens = promptTokens ~/ 10;
  while (scaledDoubleGap <= denominatorTens) {
    scaledDoubleGap *= 10;
    distinguishingPlaces += 1;
  }
  final denominatorOnes = promptTokens % 10;
  int roundedLoss = 5;
  for (int loss = 1; loss < 5; loss += 1) {
    final factor = loss * 2 + 1;
    final threshold = factor * denominatorTens + (factor * denominatorOnes ~/ 10);
    if (scaledDoubleGap <= threshold) {
      roundedLoss = loss;
      break;
    }
  }
  return '99.${'9' * (distinguishingPlaces - 1)}${10 - roundedLoss}';
}

String _formatTokensPerSecond(double tps) {
  final clamped = tps < 0 ? 0.0 : tps;
  if (clamped >= 10) return clamped.round().toString();
  final r = (clamped * 10).round() / 10;
  if (r == r.roundToDouble()) return r.round().toString();
  return r.toStringAsFixed(1);
}

String _formatLatencySeconds(int ms) {
  final s = ms < 0 ? 0 : ms / 1000;
  if (s < 10) {
    final r = (s * 10).round() / 10;
    if (r == r.roundToDouble()) return r.round().toString();
    return r.toStringAsFixed(1);
  }
  return s.round().toString();
}

String _formatRunDuration(int ms) {
  final total = ms < 0 ? 0 : (ms / 1000).floor();
  final minutes = total ~/ 60;
  final seconds = total % 60;
  String pad2(int n) => n.toString().padLeft(2, '0');
  if (minutes > 0) return '${minutes}m${pad2(seconds)}s';
  return '${seconds}s';
}

String _formatDuration(int ms) {
  final s = ms / 1000;
  if (s < 60) {
    final r = (s * 10).round() / 10;
    final secStr = r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
    return '${secStr}s';
  }
  final whole = s.round();
  final minutes = whole ~/ 60;
  final seconds = whole % 60;
  return '${minutes}m${seconds}s';
}

String _formatMessageClock(int timeMs, {int? nowMs}) {
  final d = DateTime.fromMillisecondsSinceEpoch(timeMs);
  final n = nowMs != null ? DateTime.fromMillisecondsSinceEpoch(nowMs) : DateTime.now();
  String pad2(int v) => v.toString().padLeft(2, '0');
  final clock = '${pad2(d.hour)}:${pad2(d.minute)}';
  if (d.year == n.year && d.month == n.month && d.day == n.day) return clock;
  if (d.year == n.year) return '${d.month}/${d.day} $clock';
  return '${d.year}-${d.month}-${d.day} $clock';
}

// ---- TurnTail footer card (mirrors TurnTailNodeView.tsx + TurnUsageDisclosure.tsx) ----

class _TurnTailCard extends StatefulWidget {
  const _TurnTailCard({required this.node, required this.aliases, this.onFork});
  final TurnTailNode node;
  final DswAliases aliases;
  final VoidCallback? onFork;
  @override
  State<_TurnTailCard> createState() => _TurnTailCardState();
}

class _TurnTailCardState extends State<_TurnTailCard> {
  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final aliases = widget.aliases;
    final usage = node.tokenUsage;
    final timeLabel = _formatMessageClock(node.time);
    final runLabel = node.runMs == null ? null : _formatRunDuration(node.runMs!);
    final ttftLabel = node.ttftMs == null ? null : _formatLatencySeconds(node.ttftMs!);
    final tpsLabel = node.tokensPerSecond == null ? null : _formatTokensPerSecond(node.tokensPerSecond!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (usage != null) _TurnUsageDisclosure(usage: usage, aliases: aliases),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 0,
                  children: [
                    Text(
                      timeLabel,
                      style: TextStyle(fontSize: 12, color: aliases.labelTertiary, height: 20 / 12),
                    ),
                    if (runLabel != null) ...[
                      const SizedBox(width: 6),
                      Container(width: 2, height: 2, decoration: BoxDecoration(color: aliases.labelCaption, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('Ran for $runLabel', style: TextStyle(fontSize: 12, color: aliases.labelTertiary)),
                    ],
                    if (ttftLabel != null) ...[
                      const SizedBox(width: 6),
                      Container(width: 2, height: 2, decoration: BoxDecoration(color: aliases.labelCaption, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('TTFT ${ttftLabel}s', style: TextStyle(fontSize: 12, color: aliases.labelTertiary)),
                    ],
                    if (tpsLabel != null) ...[
                      const SizedBox(width: 6),
                      Container(width: 2, height: 2, decoration: BoxDecoration(color: aliases.labelCaption, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('$tpsLabel tok/s', style: TextStyle(fontSize: 12, color: aliases.labelTertiary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CopyButton(text: node.closingText ?? '', aliases: aliases),
              const SizedBox(width: 4),
              Tooltip(
                message: node.branchUnavailable ? 'Available only on the last message of a completed turn' : 'Branch into a new conversation',
                child: IconButton(
                  icon: Icon(Icons.account_tree_outlined, size: 16, color: node.branchUnavailable ? aliases.labelCaption : aliases.labelTertiary),
                  onPressed: node.branchUnavailable ? null : widget.onFork,
                  style: IconButton.styleFrom(minimumSize: const Size(28, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text, required this.aliases});
  final String text;
  final DswAliases aliases;
  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    if (_copied) return;
    if (widget.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _copied ? 'Copied' : 'Copy',
      child: IconButton(
        icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 16, color: widget.aliases.labelTertiary),
        onPressed: _copy,
        style: IconButton.styleFrom(minimumSize: const Size(28, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero),
      ),
    );
  }
}

/// Assistant message icon actions row — copy, feedback, share.
///
/// Mirrors React's `conversation.chat.assistant-actions` list entry
/// (`MessageFeedbackActions` between copy and branch). Single-row for now
/// (not a keyed registry) but same visual: icon size 14, `labelTertiary`
/// idle, `stateBusinessPrimary` when selected, gap 6, padding 6.
/// Copy uses [ClipboardHelper.copyWithFeedback]; thumbs keep ephemeral
/// local selection state (not persisted).
class _MessageIconActions extends StatefulWidget {
  const _MessageIconActions({
    required this.text,
    required this.messageKey,
    required this.aliases,
  });
  final String text;
  final String messageKey;
  final DswAliases aliases;
  @override
  State<_MessageIconActions> createState() => _MessageIconActionsState();
}

class _MessageIconActionsState extends State<_MessageIconActions> {
  bool _thumbsUp = false;
  bool _thumbsDown = false;

  void _toggleUp() {
    setState(() {
      if (_thumbsUp) {
        _thumbsUp = false;
      } else {
        _thumbsUp = true;
        _thumbsDown = false;
      }
    });
  }

  void _toggleDown() {
    setState(() {
      if (_thumbsDown) {
        _thumbsDown = false;
      } else {
        _thumbsDown = true;
        _thumbsUp = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final aliases = widget.aliases;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Copy',
          child: IconButton(
            icon: Icon(Icons.copy_outlined, size: 14, color: aliases.labelTertiary),
            onPressed: () => ClipboardHelper.copyWithFeedback(context, widget.text),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.all(6),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: _thumbsUp ? 'Liked' : 'Like',
          child: IconButton(
            icon: Icon(
              _thumbsUp ? Icons.thumb_up : Icons.thumb_up_outlined,
              size: 14,
              color: _thumbsUp ? aliases.stateBusinessPrimary : aliases.labelTertiary,
            ),
            onPressed: _toggleUp,
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.all(6),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: _thumbsDown ? 'Disliked' : 'Dislike',
          child: IconButton(
            icon: Icon(
              _thumbsDown ? Icons.thumb_down : Icons.thumb_down_outlined,
              size: 14,
              color: _thumbsDown ? aliases.stateBusinessPrimary : aliases.labelTertiary,
            ),
            onPressed: _toggleDown,
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.all(6),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Share',
          child: IconButton(
            icon: Icon(Icons.ios_share_outlined, size: 14, color: aliases.labelTertiary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share not yet implemented')),
              );
            },
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.all(6),
            ),
          ),
        ),
      ],
    );
  }
}

class _TurnUsageDisclosure extends StatefulWidget {
  const _TurnUsageDisclosure({required this.usage, required this.aliases});
  final TurnTokenUsage usage;
  final DswAliases aliases;
  @override
  State<_TurnUsageDisclosure> createState() => _TurnUsageDisclosureState();
}

class _TurnUsageDisclosureState extends State<_TurnUsageDisclosure> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final usage = widget.usage;
    final aliases = widget.aliases;
    final totalStr = '${_formatTokens(usage.totalTokens)} tok';
    final cacheHit = usage.cacheReadTokens == null ? null : _formatCacheHitPercent(usage.cacheReadTokens!, usage.totalTokens - usage.outputTokens, 1);
    final summary = cacheHit == null ? totalStr : '$totalStr · Cache hit $cacheHit%';
    final routes = usage.routes?.map((r) => '${r.provider}/${r.model}').join(', ') ?? '';
    final collapsed = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 2, height: 2, decoration: BoxDecoration(color: aliases.labelCaption, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Flexible(child: Text(summary, style: TextStyle(fontSize: 13, color: aliases.labelTertiary, height: 24 / 13), overflow: TextOverflow.ellipsis)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DisclosureRow(
          icon: Icon(Icons.data_usage_outlined, size: 16, color: aliases.labelTertiary),
          title: 'Turn usage',
          open: _open,
          expandable: true,
          expandOnRowClick: true,
          keepContentWhenOpen: true,
          onToggle: () => setState(() => _open = !_open),
          collapsedContent: collapsed,
          child: Container(
            margin: const EdgeInsets.only(left: 22, top: 4, right: 0),
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
            decoration: BoxDecoration(color: aliases.markdownCodeBlock, borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (routes.isNotEmpty) ...[
                  _UsageRow(label: 'Provider / model', value: routes, aliases: aliases, isRoute: true),
                  const SizedBox(height: 6),
                ],
                _UsageRow(label: 'Uncached input', value: '${_formatExactTokens(usage.uncachedInputTokens)} tok', aliases: aliases),
                if (usage.cacheReadTokens != null) ...[
                  const SizedBox(height: 6),
                  _UsageRow(label: 'Cached input', value: '${_formatExactTokens(usage.cacheReadTokens!)} tok', aliases: aliases),
                ],
                if (usage.cacheWriteTokens != null) ...[
                  const SizedBox(height: 6),
                  _UsageRow(label: 'Cache write', value: '${_formatExactTokens(usage.cacheWriteTokens!)} tok', aliases: aliases),
                ],
                const SizedBox(height: 6),
                _UsageRow(
                  label: 'Output',
                  value: '${_formatExactTokens(usage.outputTokens)} tok${usage.reasoningTokens == null ? '' : ' (${_formatExactTokens(usage.reasoningTokens!)} tok reasoning)'}',
                  aliases: aliases,
                ),
                const SizedBox(height: 6),
                Container(height: 1, color: aliases.borderL1),
                const SizedBox(height: 6),
                _UsageRow(label: 'Total', value: '${_formatExactTokens(usage.totalTokens)} tok', aliases: aliases, isTotal: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.label, required this.value, required this.aliases, this.isRoute = false, this.isTotal = false});
  final String label;
  final String value;
  final DswAliases aliases;
  final bool isRoute;
  final bool isTotal;
  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(fontSize: 12, color: isTotal ? aliases.labelPrimary : aliases.labelTertiary, height: 18 / 12);
    final valueStyle = TextStyle(fontSize: 12, color: isTotal ? aliases.labelPrimary : aliases.labelSecondary, height: 18 / 12);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: Text(label, style: labelStyle)),
        const SizedBox(width: 16),
        Expanded(child: Text(value, style: valueStyle, textAlign: TextAlign.right)),
      ],
    );
  }
}

// ---- StatsLine parity (mirrors StatsLine.tsx) ----

class _WindowStats {
  const _WindowStats({
    required this.turns,
    required this.steps,
    required this.llmMs,
    required this.toolMs,
    required this.ttftMs,
    required this.ttftSteps,
    required this.decodeMs,
    required this.decodeTokens,
  });
  final int turns;
  final int steps;
  final int llmMs;
  final int toolMs;
  final int ttftMs;
  final int ttftSteps;
  final int decodeMs;
  final int decodeTokens;
}

_WindowStats _deriveWindowStats(List<ConversationNode> nodes) {
  final tails = nodes.whereType<TurnTailNode>().toList();
  final groups = nodes.whereType<StepGroupNode>().toList();
  // Also collect open groups that may have been flattened? groups already cover settled + open before flattening
  final turnSet = <int>{};
  for (final t in tails) turnSet.add(t.turn);
  for (final g in groups) turnSet.add(g.turn);
  // Fallback: if no tails but groups present, turns already counted; if neither, 0
  final turns = turnSet.length;
  final steps = groups.length;
  int llmMs = 0;
  int ttftMs = 0;
  int ttftSteps = 0;
  int decodeMs = 0;
  int decodeTokens = 0;
  for (final t in tails) {
    if (t.runMs != null) llmMs += t.runMs!;
    if (t.ttftMs != null) {
      ttftMs += t.ttftMs!;
      ttftSteps += 1;
    }
    if (t.tokenUsage != null && t.runMs != null && t.ttftMs != null) {
      final dm = (t.runMs! - t.ttftMs!).clamp(0, 1 << 30);
      if (dm > 0) {
        decodeMs += dm;
        decodeTokens += t.tokenUsage!.outputTokens;
      }
    } else if (t.tokenUsage != null && t.tokenUsage!.outputTokens > 0) {
      // Fallback when runMs missing: estimate decode as end - firstToken
      if (t.ttftMs != null && t.runMs != null) {
        final dm = (t.runMs! - t.ttftMs!).clamp(0, 1 << 30);
        if (dm > 0) {
          decodeMs += dm;
          decodeTokens += t.tokenUsage!.outputTokens;
        }
      }
    }
  }
  int toolMs = 0;
  // Tool durations are tracked in the folder's private map; we cannot access it here,
  // so we leave toolMs at 0. The dock still renders counts/speeds/token groups.
  return _WindowStats(turns: turns, steps: steps, llmMs: llmMs, toolMs: toolMs, ttftMs: ttftMs, ttftSteps: ttftSteps, decodeMs: decodeMs, decodeTokens: decodeTokens);
}

TurnTokenUsage? _aggregateTokenUsage(List<TurnTailNode> tails) {
  final withUsage = tails.where((t) => t.tokenUsage != null).map((t) => t.tokenUsage!).toList();
  if (withUsage.isEmpty) return null;
  int sumInput = 0;
  int sumOutput = 0;
  int sumTotal = 0;
  int? sumCacheRead;
  int? sumCacheWrite;
  int? sumReasoning;
  bool allCacheRead = withUsage.every((u) => u.cacheReadTokens != null);
  bool allCacheWrite = withUsage.every((u) => u.cacheWriteTokens != null);
  bool allReasoning = withUsage.every((u) => u.reasoningTokens != null);
  bool allRoutes = withUsage.every((u) => u.routes != null);
  final routeUniq = <String, TurnTokenUsageRoute>{};
  for (final u in withUsage) {
    sumInput += u.uncachedInputTokens;
    sumOutput += u.outputTokens;
    sumTotal += u.totalTokens;
    if (sumInput > 9007199254740991 || sumOutput > 9007199254740991 || sumTotal > 9007199254740991) return null;
  }
  if (allCacheRead) {
    sumCacheRead = withUsage.fold<int>(0, (s, u) => s + u.cacheReadTokens!);
    if (sumCacheRead > 9007199254740991) return null;
  }
  if (allCacheWrite) {
    sumCacheWrite = withUsage.fold<int>(0, (s, u) => s + u.cacheWriteTokens!);
    if (sumCacheWrite > 9007199254740991) return null;
  }
  if (allReasoning) {
    sumReasoning = withUsage.fold<int>(0, (s, u) => s + u.reasoningTokens!);
    if (sumReasoning > 9007199254740991) return null;
  }
  List<TurnTokenUsageRoute>? aggRoutes;
  if (allRoutes) {
    for (final u in withUsage) {
      for (final r in u.routes!) {
        routeUniq['${r.provider}\u0000${r.model}'] = r;
      }
    }
    aggRoutes = routeUniq.values.toList(growable: false);
  }
  return TurnTokenUsage(
    uncachedInputTokens: sumInput,
    outputTokens: sumOutput,
    totalTokens: sumTotal,
    cacheReadTokens: sumCacheRead,
    cacheWriteTokens: sumCacheWrite,
    reasoningTokens: sumReasoning,
    routes: aggRoutes,
  );
}

class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.stats, this.usage});
  final _WindowStats stats;
  final TurnTokenUsage? usage;
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ?? (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final List<String> groups = [];
    if (stats.steps > 0) {
      groups.add('${stats.turns} turns · ${stats.steps} steps');
      final durations = <String>[];
      if (stats.llmMs > 0) durations.add('LLM ${_formatDuration(stats.llmMs)}');
      if (stats.toolMs > 0) durations.add('Tool call ${_formatDuration(stats.toolMs)}');
      if (durations.isNotEmpty) groups.add(durations.join(' · '));
      final speeds = <String>[];
      if (stats.ttftSteps > 0) {
        final avg = (stats.ttftMs / stats.ttftSteps).round();
        speeds.add('TTFT avg ${_formatDuration(avg)}');
      }
      if (stats.decodeMs > 0) {
        final tps = stats.decodeTokens / (stats.decodeMs / 1000);
        speeds.add('${_formatTokensPerSecond(tps)} tok/s');
      }
      if (speeds.isNotEmpty) groups.add(speeds.join(' · '));
    }
    if (usage != null && (usage!.billedInputTokens > 0 || usage!.outputTokens > 0)) {
      final cacheHit = usage!.cacheReadTokens == null ? null : _formatCacheHitPercent(usage!.cacheReadTokens!, usage!.billedInputTokens);
      if (cacheHit != null) groups.add('Cache hit $cacheHit%');
      groups.add('Input ${_formatTokens(usage!.billedInputTokens)} tok · Output ${_formatTokens(usage!.outputTokens)} tok');
    }
    if (groups.isEmpty) return const SizedBox.shrink();
    final line = groups.join(' | ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 748),
          child: Text(
            line,
            style: TextStyle(fontSize: 13, color: aliases.labelTertiary, height: 20 / 13),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

// Adapter for ToolNode raw hole.
class _ToolNodeRawAdapter
    implements ToolNodeAdapter, ToolNodeAdapterWithSubCalls {
  _ToolNodeRawAdapter(this.node);
  final ToolNode node;
  @override
  List<ToolSubCallAdapter> get subCalls =>
      node.subCalls.map((c) => _ToolSubCallAdapterImpl(c)).toList();
  @override
  ToolCall toToolCall() {
    final status = node.status == ToolNodeStatus.running
        ? ToolCallStatus.running
        : node.isError
        ? ToolCallStatus.error
        : ToolCallStatus.success;
    late final Map<String, dynamic> args;
    final raw = node.argsRaw;
    if (raw == null || raw.trim().isEmpty) {
      args = const {};
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          args = (decoded as Map).cast<String, dynamic>();
        } else {
          args = {'raw': raw};
        }
      } catch (_) {
        args = {'raw': raw};
      }
    }
    return ToolCall(
      id: node.callId,
      toolName: node.name,
      kind: kindForTool(node.name),
      status: status,
      args: args,
      result: node.result,
      time: 0,
    );
  }
}

class _ChatListItem {
  const _ChatListItem.header(this.header) : node = null;
  const _ChatListItem.node(this.node) : header = null;
  final StepGroupNode? header;
  final ConversationNode? node;
  bool get isHeader => header != null;
  String get key => header?.key ?? node!.key;
}

enum _ChatKind { user, assistant, tool, other }

extension on ConversationNode {
  _ChatKind get kind => switch (this) {
    UserMessageNode() => _ChatKind.user,
    AssistantNode() => _ChatKind.assistant,
    ToolNode() => _ChatKind.tool,
    _ => _ChatKind.other,
  };
}

/// Think row — collapsed by default, live one-line summary while streaming
/// follows the latest non-blank reasoning line, stops after settlement.
class _ReasoningRow extends StatefulWidget {
  const _ReasoningRow({
    required this.text,
    required this.running,
    required this.aliases,
  });
  final String text;
  final bool running;
  final DswAliases aliases;
  @override
  State<_ReasoningRow> createState() => _ReasoningRowState();
}

class _ReasoningRowState extends State<_ReasoningRow> {
  bool _expanded = false;
  final _summaryKey = GlobalKey();
  final _scrollController = ScrollController();

  String _firstLine(String text) {
    final nl = text.indexOf('\n');
    return nl == -1 ? text : text.substring(0, nl);
  }

  String _latestLine(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return '';
    final nl = trimmed.lastIndexOf('\n');
    return nl == -1 ? trimmed : trimmed.substring(nl + 1);
  }

  @override
  void didUpdateWidget(covariant _ReasoningRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && widget.running) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } else if (!widget.running && oldWidget.running) {
      // Settlement: scroll to start.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.running
        ? _latestLine(widget.text)
        : _firstLine(widget.text);
    return Container(
      decoration: BoxDecoration(
        color: widget.aliases.bgOverlay.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.aliases.borderL2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: widget.aliases.labelTertiary,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.lightbulb_outline,
                    size: 14,
                    color: widget.aliases.labelTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Thinking',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.aliases.labelTertiary,
                    ),
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        key: _summaryKey,
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Text(
                          summary,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.aliases.labelCaption,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    _expanded ? 'Hide' : 'Show',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.aliases.labelCaption,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SelectableText(
                widget.text,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.aliases.labelSecondary,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fallback tool row when no registry override is present (tests without host).
class _ToolFallbackRow extends StatefulWidget {
  const _ToolFallbackRow({required this.node, required this.aliases});
  final ToolNode node;
  final DswAliases aliases;
  @override
  State<_ToolFallbackRow> createState() => _ToolFallbackRowState();
}

class _ToolFallbackRowState extends State<_ToolFallbackRow> {
  bool _expanded = false;
  ToolRowVariant _variantFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('search') || n.contains('grep') || n.contains('glob'))
      return ToolRowVariant.search;
    if (n.contains('read') || n.contains('view') || n.contains('cat'))
      return ToolRowVariant.read;
    if (n.contains('bash') || n.contains('shell') || n.contains('exec'))
      return ToolRowVariant.bash;
    if (n.contains('write')) return ToolRowVariant.write;
    if (n.contains('edit')) return ToolRowVariant.edit;
    if (n.contains('code') || n.contains('run_code'))
      return ToolRowVariant.code;
    return ToolRowVariant.others;
  }

  Widget _iconFor(ToolRowVariant variant, ToolNodeStatus status) {
    if (status == ToolNodeStatus.error)
      return const StateDot(state: StateDotState.error);
    if (status == ToolNodeStatus.running)
      return Icon(
        Icons.pending_outlined,
        size: 14,
        color: widget.aliases.stateWarnPrimary,
      );
    final Color iconColor = widget.node.name.startsWith('cordis_')
        ? widget.aliases.stateBusinessPrimary
        : widget.aliases.labelTertiary;
    return switch (variant) {
      ToolRowVariant.search => Icon(Icons.search, size: 14, color: iconColor),
      ToolRowVariant.read => Icon(
        Icons.description_outlined,
        size: 14,
        color: iconColor,
      ),
      ToolRowVariant.bash => Icon(
        Icons.terminal_rounded,
        size: 14,
        color: iconColor,
      ),
      ToolRowVariant.write || ToolRowVariant.edit => Icon(
        Icons.edit_outlined,
        size: 14,
        color: iconColor,
      ),
      ToolRowVariant.code => Icon(
        Icons.code_rounded,
        size: 14,
        color: iconColor,
      ),
      ToolRowVariant.others => Icon(
        Icons.auto_awesome_outlined,
        size: 14,
        color: iconColor,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final variant = _variantFor(widget.node.name);
    final summary = widget.node.result?.split('\n').first.trim() ?? '';
    final expandable =
        widget.node.result != null && widget.node.result!.trim().isNotEmpty;
    final failureLine = widget.node.status == ToolNodeStatus.error
        ? (summary.isNotEmpty ? summary : widget.node.result)
        : null;
    final summaryText = failureLine ?? summary;
    final summaryColor = failureLine != null
        ? widget.aliases.stateErrorPrimary
        : widget.aliases.labelTertiary;
    final collapsed = summaryText.isNotEmpty
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 2,
                height: 2,
                decoration: BoxDecoration(
                  color: widget.node.name.startsWith('cordis_')
                      ? widget.aliases.stateBusinessPrimary
                      : widget.aliases.labelCaption,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  summaryText,
                  style: TextStyle(
                    fontSize: 14,
                    height: 24 / 14,
                    color: summaryColor,
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          )
        : const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DisclosureRow(
          icon: _iconFor(variant, widget.node.status),
          title: widget.node.name,
          open: _expanded && expandable,
          expandable: expandable,
          expandOnRowClick: true,
          keepContentWhenOpen: true,
          onToggle: () => setState(() => _expanded = !_expanded),
          collapsedContent: collapsed,
          child: expandable
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                  child: _IoCard(
                    aliases: widget.aliases,
                    output: widget.node.result,
                    isError: widget.node.status == ToolNodeStatus.error,
                  ),
                )
              : null,
        ),
        if (widget.node.subCalls.isNotEmpty)
          _SubCallsTree(
            subCalls: widget.node.subCalls,
            aliases: widget.aliases,
          ),
      ],
    );
  }
}

enum ToolRowVariant { search, read, bash, write, edit, code, others }

class _IoCard extends StatelessWidget {
  const _IoCard({required this.aliases, this.output, this.isError = false});
  final DswAliases aliases;
  final String? output;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    final out = output?.trim().isEmpty == true ? null : output;
    if (out == null) return const SizedBox.shrink();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            constraints: const BoxConstraints(maxHeight: 150),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OUT',
                  style: TextStyle(
                    fontSize: 11,
                    height: 18 / 11,
                    color: aliases.labelCaption,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText.rich(
                      ansiToSpan(
                        out,
                        fallbackColor: isError
                            ? aliases.stateErrorPrimary
                            : aliases.labelSecondary,
                      ),
                      style: TextStyle(
                        fontSize: DswTokens.markdownCodeBlockSmallSize,
                        height:
                            DswTokens.markdownCodeBlockSmallLineHeight /
                            DswTokens.markdownCodeBlockSmallSize,
                        fontFamily: 'SF Mono',
                        color: isError
                            ? aliases.stateErrorPrimary
                            : aliases.labelSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Copy',
                  child: IconButton(
                    icon: Icon(Icons.copy_outlined, size: 14, color: aliases.labelTertiary),
                    onPressed: () => ClipboardHelper.copyWithFeedback(context, out),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(28, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.all(6),
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

class _SubCallRow extends StatelessWidget {
  const _SubCallRow({required this.subCall, required this.aliases});
  final ToolSubCall subCall;
  final DswAliases aliases;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            subCall.isError ? Icons.error_outline : Icons.code_rounded,
            size: 12,
            color: subCall.isError
                ? aliases.stateErrorPrimary
                : aliases.labelTertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subCall.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: subCall.isError
                        ? aliases.stateErrorPrimary
                        : aliases.labelSecondary,
                  ),
                ),
                if (subCall.result != null && subCall.result!.isNotEmpty)
                  Text(
                    subCall.result!,
                    style: TextStyle(
                      fontSize: 11,
                      color: subCall.isError
                          ? aliases.stateErrorPrimary
                          : aliases.labelTertiary,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubCallsTree extends StatelessWidget {
  const _SubCallsTree({required this.subCalls, required this.aliases});
  final List<ToolSubCall> subCalls;
  final DswAliases aliases;
  @override
  Widget build(BuildContext context) {
    if (subCalls.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 4, 0, 2),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: aliases.borderL2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final sub in subCalls) ...[
            _SubCallRow(subCall: sub, aliases: aliases),
            if (sub.children.isNotEmpty)
              _SubCallsTree(subCalls: sub.children, aliases: aliases),
          ],
        ],
      ),
    );
  }
}

/// Injected context row — mirrors React's ContextInjectionRow: collapsed
/// DisclosureRow with browse icon, title, and summary; body shows sections
/// or raw text bounded to 20k chars. Collapsed by default so runtime
/// snapshot does not dominate the transcript like the raw Flutter bug.
class _ContextRow extends StatefulWidget {
  const _ContextRow({
    required this.label,
    required this.form,
    required this.summary,
    required this.text,
    required this.sections,
    required this.aliases,
  });
  final String? label;
  final String? form;
  final String summary;
  final String text;
  final List<Map<String, String>>? sections;
  final DswAliases aliases;
  @override
  State<_ContextRow> createState() => _ContextRowState();
}

class _ContextRowState extends State<_ContextRow> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final hasBody =
        widget.text.trim().isNotEmpty ||
        (widget.sections != null && widget.sections!.isNotEmpty);
    // React title is always "Context injection" (or "Context recall") — not per-form.
    final title = 'Context injection';
    final collapsed = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 2,
          height: 2,
          decoration: BoxDecoration(
            color: widget.aliases.labelCaption,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        if (widget.label != null)
          Flexible(
            child: Text(
              widget.label!,
              style: TextStyle(
                fontSize: 13,
                color: widget.aliases.labelSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.label != null && widget.summary.isNotEmpty)
          const SizedBox(width: 8),
        if (widget.summary.isNotEmpty)
          Flexible(
            child: Text(
              widget.summary,
              style: TextStyle(
                fontSize: 13,
                color: widget.aliases.labelTertiary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
      ],
    );
    // When collapsed summary empty, still show title alone (no dot).
    final effectiveCollapsed = (widget.label == null && widget.summary.isEmpty)
        ? const SizedBox.shrink()
        : collapsed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DisclosureRow(
          icon: Icon(
            Icons.article_outlined,
            size: 14,
            color: widget.aliases.labelTertiary,
          ),
          title: title,
          open: _expanded && hasBody,
          expandable: hasBody,
          expandOnRowClick: true,
          keepContentWhenOpen: true,
          onToggle: () => setState(() => _expanded = !_expanded),
          collapsedContent: effectiveCollapsed,
          child: hasBody
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.sections != null)
                        ...widget.sections!.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s['name'] ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.aliases.labelPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s['text'] ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: widget.aliases.labelSecondary,
                                    height: 1.4,
                                  ),
                                  maxLines: 6,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (widget.sections == null && widget.text.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: widget.aliases.markdownCodeBlock,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: widget.aliases.borderL1),
                          ),
                          child: Text(
                            widget.text.length > 20000
                                ? '${widget.text.substring(0, 20000)}\n… truncated'
                                : widget.text,
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.aliases.labelSecondary,
                              fontFamily: 'SF Mono',
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

/// System prompt row — mirrors React's SystemPromptRow: collapsed
/// DisclosureRow with browse icon and "System prompt" title, first-line
/// summary when collapsed, and exact model-visible text with original
/// line breaks in a bounded scrollable body when expanded.
class _SystemPromptRow extends StatefulWidget {
  const _SystemPromptRow({required this.text, required this.aliases});
  final String text;
  final DswAliases aliases;
  @override
  State<_SystemPromptRow> createState() => _SystemPromptRowState();
}

class _SystemPromptRowState extends State<_SystemPromptRow> {
  bool _expanded = false;

  String _firstLine(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final nl = trimmed.indexOf('\n');
    return nl == -1 ? trimmed : trimmed.substring(0, nl).trim();
  }

  @override
  Widget build(BuildContext context) {
    final hasBody = widget.text.trim().isNotEmpty;
    // React SystemPromptRow has no collapsed summary — title only.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DisclosureRow(
          icon: Icon(
            Icons.description_outlined,
            size: 14,
            color: widget.aliases.labelTertiary,
          ),
          title: 'System prompt',
          open: _expanded && hasBody,
          expandable: hasBody,
          expandOnRowClick: true,
          keepContentWhenOpen: true,
          onToggle: () => setState(() => _expanded = !_expanded),
          child: hasBody
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.aliases.markdownCodeBlock,
                      borderRadius:
                          BorderRadius.circular(DswTokens.radiusLg),
                      border: Border.all(color: widget.aliases.borderL1),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          widget.text.length > 20000
                              ? '${widget.text.substring(0, 20000)}\n… truncated'
                              : widget.text,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.aliases.labelSecondary,
                            fontFamily: 'SF Mono',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

class _ModelRetryRow extends StatefulWidget {
  const _ModelRetryRow({required this.node, required this.aliases});
  final ModelRetryNode node;
  final DswAliases aliases;
  @override
  State<_ModelRetryRow> createState() => _ModelRetryRowState();
}

class _ModelRetryRowState extends State<_ModelRetryRow> {
  bool _expanded = false;

  int _retrySeconds(int ms) => ms <= 0 ? 1 : (ms / 1000).ceil().clamp(1, 1 << 30);
  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final aliases = widget.aliases;
    final seconds = _retrySeconds(node.delayMs);
    final maximum = node.maxRetries <= 0 ? '∞' : '${node.maxRetries}';
    final String label;
    if (node.started) {
      label = 'Retrying';
    } else if (node.retry >= node.maxRetries && node.maxRetries > 0) {
      label = 'Retried';
    } else {
      label = 'Scheduled';
    }
    final summary =
        '$label model request (${node.retry}/$maximum) · ${seconds}s';
    final hasDetails =
        node.failureMessage != null && node.failureMessage!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
          borderRadius: BorderRadius.circular(DswTokens.radiusXs),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXs13,
                    height: 20 / DswTokens.fontSizeXs13,
                    color: aliases.labelTertiary,
                  ),
                ),
                if (hasDetails) ...[
                  const SizedBox(width: 7),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : -0.125,
                    duration: DswTokens.transitionDurationFast,
                    child: Icon(
                      Icons.chevron_right,
                      size: 10,
                      color: aliases.labelTertiary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded && hasDetails)
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Delay',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxxs11,
                        color: aliases.labelSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${node.delayMs}ms',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxxs11,
                        color: aliases.labelTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Failure',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxxs11,
                        color: aliases.labelSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        node.failureMessage!,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxxs11,
                          height: 18 / DswTokens.fontSizeXxxs11,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TurnProcessRow extends StatefulWidget {
  const _TurnProcessRow({
    required this.turn,
    required this.messageCount,
    required this.toolCallCount,
    required this.subagentCount,
    required this.aliases,
  });

  final int turn;
  final int messageCount;
  final int toolCallCount;
  final int subagentCount;
  final DswAliases aliases;

  @override
  State<_TurnProcessRow> createState() => _TurnProcessRowState();
}

class _TurnProcessRowState extends State<_TurnProcessRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bool foldable = widget.messageCount > 0 || widget.toolCallCount > 0 || widget.subagentCount > 0;
    final String title;
    if (!foldable) {
      title = 'Thought for a while';
    } else {
      final parts = <String>[];
      if (widget.toolCallCount > 0 && widget.subagentCount == 0) {
        parts.add('${widget.toolCallCount} tool${widget.toolCallCount == 1 ? '' : 's'}');
      } else if (widget.subagentCount > 0 && widget.toolCallCount == 0) {
        parts.add('${widget.subagentCount} subagent${widget.subagentCount == 1 ? '' : 's'}');
      } else if (widget.toolCallCount > 0 && widget.subagentCount > 0) {
        parts.add('${widget.toolCallCount} tool${widget.toolCallCount == 1 ? '' : 's'}');
        parts.add('${widget.subagentCount} subagent${widget.subagentCount == 1 ? '' : 's'}');
      }
      if (widget.messageCount > 0) {
        parts.add('${widget.messageCount} reply${widget.messageCount == 1 ? '' : 'ies'}');
      }
      title = parts.isEmpty ? 'Thought for a while' : parts.join(' · ');
    }

    final collapsed = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 2,
          height: 2,
          decoration: BoxDecoration(
            color: widget.aliases.labelCaption,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: TextStyle(fontSize: 13, color: widget.aliases.labelTertiary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DisclosureRow(
          icon: Icon(Icons.psychology_outlined, size: 14, color: widget.aliases.labelTertiary),
          title: 'Process',
          open: _open,
          expandable: foldable,
          expandOnRowClick: true,
          onToggle: () => setState(() => _open = !_open),
          collapsedContent: collapsed,
          child: _open && foldable
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.aliases.bgLayer2,
                      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                      border: Border.all(color: widget.aliases.borderL2),
                    ),
                    child: Text(
                      'Turn ${widget.turn} process: $title',
                      style: TextStyle(fontSize: 11, color: widget.aliases.labelSecondary),
                    ),
                  ),
                )
              : null,
        ),
        // Divider below summary separating from answer (React TurnProcessNodeView)
        if (_open || !foldable) const SizedBox(height: 8),
        if (_open || !foldable)
          Container(
            height: 1,
            color: widget.aliases.borderL2,
            margin: const EdgeInsets.symmetric(vertical: 4),
          ),
      ],
    );
  }
}

/// Collapsed-by-default compaction marker matching CompactionItem.tsx
class _CompactionCard extends StatefulWidget {
  const _CompactionCard({
    required this.text,
    required this.shadowedItemCount,
    required this.shadowedTokenCount,
    required this.aliases,
    this.title,
    this.fallbackSummary,
  });
  final String text;
  final int shadowedItemCount;
  final int shadowedTokenCount;
  final DswAliases aliases;
  final String? title;
  final String? fallbackSummary;
  @override
  State<_CompactionCard> createState() => _CompactionCardState();
}

class _CompactionCardState extends State<_CompactionCard> {
  bool _expanded = false;
  String _t(BuildContext context, String key) {
    final locale = Localizations.localeOf(context).languageCode;
    final zh = kConversationZh[key];
    final en = kConversationEn[key];
    if (locale == 'zh' && zh != null) return zh;
    return en ?? zh ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final hasSummary = widget.text.trim().isNotEmpty;
    final expandable = hasSummary;
    final canExpand = expandable;
    final String summary;
    if (widget.shadowedItemCount > 0 && widget.shadowedTokenCount > 0) {
      final tmpl = _t(context, 'message.compaction.completed');
      summary = formatCompactionCompleted(
        tmpl,
        widget.shadowedItemCount,
        widget.shadowedTokenCount,
      );
    } else if (widget.fallbackSummary != null) {
      summary = widget.fallbackSummary!;
    } else if (hasSummary) {
      summary = _t(context, 'message.compaction.expand');
    } else {
      summary = _t(context, 'message.compaction.unavailable');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: canExpand
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              borderRadius: BorderRadius.circular(6),
              hoverColor: widget.aliases.interactiveBgHover,
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.api_rounded,
                      size: 14,
                      color: widget.aliases.labelSecondary,
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: widget.aliases.labelSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.title ?? _t(context, 'message.compaction'),
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.aliases.labelPrimaryDimmed,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 2,
                      height: 2,
                      decoration: BoxDecoration(
                        color: widget.aliases.labelCaption,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summary,
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.aliases.labelTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded && hasSummary)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 4, 0, 4),
              child: DsMarkdown(data: widget.text, selectable: true),
            ),
        ],
      ),
    );
  }
}

final _imageBytesProvider =
    FutureProvider.family<Uint8List, ({String sessionId, String attachmentId})>(
      (ref, args) async {
        final client = ref.watch(connectionClientProvider);
        return client.readAttachment(
          SessionId(args.sessionId),
          args.attachmentId,
        );
      },
    );

/// User message image — loads durable attachment via `session.attachment` and
/// displays as 120×80 thumbnail with tap to lightbox. Mirrors React
/// `MessageImage` gallery (singleFit / tile) but simplified for the bubble:
/// a horizontal Wrap of thumbnails via `HistoricalImageCache`-equivalent
/// `ConnectionClient.readAttachment` loader. Uses a cached FutureProvider to
/// avoid blinking.
class _UserImage extends ConsumerWidget {
  const _UserImage({required this.sessionId, required this.attachmentId});

  final String sessionId;
  final String attachmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final async = ref.watch(
      _imageBytesProvider((sessionId: sessionId, attachmentId: attachmentId)),
    );
    return async.when(
      loading: () => Container(
        width: 120,
        height: 80,
        decoration: BoxDecoration(
          color: aliases.bgOverlay,
          borderRadius: BorderRadius.circular(DswTokens.radiusSm),
          border: Border.all(color: aliases.borderL1),
        ),
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => Container(
        width: 120,
        height: 80,
        decoration: BoxDecoration(
          color: aliases.bgOverlay,
          borderRadius: BorderRadius.circular(DswTokens.radiusSm),
          border: Border.all(color: aliases.borderL1),
        ),
        child: Icon(Icons.broken_image, size: 22, color: aliases.labelCaption),
      ),
      data: (bytes) => GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              children: [
                Center(child: Image.memory(bytes, fit: BoxFit.contain)),
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: Container(
          width: 120,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DswTokens.radiusSm),
            border: Border.all(color: aliases.borderL1),
          ),
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DswTokens.radiusSm),
            child: Image.memory(
              bytes,
              width: 120,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}
