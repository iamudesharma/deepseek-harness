import 'dart:io';
import 'dart:typed_data';

/// Native implementation — reads the file at [path] via `dart:io`.
///
/// Returns `null` when the file does not exist or cannot be read, so the
/// caller can surface a submission error instead of silently dropping the
/// image.
Future<Uint8List?> readFileBytes(String path) async {
  try {
    final File file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
