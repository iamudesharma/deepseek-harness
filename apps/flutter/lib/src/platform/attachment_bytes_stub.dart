import 'dart:typed_data';

/// Web stub — no `dart:io`, so file paths cannot be read; draft bytes are
/// expected to be present in memory (via `DroppedFile.bytes` from
/// `file_picker` or a blob URL that will be fetched separately).
Future<Uint8List?> readFileBytes(String path) async => null;
