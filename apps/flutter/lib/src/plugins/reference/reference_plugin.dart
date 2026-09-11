/// The `ui-reference` plugin — Flutter port of
/// `packages/client/ui-reference/src/client/index.ts`: the combined `@file` /
/// `@session` trigger source registered into the input-trigger registry.
///
/// Candidate discovery runs the two gateway namespaces in parallel
/// (`fileReferences.list`, `sessionReferenceResolver.candidates`); a failing
/// or absent namespace degrades to an empty list — the React contract
/// (`result.ok ? result.value : []`), never a menu error tier. Picks follow
/// the React decision table: directories splice literal text and keep
/// completion open; files and sessions insert reference chips.
library;

import 'dart:async';
import 'dart:convert';


import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../input_trigger/input_trigger_service.dart';
import '../input_trigger/trigger_source.dart';

/// Plugin identity.
const String kReferencePluginId = 'ui-reference';

/// The slash source's group name (React `name: 'reference'`).
const String kReferenceSourceName = 'reference';

/// Opaque candidate payload discriminating file vs session picks.
class _CandidateValue {
  const _CandidateValue._(this.kind, this.fileKind, this.label, this.mention);

  final String kind;
  final String? fileKind;
  final String label;
  final String mention;

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (fileKind != null) 'fileKind': fileKind,
    'label': label,
    'mention': mention,
  };

  static _CandidateValue? parse(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final kind = decoded['kind'];
      final label = decoded['label'];
      final mention = decoded['mention'];
      if (kind is! String || label is! String || mention is! String)
        return null;
      return _CandidateValue._(
        kind,
        decoded['fileKind'] is String ? decoded['fileKind'] as String : null,
        label,
        mention,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Formats a selected path as prompt text (port of
/// `dsh-file-reference/grammar.ts:formatFileMention`). Whitespace uses the
/// quoted `@"path"` grammar; a quoted directory keeps that quote open after
/// its trailing slash so completion can descend another level. Null for a path
/// the editor grammar cannot represent safely.
String? formatFileMention({
  required String path,
  required bool directory,
  required bool preserveQuote,
}) {
  final full = directory ? '$path/' : path;
  // React: /[\u0000-\u001f\u007f-\u009f"]/u  — double quote is unsafe inside
  // the @"..." grammar and must be rejected, not escaped.
  if (RegExp(r'[\u0000-\u001f\u007f-\u009f"]', unicode: true).hasMatch(full)) {
    return null;
  }
  final quoted = preserveQuote || RegExp(r'\s', unicode: true).hasMatch(full);
  if (!quoted) return '@$full';
  return directory ? '@"$full' : '@"$full"';
}

/// The `ui-reference` plugin.
class ReferencePlugin extends DshPlugin {
  /// Creates the plugin over injected fetchers (tests stub these; defaults
  /// call the two gateway namespaces through the connection client).
  const ReferencePlugin({this.fetchFiles, this.fetchSessions});

  /// `fileReferences.list` slice: path rows with kind + label source.
  final Future<List<Map<String, Object?>>> Function(
    String sessionId,
    String query,
  )?
  fetchFiles;

  /// `sessionReferenceResolver.candidates` slice.
  final Future<List<Map<String, Object?>>> Function(
    String sessionId,
    String query,
  )?
  fetchSessions;

  @override
  String get id => kReferencePluginId;

  @override
  List<String> get inject => ['slots', 'connection', 'inputTriggers'];

  @override
  Future<void> apply(DshContext ctx) async {
    final client = ctx.require<ConnectionClient>('connection');
    final registry = ctx.require<TriggerSourceRegistry>('inputTriggers');

    // The wire mapping only; namespace failures degrade at the source call
    // site (the React `result.ok ? result.value : []` contract), so injected
    // and default fetchers behave identically. Host methods are slash-form
    // (`fileReferences/list`, `sessionReferenceResolver/candidates`) with a
    // single `args` object containing `agentId`.
    Future<List<Map<String, Object?>>> defaultFiles(
      String sessionId,
      String query,
    ) async {
      final value = await client.callMethod('fileReferences/list', {
        'agentId': sessionId,
        'query': query,
      });
      // Host returns a top-level array (value is `FileReference[]`) which the
      // gateway wraps as `{'_list': [...]}`; legacy test fakes return
      // `{'candidates': [...]}`.
      final raw = value['_list'] ?? value['candidates'] ?? value['items'];
      if (raw is List)
        return raw
            .whereType<Map>()
            .map((e) => e.cast<String, Object?>())
            .toList();
      // Direct array wrapper from the gateway.
      if (value['_list'] case final List list) {
        return list
            .whereType<Map>()
            .map((e) => e.cast<String, Object?>())
            .toList();
      }
      // Fallback: the map's values may already be the list entries (array-as-map).
      return const [];
    }

    Future<List<Map<String, Object?>>> defaultSessions(
      String sessionId,
      String query,
    ) async {
      final value = await client.callMethod(
        'sessionReferenceResolver/candidates',
        {
          'agentId': sessionId,
          'query': query,
        },
      );
      final raw = value['_list'] ?? value['candidates'] ?? value['items'];
      if (raw is List)
        return raw
            .whereType<Map>()
            .map((e) => e.cast<String, Object?>())
            .toList();
      if (value['_list'] case final List list) {
        return list
            .whereType<Map>()
            .map((e) => e.cast<String, Object?>())
            .toList();
      }
      return const [];
    }

    final disposeSource = registry.registerSource(
      _ReferenceSource(
        fetchFiles: fetchFiles ?? defaultFiles,
        fetchSessions: fetchSessions ?? defaultSessions,
      ),
    );
    ctx.onDispose(disposeSource);
  }
}

class _ReferenceSource extends InputTriggerSource {
  _ReferenceSource({required this.fetchFiles, required this.fetchSessions});

  final Future<List<Map<String, Object?>>> Function(String, String) fetchFiles;
  final Future<List<Map<String, Object?>>> Function(String, String)
  fetchSessions;

  @override
  TriggerChar get trigger => '@';

  @override
  String get name => kReferenceSourceName;

  @override
  bool get showGroupTitle => false;

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) async {
    // A failing or absent namespace degrades to an empty list — the React
    // contract (`result.ok ? result.value : []`), never a menu error tier.
    Future<List<Map<String, Object?>>> degraded(
      Future<List<Map<String, Object?>>> call,
    ) async {
      try {
        return await call;
      } catch (_) {
        // Absent/failing namespace degrades; the menu never errors.
        return const [];
      }
    }

    final files = degraded(fetchFiles(sessionId, request.query));
    // Sessions never answer inside an open quoted path token.
    final sessions = request.quoted
        ? Future<List<Map<String, Object?>>>.value(const [])
        : degraded(fetchSessions(sessionId, request.query));
    final results = await Future.wait([files, sessions]);
    if (request.cancelled?.call() ?? false) return const [];
    // The header already names the directory being listed; rows repeat it
    // only when there is no header to carry it (React `withLocation`).
    final withLocation =
        header(
          sessionId,
          HeaderRequest(
            query: request.query,
            quoted: request.quoted,
            drilled: request.drilled,
          ),
        ) ==
        null;
    return [
      ..._fileCandidates(results[0], request.quoted, withLocation),
      ..._sessionCandidates(results[1]),
    ];
  }

  @override
  List<InputTriggerCrumb>? header(String sessionId, HeaderRequest request) =>
      crumbsFor(request.query, request.quoted, request.drilled);

  List<InputTriggerCandidate> _fileCandidates(
    List<Map<String, Object?>> items,
    bool preserveQuote,
    bool withLocation,
  ) {
    final out = <InputTriggerCandidate>[];
    for (final item in items) {
      final path = item['path'];
      final kind = item['kind'];
      if (path is! String || path.isEmpty) continue;
      final directory = kind == 'directory';
      final mention = formatFileMention(
        path: path,
        directory: directory,
        preserveQuote: preserveQuote,
      );
      if (mention == null) continue;
      final slash = path.lastIndexOf('/');
      final name = path.substring(slash + 1);
      final parent = slash < 0 ? '' : path.substring(0, slash);
      final value = _CandidateValue._(
        'file',
        kind is String ? kind : null,
        name,
        mention,
      );
      out.add(
        InputTriggerCandidate(
          // Directories carry their trailing slash in the name; the location
          // is the parent alone (nothing at the workspace root), and only
          // when no header carries it (React `fileCandidate`).
          name: '$name${directory ? '/' : ''}',
          description: withLocation && parent != '' ? parent : null,
          icon: directory ? 'folder' : 'file',
          section: 'Files',
          value: jsonEncode(value.toJson()),
          drill: directory ? true : null,
        ),
      );
    }
    return out;
  }

  List<InputTriggerCandidate> _sessionCandidates(
    List<Map<String, Object?>> items,
  ) {
    final out = <InputTriggerCandidate>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in items) {
      final sessionId = item['sessionId'];
      final label = item['label'];
      final mention = item['mention'];
      if (sessionId is! String || label is! String || mention is! String)
        continue;
      // Candidates rank by workspace affinity, so the location only tells
      // something when it is not the current workspace (React
      // `sessionCandidate`).
      final sameWorkspace = item['sameWorkspace'] == true;
      final cwd = item['cwd'];
      final String? location = sameWorkspace
          ? null
          : cwd is String
          ? cwd
          : '(no cwd)';
      final updatedAt = item['updatedAt'];
      final createdAt = item['createdAt'];
      final at = updatedAt is int
          ? updatedAt
          : createdAt is int
          ? createdAt
          : now;
      final age = _relativeAge(at, now);
      final value = _CandidateValue._('session', null, label, mention);
      out.add(
        InputTriggerCandidate(
          name: label,
          description: location == null ? age : '$location · $age',
          icon: 'session',
          section: 'Sessions',
          value: jsonEncode(value.toJson()),
        ),
      );
    }
    return out;
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    final value = _CandidateValue.parse(pick.candidate.value);
    if (value?.kind == 'file') {
      // A directory row carries two verbs: the settling pick resolves the
      // folder itself as an atomic reference, while the drill action (Tab /
      // row chevron / header crumb) keeps the literal descent text and the
      // open menu (React `onPick`).
      if (value!.fileKind == 'directory' &&
          pick.action == PickAction.drill) {
        return TextOutcome(value.mention, continueTracking: true);
      }
      if (value.fileKind == 'directory') {
        return InsertOutcome(
          ReferenceInsert(
            source: kReferenceSourceName,
            ref: value.mention,
            label: '${value.label}/',
            appearance: 'folder',
            clipboardText: value.mention,
          ),
        );
      }
      return InsertOutcome(
        ReferenceInsert(
          source: kReferenceSourceName,
          ref: value.mention,
          label: value.label,
          appearance: 'file',
          clipboardText: value.mention,
        ),
      );
    }
    if (value?.kind == 'session') {
      return InsertOutcome(
        ReferenceInsert(
          source: kReferenceSourceName,
          ref: value!.mention,
          label: value.label,
          appearance: 'session',
          clipboardText: value.mention,
        ),
      );
    }
    return null;
  }

  @override
  ReferenceCodec get codec => const _IdentityCodec();
}

/// The breadcrumb of a drilled directory listing, from the workspace root
/// down to the directory being listed. Only a drill produces one (React
/// `crumbsFor` in `ui-reference/src/client/index.ts`).
List<InputTriggerCrumb>? crumbsFor(
  String query,
  bool quoted,
  bool drilled,
) {
  if (!drilled) return null;
  final slash = query.lastIndexOf('/');
  if (slash < 0) return null;
  final segments = query
      .substring(0, slash)
      .split('/')
      .where((segment) => segment != '')
      .toList();
  // Locale-owned root copy lives in the `reference` namespace
  // (`crumb.root`); hard-coded here until that namespace lands in Flutter.
  const rootLabel = 'Workspace';
  final crumbs = <InputTriggerCrumb>[
    InputTriggerCrumb(
      label: rootLabel,
      value: _directoryValue(rootLabel, quoted ? '@"' : '@'),
    ),
  ];
  for (var index = 0; index < segments.length; index++) {
    final path = segments.sublist(0, index + 1).join('/');
    final mention = formatFileMention(
      path: path,
      directory: true,
      preserveQuote: quoted,
    );
    // A trail whose steps cannot all be written back as mention text would
    // send the user somewhere they did not click; show no header instead.
    if (mention == null) return null;
    crumbs.add(
      InputTriggerCrumb(
        label: segments[index],
        value: _directoryValue(segments[index], mention),
        current: index == segments.length - 1,
      ),
    );
  }
  return crumbs;
}

/// Project one directory destination as the drill payload `onPick` already
/// understands.
String _directoryValue(String label, String mention) => jsonEncode(
  _CandidateValue._('file', 'directory', label, mention).toJson(),
);

/// Compact relative age in the reference `en` words (`now`/`{n}min`/`{n}h`/
/// `{n}d`/`{n}mo`/`{n}y`), bucketed exactly like ui-primitives
/// `relativeTime` so the `@` menu and the session list never disagree.
String _relativeAge(int at, int now) {
  const minute = 60000;
  const hour = 3600000;
  const day = 86400000;
  final diff = now - at < 0 ? 0 : now - at;
  if (diff < minute) return 'now';
  if (diff < hour) return '${diff ~/ minute}min';
  if (diff < day) return '${diff ~/ hour}h';
  if (diff < 30 * day) return '${diff ~/ day}d';
  if (diff < 365 * day) return '${(diff ~/ (30 * day))}mo';
  return '${diff ~/ (365 * day)}y';
}

/// The reference codec: both projections are the mention text itself
/// (`clipboardText: ref => ref`, `serialize: ref => ref` in React).
class _IdentityCodec implements ReferenceCodec {
  const _IdentityCodec();

  @override
  String clipboardText(String ref) => ref;

  @override
  Future<String> serialize(String ref) async => ref;
}
