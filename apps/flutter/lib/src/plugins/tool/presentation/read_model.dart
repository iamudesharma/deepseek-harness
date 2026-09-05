/// Read card model — Dart port of React `read-card-model.ts`.
///
/// A settled `read` shows a line-numbered card only when durable
/// `meta` (path/offset/lines/totalLines/lang) validates AND the model-facing
/// result is exactly one `<path>…</path>` file envelope. Anything else falls
/// back to the generic row.
library;

import 'dart:convert';

/// One numbered file line.
class ReadFileLine {
  const ReadFileLine({required this.number, required this.text});
  final int number;
  final String text;
}

/// Validated read card props.
class ReadCardModel {
  const ReadCardModel({
    required this.path,
    required this.offset,
    required this.lines,
    required this.totalLines,
    this.lang,
  });
  final String path;
  final int offset;
  final List<ReadFileLine> lines;
  final int totalLines;
  final String? lang;
}

/// Chat rows cap the resident read body at 8 lines; details shows full height.
const int kChatReadMaxLines = 8;

final RegExp _readEnvelope = RegExp(
  r'^<path>[^\n]*</path>\n<type>file</type>\n<content>\n([\s\S]*)\n</content>$',
);

/// Whether [resultText] is exactly one file envelope.
bool isReadEnvelope(String resultText) => _readEnvelope.hasMatch(resultText);

Map<String, Object?>? _asMap(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val as Object?));
  return null;
}

Object? _parseArgs(String argsRaw) {
  if (argsRaw.isEmpty) return null;
  try {
    return jsonDecode(argsRaw);
  } catch (_) {
    return null;
  }
}

bool validReadCall(String toolName, String argsRaw) {
  if (toolName.toLowerCase() != 'read') return false;
  final map = _asMap(_parseArgs(argsRaw));
  if (map == null) return false;
  final path = map['file_path'] ?? map['path'];
  if (path is! String || path.trim().isEmpty) return false;
  final offset = map['offset'];
  if (offset != null && (offset is! int || offset < 1)) return false;
  final limit = map['limit'];
  if (limit != null && (limit is! int || limit < 1)) return false;
  return true;
}

ReadCardModel? narrowReadMeta(Object? meta) {
  final map = _asMap(meta);
  if (map == null) return null;
  final path = map['path'];
  final offset = map['offset'];
  final lines = map['lines'];
  final totalLines = map['totalLines'];
  final lang = map['lang'];
  if (path is! String || offset is! int || offset < 1) return null;
  if (totalLines is! int || totalLines < 0 || lines is! List) return null;
  if (lang != null && lang is! String) return null;
  final narrowed = <ReadFileLine>[];
  var previous = offset - 1;
  for (final entry in lines) {
    final m = _asMap(entry);
    if (m == null) return null;
    final number = m['number'];
    final text = m['text'];
    if (number is! int || number < 1 || number <= previous) return null;
    if (number > totalLines || text is! String) return null;
    previous = number;
    narrowed.add(ReadFileLine(number: number, text: text));
  }
  return ReadCardModel(
    path: path,
    offset: offset,
    lines: narrowed,
    totalLines: totalLines,
    lang: lang as String?,
  );
}

/// Derives the settled read card, or null for the generic fallback.
ReadCardModel? readCardModel({
  required String toolName,
  required String argsRaw,
  required bool isError,
  required bool hasParentCallId,
  required Object? meta,
  required String? resultText,
}) {
  if (hasParentCallId || isError) return null;
  if (!validReadCall(toolName, argsRaw)) return null;
  final model = narrowReadMeta(meta);
  if (model == null) return null;
  if (resultText == null || !isReadEnvelope(resultText)) return null;
  return model;
}
