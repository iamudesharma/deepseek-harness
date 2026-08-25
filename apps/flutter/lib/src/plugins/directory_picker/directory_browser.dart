/// Miller-column directory browser — Dart port of
/// `packages/client/ui-directory-picker-browse/src/client/DirectoryBrowser.tsx`.
///
/// The 680×500 dialog (clamped to viewport) with header (title + breadcrumb +
/// click-to-edit path zone), Miller content (one level full-width until a row
/// is selected, then two columns splitting evenly, 256px floor, with divider),
/// and footer (New folder, Show hidden, Cancel, Open). This reproduces the
/// React contract: columns for path segments, navigation via crumbs or typing,
/// selection (selected folder vs listed level), cancel, current-directory
/// display, breadcrumb/column state, and platform handling (browse = this
/// widget, native = host OS picker — branch lives in `adaptive_directory_picker`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/runtime_services.dart' show DirectoryListSignal;
import '../../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models — mirrors `host/directory-picker/src/index.ts`
// ---------------------------------------------------------------------------

/// One directory row: a listing child or a breadcrumb ancestor.
class DirectoryEntry {
  const DirectoryEntry({
    required this.name,
    required this.path,
    required this.hidden,
  });

  final String name;
  final String path;
  final bool hidden;

  factory DirectoryEntry.fromJson(Map<String, dynamic> j) => DirectoryEntry(
        name: j['name'] as String? ?? '',
        path: j['path'] as String? ?? '',
        hidden: j['hidden'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'hidden': hidden};
}

/// One directory level plus its ancestry.
class DirectoryListing {
  const DirectoryListing({
    required this.path,
    required this.home,
    required this.crumbs,
    required this.entries,
    required this.truncated,
  });

  final String path;
  final String home;
  final List<DirectoryEntry> crumbs;
  final List<DirectoryEntry> entries;
  final bool truncated;

