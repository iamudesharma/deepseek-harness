/// Display-only POSIX home abbreviation — port of
/// `packages/client/runtime/src/client/workspaces/path.ts:abbreviateHomePath`.
///
/// Windows drive and UNC paths stay verbatim, including when `home` itself
/// is a Windows path. A missing, empty, or filesystem-root `home` leaves
/// `path` unchanged so `/` cannot become `~`.
///
/// @param path - absolute or already-short display path.
/// @param home - host account home from `host.describe`; absent skips abbreviation.
/// @returns `~` or `~/…` for the POSIX home and its descendants, otherwise `path`.
String abbreviateHomePath(String path, [String? home]) {
  if (home == null || home.isEmpty) return path;
  if (_isWindowsStylePath(path) || _isWindowsStylePath(home)) return path;
  final root = home.replaceAll(RegExp(r'/+$'), '');
  if (root.isEmpty || root == '/') return path;
  if (path.replaceAll(RegExp(r'/+$'), '') == root) return '~';
  if (path.startsWith('$root/')) return '~${path.substring(root.length)}';
  return path;
}

bool _isWindowsStylePath(String value) {
  if (RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value)) return true;
  if (value.startsWith(r'\\')) return true;
  return false;
}
