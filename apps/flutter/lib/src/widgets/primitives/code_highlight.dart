/// Syntax highlighting for fenced code blocks — VSCode-style TextMate
/// highlighting via `syntax_highlight` (Serverpod), the maintained pub
/// equivalent of React's shiki grammar highlighting.
///
/// The highlighter loads TextMate grammars from package assets
/// asynchronously; callers render plain monospace text until [ensureInitialized]
/// completes, then rebuild to highlighted spans. Unknown languages fall back
/// to plain text (never an error).
library;

import 'package:flutter/material.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

/// Fence info → TextMate grammar name. Grammars available in
/// `syntax_highlight`: css, dart, go, html, java, javascript, json, kotlin,
/// python, rust, serverpod_protocol, sql, swift, typescript, yaml.
String? highlighterLanguageFor(String? fence) {
  if (fence == null) return null;
  final lang = fence.trim().toLowerCase();
  if (lang.isEmpty) return null;
  const aliases = {
    'dart': 'dart',
    'python': 'python',
    'py': 'python',
    'javascript': 'javascript',
    'js': 'javascript',
    'jsx': 'javascript',
    'typescript': 'typescript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'json': 'json',
    'jsonc': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'sql': 'sql',
    'css': 'css',
    'scss': 'css',
    'less': 'css',
    'html': 'html',
    'xml': 'html',
    'java': 'java',
    'kotlin': 'kotlin',
    'kt': 'kotlin',
    'swift': 'swift',
    'go': 'go',
    'rust': 'rust',
    'rs': 'rust',
  };
  return aliases[lang];
}

bool _initializing = false;
bool _initialized = false;
Future<void>? _initFuture;

/// Loads TextMate grammars once per process. Safe to call concurrently;
/// failures resolve to plain-text fallback (never throw).
Future<void> ensureCodeHighlightInitialized() {
  if (_initialized) return Future.value();
  final pending = _initFuture;
  if (pending != null) return pending;
  _initializing = true;
  final future = Highlighter.initialize([
    'dart',
    'python',
    'javascript',
    'typescript',
    'json',
    'yaml',
    'sql',
    'css',
    'html',
    'java',
    'kotlin',
    'swift',
    'go',
    'rust',
  ]).then((_) {
    _initialized = true;
    _initializing = false;
  }).catchError((_) {
    _initializing = false;
  });
  _initFuture = future;
  return future;
}

/// Whether grammars finished loading (highlighting available).
bool get codeHighlightReady => _initialized;

/// Whether a highlight load is in flight.
bool get codeHighlightLoading => _initializing;

HighlighterTheme? _lightTheme;
HighlighterTheme? _darkTheme;

/// Ensures grammars + the brightness-appropriate theme are loaded.
/// Returns true when highlighting is available; false on any failure
/// (callers render plain text). Concurrent calls share one future per
/// brightness.
Future<bool> ensureCodeHighlightReady({required bool dark}) async {
  try {
    await ensureCodeHighlightInitialized();
  } catch (_) {
    return false;
  }
  if (!_initialized) return false;
  try {
    if (dark) {
      _darkTheme ??= await HighlighterTheme.loadDarkTheme();
    } else {
      _lightTheme ??= await HighlighterTheme.loadLightTheme();
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Highlights [code] with the grammar for [language], or returns null when
/// highlighting is unavailable (not initialized, unknown language, failure).
TextSpan? highlightCodeSpan(
  String code,
  String? language, {
  required bool dark,
  required TextStyle baseStyle,
}) {
  if (!_initialized) return null;
  final grammar = highlighterLanguageFor(language);
  if (grammar == null) return null;
  try {
    final theme = dark ? _darkTheme : _lightTheme;
    // Theme loads via ensureCodeHighlightReady; null means plain fallback.
    if (theme == null) return null;
    final highlighter = Highlighter(language: grammar, theme: theme);
    final span = highlighter.highlight(code);
    return TextSpan(
      style: baseStyle,
      children: [span],
    );
  } catch (_) {
    return null;
  }
}