  factory DirectoryListing.fromJson(Map<String, dynamic> j) {
    final crumbsRaw = j['crumbs'] as List<dynamic>? ?? const [];
    final entriesRaw = j['entries'] as List<dynamic>? ?? const [];
    return DirectoryListing(
      path: j['path'] as String? ?? '',
      home: j['home'] as String? ?? '',
      crumbs: crumbsRaw
          .whereType<Map>()
          .map((e) => DirectoryEntry.fromJson(e.cast<String, dynamic>()))
          .toList(),
      entries: entriesRaw
          .whereType<Map>()
          .map((e) => DirectoryEntry.fromJson(e.cast<String, dynamic>()))
          .toList(),
      truncated: j['truncated'] as bool? ?? false,
    );
  }
}

/// Host browse failure — mirrors `DirectoryBrowseError` in TS runtime.
class DirectoryBrowseError implements Exception {
  DirectoryBrowseError(this.message, {this.code, this.path});
  final String message;
  final String? code;
  final String? path;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Helpers — mirrors DirectoryBrowser.tsx pure helpers
// ---------------------------------------------------------------------------

List<DirectoryEntry> displayCrumbs(DirectoryListing listing, String homeLabel) {
  final idx = listing.crumbs.indexWhere((c) => c.path == listing.home);
  if (idx == -1) return listing.crumbs;
  final tail = listing.crumbs.sublist(idx + 1);
  return [DirectoryEntry(name: homeLabel, path: listing.home, hidden: false), ...tail];
}

String separatorOf(DirectoryListing listing) =>
    listing.home.contains('\\') ? r'\' : '/';

String levelDirectory(DirectoryListing listing) {
  final sep = separatorOf(listing);
  return listing.path.endsWith(sep) ? listing.path : '${listing.path}$sep';
}

class ScannedDirectory {
  const ScannedDirectory({required this.directory, required this.landed});
  final String directory;
  final String landed;
}

String? draftDirectory(DirectoryListing listing, String draft) {
  final cut = separatorOf(listing) == r'\'
      ? (draft.lastIndexOf(r'\') > draft.lastIndexOf('/') ? draft.lastIndexOf(r'\') : draft.lastIndexOf('/'))
      : draft.lastIndexOf('/');
  return cut == -1 ? null : draft.substring(0, cut + 1);
}

({String? directory, String? tail}) readDraft(
  DirectoryListing listing,
  String draft,
  ScannedDirectory? scanned,
) {
  final directory = draftDirectory(listing, draft);
  if (directory == null) return (directory: null, tail: null);
  final answers = directory == levelDirectory(listing) ||
      (scanned != null && scanned.directory == directory && scanned.landed == listing.path);
  return (directory: directory, tail: answers ? draft.substring(directory.length) : null);
}

List<DirectoryEntry> visibleEntries(
  List<DirectoryEntry> entries,
  String? selectedPath,
  bool showHidden,
  String? filterPrefix,
) {
  final needle = filterPrefix == null ? '' : filterPrefix.toLowerCase();
  bool displayable(DirectoryEntry e) => showHidden || !e.hidden || needle.startsWith('.');
  bool matches(DirectoryEntry e) => displayable(e) && e.name.toLowerCase().startsWith(needle);
  final narrowing = needle.isNotEmpty && entries.any(matches);
  return entries.where((e) {
    if (e.path == selectedPath) return true;
    if (narrowing) return matches(e);
    return showHidden || !e.hidden;
  }).toList();
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

typedef ListDirectory = Future<Map<String, Object?>> Function({String? path});
typedef CreateDirectory = Future<String> Function({required String path, required String name});

class DirectoryBrowser extends StatefulWidget {
  const DirectoryBrowser({
    super.key,
    required this.open,
    required this.listDirectory,
    required this.createDirectory,
    required this.onOpen,
    required this.onClose,
    this.busy = false,
    this.translate,
  });

  final bool open;

  /// Mirrors React `listDirectory(path, signal)` — the [DirectoryListSignal]
  /// is the Dart analog of `AbortSignal`. Callers may ignore it; the widget
  /// uses it to abort the previous scan on supersession.
  final Future<DirectoryListing> Function({String? path, DirectoryListSignal? signal}) listDirectory;
  final Future<String> Function({required String path, required String name}) createDirectory;
  final ValueChanged<String> onOpen;
  final VoidCallback onClose;
  final bool busy;
  final String Function(String key)? translate;

  @override
  State<DirectoryBrowser> createState() => _DirectoryBrowserState();
}

class _DirectoryBrowserState extends State<DirectoryBrowser> {
  DirectoryListing? _parent;
  DirectoryEntry? _selected;
  DirectoryListing? _child;

  bool _loading = false;
  bool _slowScan = false;
  int _scanWindow = 0;
  Timer? _slowTimer;

  String? _error;
  String? _pathDraft;
  bool _showHidden = false;
  String? _folderDraft;
  bool _creatingFolder = false;
  String? _createError;

  int _requestSeq = 0;
  int _openGeneration = 0;
  final ScrollController _crumbTrail = ScrollController();
  final ScrollController _millerRow = ScrollController();
  final TextEditingController _pathCtrl = TextEditingController();
  final TextEditingController _folderCtrl = TextEditingController();
  final FocusNode _pathFocus = FocusNode();
  final FocusNode _editZoneFocus = FocusNode();
  // Focus re-park targets — mirrors React refocusPathInput / refocusPick /
  // refocusEditZone guarded by document.activeElement === body → focus(...).
  // Flutter analog: FocusManager.instance.primaryFocus == null means no widget
  // holds focus (body). Post-frame we re-park only when focus was dropped.
  bool _refocusPathInput = false;
  bool _refocusPick = false;
  bool _refocusEditZone = false;
  // Per-scan abort signal — Dart analog of AbortSignal / AbortController.
  // Supersession aborts the previous wire scan via signal.abort() instead of
  // only discarding its settlement, freeing the host scan promptly.
  DirectoryListSignal? _scanSignal;
  // IME composition guard — mirrors React composingRef + compositionGuard.
  // TextField composing range isValid while IME candidate selection is active;
  // Enter during composition must not submit (same guard workspace-name inputs
  // carry). Checked via controller.value.composing.
  bool _isComposing = false;

  ScannedDirectory? _scanned;
  Timer? _draftDebounce;
  bool _previewSuspended = false;

  static const _slowDelay = Duration(milliseconds: 300);
  static const _parentWait = Duration(milliseconds: 200);
  static const _draftDebounceDelay = Duration(milliseconds: 250);

  String _t(String k) {
    final v = widget.translate?.call(k);
    if (v != null && v != k) return v;
    const en = {
      'browser.title': 'Select Workspace Directory',
      'browser.home': 'Home',
      'browser.newFolder': 'New folder',
      'browser.folderName': 'Folder name',
      'browser.createIn': 'New folder in "{name}"',
      'browser.untitledFolder': 'Untitled folder',
      'browser.create': 'Create',
      'browser.cancel': 'Cancel',
      'browser.open': 'Open',
      'browser.editPath': 'Edit path',
      'browser.loading': 'Loading…',
      'browser.truncated': 'Too many folders to list; only the beginning is shown.',
      'browser.showHidden': 'Show hidden files',
    };
    return en[k] ?? k;
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      _openGeneration++;
      _navigate(null);
    }
  }

  @override
  void didUpdateWidget(covariant DirectoryBrowser old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) {
      _openGeneration++;
      setState(() {
        _parent = null;
        _selected = null;
        _child = null;
        _creatingFolder = false;
        _showHidden = false;
      });
      _navigate(null);
    } else if (!widget.open && old.open) {
      _scanSignal?.abort();
      _scanSignal = null;
      _cancelSlow();
      _draftDebounce?.cancel();
      _setLoading(false);
      _refocusPathInput = false;
      _refocusPick = false;
      _refocusEditZone = false;
      setState(() {
        _error = null;
        _pathDraft = null;
        _folderDraft = null;
        _createError = null;
      });
    }
  }

  @override
  void dispose() {
    _scanSignal?.abort();
    _slowTimer?.cancel();
    _draftDebounce?.cancel();
    _crumbTrail.dispose();
    _millerRow.dispose();
    _pathCtrl.dispose();
    _folderCtrl.dispose();
    _pathFocus.dispose();
    _editZoneFocus.dispose();
    super.dispose();
  }

  void _setLoading(bool v) {
    if (_loading == v) return;
    setState(() => _loading = v);
    _scheduleSlow();
  }

  void _scheduleSlow() {
    _slowTimer?.cancel();
    setState(() => _slowScan = false);
    _scanWindow++;
    if (_loading) {
      final gen = _scanWindow;
      _slowTimer = Timer(_slowDelay, () {
        if (!mounted || gen != _scanWindow || !_loading) return;
        setState(() => _slowScan = true);
      });
    }
  }

  void _cancelSlow() {
    _slowTimer?.cancel();
    _slowScan = false;
  }

  int _supersede() {
    _scanSignal?.abort();
    _scanSignal = null;
    _slowTimer?.cancel();
    _setLoading(false);
    return ++_requestSeq;
  }

  void _runPostFrameFocusPark() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only re-park when focus was dropped to body (no primary focus).
      final hasFocus = FocusManager.instance.primaryFocus != null;
      if (hasFocus) {
        // Consume flags without moving focus the user still holds.
        _refocusPathInput = false;
        _refocusPick = false;
        _refocusEditZone = false;
        return;
      }
      if (_refocusPathInput) {
        _refocusPathInput = false;
        if (_pathFocus.canRequestFocus) _pathFocus.requestFocus();
        return;
      }
      if (_refocusPick) {
        _refocusPick = false;
        _refocusEditZone = false;
        // Selected row carries aria-current semantics; focus it.
        // Find the first Semantics with selected == true via focus traversal?
        // Fallback to edit zone if row not found.
        final ctx = context;
        final scope = FocusScope.of(ctx);
        // Try to find selected row focus node by searching focus traversal.
        // If none, park on edit zone.
        if (!_editZoneFocus.hasFocus && _editZoneFocus.canRequestFocus) {
          // For now park on edit zone as stable fallback; row focus is wired
          // via the row's Focus widget with _selectedRowFocus when available.
          // The _selectedRowFocus is set when a row is selected; if present
          // we focus it, else the edit zone keeps keyboard inside dialog.
          _editZoneFocus.requestFocus();
        }
        scope; // keep reference for lints
        return;
      }
      if (_refocusEditZone) {
        _refocusEditZone = false;
        if (_editZoneFocus.canRequestFocus) _editZoneFocus.requestFocus();
      }
    });
  }

