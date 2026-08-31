import 'dart:convert';

/// Port of React `displayFailureMessage`
/// (`packages/client/runtime/src/client/sessions/failure-display.ts`).
///
/// Converts a durable failure into copy safe for GUI projection: AUTH codes
/// collapse to a fixed line so a masked or partially preserved credential is
/// never projected into UI state; every other provider message projects
/// verbatim (`This turn failed\n` + message) with the typed envelope kept as
/// raw for Details.
({String friendly, String raw}) displayFailureMessage(dynamic failure) {
  if (failure == null) return (friendly: 'Response failed', raw: '');
  if (failure is! Map) {
    final String s = failure.toString();
    return (friendly: s, raw: s);
  }
  final m = (failure as Map).cast<String, dynamic>();
  final String? code = m['code'] as String?;
  final dynamic message = m['message'];
  if (code == 'AUTH') {
    // Raw diagnostic stays in the session log; UI shows the fixed line.
    final String raw = message is String ? message : jsonEncode(m);
    return (friendly: 'This turn failed\nAPI key is invalid', raw: raw);
  }
  if (message is String && message.trim().isNotEmpty) {
    // Keep raw containing type for Details when ModelError without AUTH code
    final String raw = m.containsKey('type') ? jsonEncode(m) : message;
    return (friendly: 'This turn failed\n$message', raw: raw);
  }
  final String raw = jsonEncode(m);
  return (friendly: 'This turn failed\n$raw', raw: raw);
}
