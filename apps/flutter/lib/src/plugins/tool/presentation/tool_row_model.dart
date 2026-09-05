/// Tool row model — Dart port of React `tool-call-model.ts`
/// (`packages/client/ui-tool/src/client/tool/models/tool-call-model.ts`).
///
/// Derives the collapsed row (variant, title, summary, openable file path,
/// state) from the wire tool name + raw argument JSON. Summaries are always
/// args-derived; the result envelope (`<path>…</path>`) is never parsed for
/// the row — matching React, which reads `file_path`/`path` input keys.
library;

import 'dart:convert';

import 'path_utils.dart';

/// Row variants selected by the generic atomic renderer.
enum ToolRowVariant { search, read, bash, write, edit, code, others }

/// Row state semantic.
enum ToolRowState { running, ok, error, stopped }

/// Known wire name → variant. Mirrors React `TOOL_VARIANTS`.
const Map<String, ToolRowVariant> kToolVariants = {
  'bash': ToolRowVariant.bash,
  'pwsh': ToolRowVariant.bash,
  'read': ToolRowVariant.read,
  'read_image': ToolRowVariant.read,
  'web_fetch': ToolRowVariant.read,
  'web_search': ToolRowVariant.search,
  'grep': ToolRowVariant.search,
  'glob': ToolRowVariant.search,
  'write': ToolRowVariant.write,
  'edit': ToolRowVariant.edit,
  'run_code': ToolRowVariant.code,
  'cordis_package_inspect': ToolRowVariant.read,
  'cordis_runtime_inspect': ToolRowVariant.read,
  'cordis_run': ToolRowVariant.others,
  'cordis_stop': ToolRowVariant.others,
  'cordis_undefine': ToolRowVariant.others,
  // Flutter treasury: local aliases that predate the canonical names.
  'str_replace_editor': ToolRowVariant.edit,
  'view': ToolRowVariant.read,
  'cat': ToolRowVariant.read,
  'search': ToolRowVariant.search,
  'shell': ToolRowVariant.bash,
  'terminal': ToolRowVariant.bash,
  'exec': ToolRowVariant.bash,
  'diff': ToolRowVariant.edit,
  'apply_patch': ToolRowVariant.edit,
  'find': ToolRowVariant.search,
  'rg': ToolRowVariant.search,
};

/// Classify a wire tool name into its row variant.
ToolRowVariant classifyTool(String toolName) =>
    kToolVariants[toolName] ?? kToolVariants[toolName.toLowerCase()] ?? ToolRowVariant.others;

/// Locale key per variant. Mirrors React `VARIANT_TITLE_KEYS`.
String variantTitleKey(ToolRowVariant variant) => switch (variant) {
  ToolRowVariant.search => 'tool.title.search',
  ToolRowVariant.read => 'tool.title.read',
  ToolRowVariant.bash => 'tool.title.bash',
  ToolRowVariant.write => 'tool.title.write',
  ToolRowVariant.edit => 'tool.title.edit',
  ToolRowVariant.code => 'tool.title.code',
  ToolRowVariant.others => 'tool.title.generic',
};

/// Tool-owned title refinements. Mirrors React `TOOL_TITLE_KEYS`.
String? toolTitleKey(String toolName) => const {
  'cordis_package_inspect': 'tool.title.inspect',
  'cordis_runtime_inspect': 'tool.title.inspect',
  'cordis_run': 'tool.title.runCordis',
  'cordis_stop': 'tool.title.stopCordis',
  'cordis_undefine': 'tool.title.removeCordis',
  'pwsh': 'tool.title.pwsh',
  'read_image': 'tool.title.readImage',
}[toolName];

/// Everything the collapsed row needs, derived once from raw args.
class ToolRowModel {
  const ToolRowModel({
    required this.variant,
    required this.titleKey,
    required this.titleFallback,
    required this.summary,
    this.filePath,
    required this.state,
    this.errorSummary,
  });

  final ToolRowVariant variant;

  /// Locale key for the row title (e.g. `tool.title.write`).
  final String titleKey;

  /// Verbatim fallback when the locale dictionary lacks [titleKey].
  final String titleFallback;
  final String summary;
  final String? filePath;
  final ToolRowState state;
  final String? errorSummary;
}

/// Summary key preference per variant. Mirrors React `SUMMARY_KEYS`.
const Map<ToolRowVariant, List<String>> kSummaryKeys = {
  ToolRowVariant.bash: ['description', 'command'],
  ToolRowVariant.read: ['path', 'file_path', 'url'],
  ToolRowVariant.search: ['query', 'pattern', 'url'],
  ToolRowVariant.write: ['path', 'file_path'],
  ToolRowVariant.edit: ['path', 'file_path'],
  ToolRowVariant.code: ['description'],
  ToolRowVariant.others: [],
};

/// Path keys only — never `url`.
const List<String> kFilePathKeys = ['path', 'file_path'];