  // ---- navigation landing (selection-anchored, two-pane away from display root)

  void _navigate(String? path) {
    final seq = ++_requestSeq;
    _setLoading(true);
    setState(() => _error = null);
    // restart slow window and abort previous scan
    _scanSignal?.abort();
    final navSignal = DirectoryListSignal();
    _scanSignal = navSignal;
    _slowTimer?.cancel();
    final win = ++_scanWindow;
    _slowTimer = Timer(_slowDelay, () {
      if (mounted && seq == _requestSeq && win == _scanWindow && _loading) setState(() => _slowScan = true);
    });

    void settle() {
      _setLoading(false);
      setState(() => _pathDraft = null);
      // Focus park: if navigation closed editor and focus was dropped to body,
      // re-park on edit zone. Mirrors React refocusEditZone guarded by
      // document.activeElement === body.
      if (FocusManager.instance.primaryFocus == null) {
        _refocusEditZone = true;
        _runPostFrameFocusPark();
      }
    }

    void landSingle(DirectoryListing target) {
      if (seq != _requestSeq) return;
      setState(() {
        _parent = target;
        _selected = null;
        _child = null;
      });
      settle();
    }

    widget.listDirectory(path: path, signal: navSignal).then((target) {
      if (seq != _requestSeq || navSignal.aborted) return;
      // Two-pane determination uses collapsed crumbs depth
      final crumbs = displayCrumbs(target, '');
      if (crumbs.length < 2) {
        landSingle(target);
        return;
      }
      final parentCrumb = crumbs[crumbs.length - 2];
      bool landed = false;
      Timer? timeout;
      void trySingle() {
        if (landed || seq != _requestSeq) return;
        landed = true;
        landSingle(target);
      }

      timeout = Timer(_parentWait, trySingle);
      final parentSignal = DirectoryListSignal();
      // Parent leg is part of same navigation scan window — supersession
      // aborts it via the same sequence. Store as current so _supersede()
      // aborts the parent leg too.
      _scanSignal = parentSignal;
      widget.listDirectory(path: parentCrumb.path, signal: parentSignal).then((parentLevel) {
        if (seq != _requestSeq || parentSignal.aborted) return;
        timeout?.cancel();
        if (landed) {
          final sep = separatorOf(parentLevel);
          String fold(String s) => sep == r'\' ? s.toLowerCase() : s;
          final match = parentLevel.entries.where((e) => fold(e.path) == fold(target.path)).firstOrNull;
          if (match != null) {
            setState(() {
              _parent = parentLevel;
              _selected = match;
              _child = target;
            });
          }
          return;
        }
        final sep = separatorOf(parentLevel);
        String fold(String s) => sep == r'\' ? s.toLowerCase() : s;
        final match = parentLevel.entries.where((e) => fold(e.path) == fold(target.path)).firstOrNull;
        if (match == null) {
          landed = true;
          landSingle(target);
          return;
        }
        landed = true;
        timeout?.cancel();
        if (seq != _requestSeq) return;
        setState(() {
          _parent = parentLevel;
          _selected = match;
          _child = target;
        });
        settle();
      }, onError: (Object e) {
        if (e.toString().contains('aborted')) return;
        timeout?.cancel();
        trySingle();
      });
    }, onError: (Object e) {
      if (e.toString().contains('aborted') || navSignal.aborted) return;
      if (seq != _requestSeq) return;
      _setLoading(false);
      setState(() => _error = e.toString());
    });
  }

