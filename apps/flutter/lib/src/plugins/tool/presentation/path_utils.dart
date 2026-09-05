/// Path display helpers — Dart port of React `relativizeToCwd` +
/// `abbreviateHomePath` composition used by every tool row summary.
///
/// React: `packages/client/ui-tool/src/client/tool/models/tool-call-model.ts:168-173`
/// + `packages/util/workspace-path/src/index.ts:31-39`.
/// Flutter already owns [abbreviateHomePath]; this file adds the cwd-relative
/// step and the combined display helper so rows show `src/a.ts` instead of
/// `/Volumes/.../proj/src/a.ts`.
library;

import '../../../utils/abbreviate_home_path.dart';

/// Strips the workspace root from a workspace-rooted absolute path.
///
/// Mirrors React `relativizeToCwd`: trailing slashes on [cwd] are ignored; a
/// [text] that starts with `<root>/` or `<root>\` returns the remainder,
/// otherwise [text] is returned unchanged. Empty/absent [cwd] is a no-op.
String relativizeToCwd(String text, String? cwd) {
  if (cwd == null || cwd.isEmpty) return text;
  final root = cwd.replaceAll(RegExp(r'[/\\]+$'), '');
  if (root.isEmpty) return text;
  if (text.startsWith('$root/') || text.startsWith('$root\\')) {
    return text.substring(root.length + 1);
  }
  return text;
}

/// Full display pipeline for a tool-row path: cwd-relative then `~`-abbreviated.
String displayPath(String path, {String? cwd, String? home}) =>
    abbreviateHomePath(relativizeToCwd(path, cwd), home);