/// File-tool variants whose summary may be an openable workspace path.
const Set<ToolRowVariant> kFilePathVariants = {
  ToolRowVariant.read,
  ToolRowVariant.write,
  ToolRowVariant.edit,
};

/// Default English titles used when the locale dictionary lacks the key.
String defaultTitleFor(String toolName, ToolRowVariant variant) {
  final owned = {
    'pwsh': 'Pwsh',
    'read_image': 'Read image',
    'cordis_package_inspect': 'Inspect',
    'cordis_runtime_inspect': 'Inspect',
    'cordis_run': 'Run Cordis',
    'cordis_stop': 'Stop Cordis',
    'cordis_undefine': 'Remove Cordis',
  }[toolName];
  if (owned != null) return owned;
  return switch (variant) {
    ToolRowVariant.search => 'Search',
    ToolRowVariant.read => 'Read',
    ToolRowVariant.bash => 'Bash',
    ToolRowVariant.write => 'Write',
    ToolRowVariant.edit => 'Edit',
    ToolRowVariant.code => 'Code',
    ToolRowVariant.others => 'Tool call',
  };
}

Object? parseArgs(String argsRaw) {
  if (argsRaw.isEmpty) return null;
  try {
    return jsonDecode(argsRaw);
  } catch (_) {
    return null;
  }
}

String firstLine(String text) {
  final nl = text.indexOf('\n');
  return nl == -1 ? text : text.substring(0, nl);
}

String? pickString(Map<String, Object?> args, List<String> keys) {
  for (final key in keys) {
    final v = args[key];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

String deriveSummary(ToolRowVariant variant, String argsRaw) {
  final parsed = parseArgs(argsRaw);
  if (parsed is! Map) return firstLine(argsRaw);
  final args = parsed.map((k, v) => MapEntry(k.toString(), v));
  if (variant == ToolRowVariant.search && args['queries'] is List) {
    final queries = (args['queries'] as List)
        .whereType<String>()
        .where((q) => q.isNotEmpty)
        .map(firstLine)
        .toList();
    if (queries.isNotEmpty) return queries.join(', ');
  }
  final picked = pickString(
    args.map((k, v) => MapEntry(k, v as Object?)),
    kSummaryKeys[variant] ?? const [],
  );
  if (picked != null) return firstLine(picked);
  for (final v in args.values) {
    if (v is String && v.isNotEmpty) return firstLine(v);
  }
  return firstLine(argsRaw);
}

String? deriveFilePath(ToolRowVariant variant, String argsRaw) {
  if (!kFilePathVariants.contains(variant)) return null;
  final parsed = parseArgs(argsRaw);
  if (parsed is! Map) return null;
  final args = (parsed).map((k, v) => MapEntry(k.toString(), v as Object?));
  final picked = pickString(args, kFilePathKeys);
  return picked == null ? null : firstLine(picked);
}

/// Derives the full row model.
///
/// @param toolName wire tool name.
/// @param argsRaw raw `arguments` JSON string exactly as the model produced it.
/// @param isError whether the settled result is an error.
/// @param running whether the call is still in flight.
/// @param interrupted whether the error code is `interrupted`.
/// @param resultText flattened result text (for the error summary only).
/// @param cwd session workspace root for relative summaries.
/// @param home host home for `~` abbreviation.
/// @param callId stable call id shown when [argsRaw] is empty (React parity:
///   a windowless/orphan result titles by call id, never by tool name twice).
ToolRowModel toolRowModel({
  required String toolName,
  required String argsRaw,
  required bool running,
  bool isError = false,
  bool interrupted = false,
  String? resultText,
  String? cwd,
  String? home,
  String? callId,
}) {
  final variant = classifyTool(toolName);
  final state = running
      ? ToolRowState.running
      : interrupted
      ? ToolRowState.stopped
      : isError
      ? ToolRowState.error
      : ToolRowState.ok;
  final base = argsRaw.isEmpty
      ? (callId ?? toolName)
      : displayPath(deriveSummary(variant, argsRaw), cwd: cwd, home: home);
  final ownedKey = toolTitleKey(toolName);
  final summary =
      variant == ToolRowVariant.others && ownedKey == null && toolName.isNotEmpty
      ? '$toolName · $base'
      : base;
  final output = (resultText ?? '').isEmpty ? null : resultText;
  final errorSummary = state == ToolRowState.error && output != null
      ? firstLine(output)
      : null;
  final rawPath = deriveFilePath(variant, argsRaw);
  return ToolRowModel(
    variant: variant,
    titleKey: ownedKey ?? variantTitleKey(variant),
    titleFallback: defaultTitleFor(toolName, variant),
    summary: summary,
    filePath: rawPath == null
        ? null
        : displayPath(rawPath, cwd: cwd, home: home),
    state: state,
    errorSummary: errorSummary,
  );
}