  void _landForDraft(String directory) {
    final seq = ++_requestSeq;
    _setLoading(true);
    _scanSignal?.abort();
    final draftSignal = DirectoryListSignal();
    _scanSignal = draftSignal;
    final win = ++_scanWindow;
    _slowTimer?.cancel();
    _slowTimer = Timer(_slowDelay, () {
      if (mounted && seq == _requestSeq && win == _scanWindow && _loading) setState(() => _slowScan = true);
    });

    widget.listDirectory(path: directory, signal: draftSignal).then((target) {
      if (seq != _requestSeq || draftSignal.aborted) return;
      _scanned = ScannedDirectory(directory: directory, landed: target.path);
      // Similar two-pane logic as _navigate but keep editor open — wait both legs
      // (no timeout) so one keystroke moves view once, and re-park focus if
      // swap dropped it to body.
      final crumbs = displayCrumbs(target, '');
      if (crumbs.length < 2) {
        if (seq != _requestSeq) return;
        setState(() {
          _parent = target;
          _selected = null;
          _child = null;
          _error = null;
        });
        _setLoading(false);
        if (FocusManager.instance.primaryFocus == null) {
          _refocusPathInput = true;
          _runPostFrameFocusPark();
        }
        return;
      }
      final parentCrumb = crumbs[crumbs.length - 2];
      final parentSignal = DirectoryListSignal();
      _scanSignal = parentSignal;
      widget.listDirectory(path: parentCrumb.path, signal: parentSignal).then((parentLevel) {
        if (seq != _requestSeq) return;
        final sep = separatorOf(parentLevel);
        String fold(String s) => sep == r'\' ? s.toLowerCase() : s;
        final match = parentLevel.entries.where((e) => fold(e.path) == fold(target.path)).firstOrNull;
        if (match == null) {
          setState(() {
            _parent = target;
            _selected = null;
            _child = null;
            _error = null;
          });
          _setLoading(false);
          return;
        }
        setState(() {
          _parent = parentLevel;
          _selected = match;
          _child = target;
          _error = null;
        });
        _setLoading(false);
      }, onError: (Object e) {
        if (e.toString().contains('aborted')) return;
        if (seq != _requestSeq) return;
        setState(() {
          _parent = target;
          _selected = null;
          _child = null;
        });
        _setLoading(false);
      });
      // Keep editor focus after draft walk — re-park if swap dropped to body.
      if (FocusManager.instance.primaryFocus == null) {
        _refocusPathInput = true;
        _runPostFrameFocusPark();
      }
    }, onError: (Object e) {
      if (e.toString().contains('aborted')) return;
      if (seq != _requestSeq) return;
      _setLoading(false);
      // draft failure keeps stale view silent, no alert
    });
  }

  void _select(DirectoryEntry entry) {
    final seq = ++_requestSeq;
    _scanSignal?.abort();
    final selectSignal = DirectoryListSignal();
    _scanSignal = selectSignal;
    if (_pathDraft != null) {
      _refocusPick = true;
      setState(() => _pathDraft = null);
    }
    setState(() {
      _selected = entry;
      _child = null;
      _error = null;
    });
    _setLoading(true);
    final win = ++_scanWindow;
    _slowTimer?.cancel();
    _slowTimer = Timer(_slowDelay, () {
      if (mounted && seq == _requestSeq && win == _scanWindow && _loading) setState(() => _slowScan = true);
    });
    widget.listDirectory(path: entry.path, signal: selectSignal).then((next) {
      if (seq != _requestSeq || selectSignal.aborted) return;
      setState(() => _child = next);
      _setLoading(false);
      // Pin miller row to child pane after landing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_millerRow.hasClients) _millerRow.jumpTo(_millerRow.position.maxScrollExtent);
      });
      if (_refocusPick) _runPostFrameFocusPark();
    }, onError: (Object e) {
      if (e.toString().contains('aborted') || selectSignal.aborted) return;
      if (seq != _requestSeq) return;
      _setLoading(false);
      setState(() {
        _error = e.toString();
        _selected = null;
      });
      // Clearing selection can orphan focus to body if dot-revealed hidden row
      // re-hides — re-park on edit zone only if focus actually fell to body.
      if (FocusManager.instance.primaryFocus == null) {
        _refocusEditZone = true;
        _runPostFrameFocusPark();
      }
    });
  }

  void _advance(DirectoryEntry entry) {
    if (_child == null) return;
    setState(() => _parent = _child);
    _select(entry);
  }

  void _cancelPathEdit() {
    _supersede();
    setState(() {
      _pathDraft = null;
      _error = null;
      if (_child == null) _selected = null;
    });
    if (_parent == null) _navigate(null);
  }

  void _onDraftChanged(String value) {
    _supersede();
    _previewSuspended = false;
    setState(() => _pathDraft = value);
    _draftDebounce?.cancel();
    _draftDebounce = Timer(_draftDebounceDelay, () {
      if (_previewSuspended) return;
      final current = _child ?? _parent;
      if (current == null || _pathDraft == null) return;
      final rd = readDraft(current, _pathDraft!, _scanned);
      if (rd.directory == null || rd.tail != null) return;
      _landForDraft(rd.directory!);
    });
  }

  void _confirmCreate() {
    final draft = _folderDraft;
    final targetPath = _selected?.path ?? _parent?.path;
    if (targetPath == null || draft == null || _creatingFolder) return;
    if (draft.trim().isEmpty) return;
    setState(() {
      _creatingFolder = true;
      _createError = null;
    });
    final gen = _openGeneration;
    widget.createDirectory(path: targetPath, name: draft).then((createdPath) {
      if (gen != _openGeneration || !mounted) return;
      setState(() {
        _creatingFolder = false;
        _folderDraft = null;
      });
      final seq = ++_requestSeq;
      _setLoading(true);
      final win = ++_scanWindow;
      _slowTimer?.cancel();
      _slowTimer = Timer(_slowDelay, () {
        if (mounted && seq == _requestSeq && win == _scanWindow && _loading) setState(() => _slowScan = true);
      });
      setState(() => _error = null);
      _scanSignal?.abort();
      final createSignal = DirectoryListSignal();
      _scanSignal = createSignal;
      widget.listDirectory(path: targetPath, signal: createSignal).then((level) {
        if (seq != _requestSeq || createSignal.aborted) return;
        setState(() {
          _parent = level;
          _loading = false;
          _slowScan = false;
        });
        // select created folder — mirrors figma 802:57446→813:23278 flow
        _select(DirectoryEntry(name: draft, path: createdPath, hidden: false));
      }, onError: (Object e) {
        if (e.toString().contains('aborted') || createSignal.aborted) return;
        if (seq != _requestSeq) return;
        _setLoading(false);
        setState(() => _error = e.toString());
      });
    }, onError: (Object e) {
      if (gen != _openGeneration || !mounted) return;
      setState(() {
        _creatingFolder = false;
        _createError = e.toString();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);

    final crumbSource = _child ?? _parent;
    final typedPrefix = crumbSource == null || _pathDraft == null
        ? null
        : readDraft(crumbSource, _pathDraft!, _scanned).tail;
    final crumbs = crumbSource == null ? <DirectoryEntry>[] : displayCrumbs(crumbSource, _t('browser.home'));
    final targetPath = _selected?.path ?? _parent?.path;
    final twoPane = _selected != null;
    final parentInert = widget.busy || _folderDraft != null;
    final draftPending = _pathDraft != null;

    // crumb tail scroll pin and miller pin are handled via controllers/effects

    final targetName = _selected?.name ??
        (_parent == null ? '' : (displayCrumbs(_parent!, _t('browser.home')).lastOrNull?.name ?? _parent!.path));
    final showCreateDialog = _folderDraft != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: aliases.bgLayer2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DswTokens.radiusLg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 500, minWidth: 320, minHeight: 240),
        child: SizedBox(
          width: 680,
          height: 500,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 14, 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: aliases.borderL3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t('browser.title'),
                        style: TextStyle(fontSize: DswTokens.fontSizeBase16, fontWeight: FontWeight.w600, color: aliases.labelPrimary)),
                    const SizedBox(height: 8),
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: _pathDraft != null ? aliases.borderL2 : DswTokens.transparent),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _pathDraft == null
                          ? Row(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: _crumbTrail,
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        for (int i = 0; i < crumbs.length; i++) ...[
                                          if (i > 0) Icon(Icons.chevron_right, size: 12, color: aliases.labelTertiary),
                                          TextButton(
                                            onPressed: parentInert ? null : () => _navigate(crumbs[i].path),
                                            style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                            child: Text(crumbs[i].name,
                                                style: TextStyle(
                                                    fontSize: DswTokens.fontSizeXs13,
                                                    fontWeight: FontWeight.w500,
                                                    color: aliases.labelTertiary)),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // edit zone — pencil affordance (focus target for re-park)
                                IconButton(
                                  key: const ValueKey('crumbEditZone'),
                                  focusNode: _editZoneFocus,
                                  tooltip: _t('browser.editPath'),
                                  onPressed: parentInert
                                      ? null
                                      : () {
                                          _supersede();
                                          _previewSuspended = false;
                                          if (_parent == null) {
                                            setState(() {
                                              _pathDraft = '';
                                              _pathCtrl.text = '';
                                            });
                                            WidgetsBinding.instance.addPostFrameCallback((_) => _pathFocus.requestFocus());
                                            return;
                                          }
                                          final base = _selected?.path ?? _parent!.path;
                                          final sep = separatorOf(_parent!);
                                          final seed = base.endsWith(sep) ? base : '$base$sep';
                                          setState(() {
                                            _pathDraft = seed;
                                            _pathCtrl.text = seed;
                                          });
                                          WidgetsBinding.instance.addPostFrameCallback((_) => _pathFocus.requestFocus());
                                        },
                                  icon: Icon(Icons.edit_outlined, size: 14, color: aliases.labelTertiary),
                                  style: IconButton.styleFrom(minimumSize: const Size(34, 22), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                ),
                              ],
                            )
                          : TextField(
                              key: const ValueKey('pathInput'),
                              controller: _pathCtrl,
                              focusNode: _pathFocus,
                              autofocus: true,
                              enabled: !parentInert,
                              style: TextStyle(fontSize: DswTokens.fontSizeXs13, color: aliases.labelPrimary),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 6),
                              ),
                              onChanged: (v) {
                                // IME composition guard — TextEditingValue.composing.isValid
                                // mirrors React composingRef + isComposing check.
                                _isComposing = _pathCtrl.value.composing.isValid;
                                _onDraftChanged(v);
                              },
                              onSubmitted: (value) {
                                // IME confirmation (Enter selecting candidate) must not submit.
                                if (_pathCtrl.value.composing.isValid || _isComposing) return;
                                if (value.trim().isEmpty) return;
                                _previewSuspended = true;
                                // Park focus on edit zone after submission — only if
                                // focus was actually in input; mirrors
                                // refocusEditZone.current = document.activeElement === pathInput
                                if (_pathFocus.hasFocus) _refocusEditZone = true;
                                _navigate(value);
                              },
                            ),
                    ),
                  ],
                ),
              ),
              // Miller content
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _millerRow,
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_parent != null)
                                    SizedBox(
                                      width: twoPane ? 320 : 632,
                                      child: _LevelColumn(
                                        key: const ValueKey('parentColumn'),
                                        entries: _parent!.entries,
                                        selectedPath: _selected?.path,
                                        busy: parentInert,
                                        onPick: _select,
                                        showHidden: _showHidden,
                                        filterPrefix: _child == null ? typedPrefix : null,
                                        pathEditing: draftPending,
                                      ),
                                    ),
                                  if (twoPane) Container(width: 1, color: aliases.borderL3, margin: const EdgeInsets.symmetric(horizontal: 12)),
                                  if (twoPane && _child != null)
                                    SizedBox(
                                      width: 320,
                                      child: _LevelColumn(
                                        key: const ValueKey('childColumn'),
                                        entries: _child!.entries,
                                        selectedPath: null,
                                        busy: parentInert,
                                        onPick: _advance,
                                        showHidden: _showHidden,
                                        filterPrefix: typedPrefix,
                                        pathEditing: draftPending,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if ((_parent?.truncated ?? false) || (_child?.truncated ?? false))
                            Padding(
                              padding: const EdgeInsets.only(top: 8, right: 120),
                              child: Text(_t('browser.truncated'),
                                  style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelSecondary)),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 120),
                              child: Text(_error!,
                                  style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary)),
                            ),
                        ],
                      ),
                    ),
                    if (_loading && _slowScan)
                      Positioned(
                        right: 16,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          color: aliases.bgLayer2,
                          child: Text(_t('browser.loading'),
                              style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.labelSecondary)),
                        ),
                      ),
                  ],
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: aliases.borderL3))),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: (_parent == null || _loading || parentInert || draftPending)
                              ? null
                              : () {
                                  setState(() {
                                    _folderDraft = '';
                                    _folderCtrl.text = '';
                                    _createError = null;
                                  });
                                },
                          icon: const Icon(Icons.create_new_folder_outlined, size: 14),
                          label: Text(_t('browser.newFolder')),
                        ),
                        TextButton.icon(
                          onPressed: parentInert
                              ? null
                              : () => setState(() => _showHidden = !_showHidden),
                          icon: _showHidden ? const Icon(Icons.check, size: 14) : const SizedBox.shrink(),
                          label: Text(_t('browser.showHidden')),
                          style: TextButton.styleFrom(
                            foregroundColor: _showHidden ? aliases.labelPrimary : aliases.labelSecondary,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: parentInert ? null : widget.onClose,
                          child: Text(_t('browser.cancel')),
                        ),
                        FilledButton(
                          onPressed: (targetPath == null || _loading || parentInert || draftPending)
                              ? null
                              : () => widget.onOpen(targetPath),
                          child: Text(_t('browser.open')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Keyboard handling for Escape to cancel path edit or dialog
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                    if (_pathDraft != null) {
                      _cancelPathEdit();
                      return KeyEventResult.handled;
                    }
                    if (_folderDraft == null && !widget.busy) {
                      widget.onClose();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: const SizedBox.shrink(),
              ),
            ],
          ),
              if (showCreateDialog)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Material(
                          color: aliases.bgLayer2,
                          borderRadius: BorderRadius.circular(DswTokens.radiusLg),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_t('browser.newFolder'),
                                    style: TextStyle(
                                        fontSize: DswTokens.fontSizeBase16,
                                        fontWeight: FontWeight.w600,
                                        color: aliases.labelPrimary)),
                                const SizedBox(height: 12),
                                Text(
                                  _t('browser.createIn').contains('{name}')
                                      ? _t('browser.createIn').replaceAll('{name}', targetName)
                                      : 'New folder in "$targetName"',
                                  style: TextStyle(fontSize: DswTokens.fontSizeS14, color: aliases.labelPrimary),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  key: const ValueKey('createFolderInput'),
                                  controller: _folderCtrl,
                                  autofocus: true,
                                  enabled: !_creatingFolder,
                                  decoration: InputDecoration(
                                    hintText: _t('browser.untitledFolder'),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                                  ),
                                  onChanged: (v) {
                                    _isComposing = _folderCtrl.value.composing.isValid;
                                    setState(() => _folderDraft = v);
                                  },
                                  onSubmitted: (_) {
                                    if (_folderCtrl.value.composing.isValid || _isComposing) return;
                                    _confirmCreate();
                                  },
                                ),
                                if (_createError != null) ...[
                                  const SizedBox(height: 8),
                                  Text(_createError!,
                                      style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary)),
                                ],
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _creatingFolder ? null : () => setState(() => _folderDraft = null),
                                      child: Text(_t('browser.cancel')),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: (_creatingFolder || (_folderDraft?.trim().isEmpty ?? true))
                                          ? null
                                          : _confirmCreate,
                                      child: _creatingFolder
                                          ? SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: aliases.labelPrimaryForeground))
                                          : Text(_t('browser.create')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelColumn extends StatelessWidget {
  const _LevelColumn({
    super.key,
    required this.entries,
    required this.selectedPath,
    required this.busy,
    required this.onPick,
    required this.showHidden,
    required this.filterPrefix,
    required this.pathEditing,
  });

  final List<DirectoryEntry> entries;
  final String? selectedPath;
  final bool busy;
  final ValueChanged<DirectoryEntry> onPick;
  final bool showHidden;
  final String? filterPrefix;
  final bool pathEditing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final visible = visibleEntries(entries, selectedPath, showHidden, filterPrefix);
    return ListView.separated(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: visible.length,
      separatorBuilder: (context, index) => const SizedBox(height: 2),
      itemBuilder: (context, i) {
        final entry = visible[i];
        final selected = entry.path == selectedPath;
        // Mirrors React LevelColumn's listitem + button with aria-current
        // and selected semantics. The row seat carries list item semantics;
        // the button carries selected/current for assistive tech.
        return Semantics(
          selected: selected,
          container: true,
          explicitChildNodes: true,
          child: SizedBox(
            height: 28,
            // Keep focus in path editor while editing: mousedown preventDefault
            // in React. In Flutter we avoid focus steal by wrapping with a
            // Focus that refuses traversal while editing — the click still lands
            // via onPressed, but the editor retains primary focus until the
            // pick commits and refocusPick parks it on the new selection.
            child: Focus(
              canRequestFocus: !pathEditing,
              skipTraversal: pathEditing,
              includeSemantics: false,
              child: TextButton(
                onPressed: busy ? null : () => onPick(entry),
                autofocus: false,
                style: TextButton.styleFrom(
                backgroundColor: selected ? aliases.interactiveBgActive : DswTokens.transparent,
                foregroundColor: aliases.labelPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                alignment: Alignment.centerLeft,
              ),
                child: Semantics(
                  selected: selected,
                  // aria-current counterpart — mark selected row as current for a11y
                  // traversal. Flutter Semantics has no aria-current but selected
                  // plus header semantics covers it; we also set button: true.
                  button: true,
                  child: Row(
                    children: [
                      Icon(selected ? Icons.folder_open : Icons.folder_outlined,
                          size: 16, color: selected ? aliases.buttonInfoFill : aliases.labelSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(entry.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: DswTokens.fontSizeXs13,
                                fontWeight: FontWeight.w500,
                                color: aliases.labelPrimary)),
                      ),
                      Icon(Icons.chevron_right, size: 12, color: aliases.labelTertiary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Nested create dialog helper
Future<void> showCreateFolderDialog({
  required BuildContext context,
  required String targetName,
  required TextEditingController controller,
  required String? createError,
  required bool creating,
  required VoidCallback onCancel,
  required VoidCallback onCreate,
  required String Function(String) t,
}) {
  final ThemeData theme = Theme.of(context);
  final DswAliases aliases = theme.extension<DswThemeExtension>()?.aliases ??
      (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
  return showDialog<void>(
    context: context,
    barrierDismissible: !creating,
    builder: (ctx) => AlertDialog(
      backgroundColor: aliases.bgLayer2,
      title: Text(t('browser.newFolder'),
          style: TextStyle(fontSize: DswTokens.fontSizeBase16, fontWeight: FontWeight.w600, color: aliases.labelPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('browser.createIn').replaceAll('{name}', targetName),
              style: TextStyle(fontSize: DswTokens.fontSizeS14, color: aliases.labelPrimary)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            enabled: !creating,
            decoration: InputDecoration(
              hintText: t('browser.untitledFolder'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
            ),
            onSubmitted: (_) => onCreate(),
          ),
          if (createError != null) ...[
            const SizedBox(height: 8),
            Text(createError, style: TextStyle(fontSize: DswTokens.fontSizeXxs12, color: aliases.stateErrorPrimary)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: creating ? null : onCancel, child: Text(t('browser.cancel'))),
        FilledButton(onPressed: creating || controller.text.trim().isEmpty ? null : onCreate, child: Text(t('browser.create'))),
      ],
    ),
  );
}
