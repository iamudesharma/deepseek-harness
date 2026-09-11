import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/remote_mux_client.dart';
import 'package:dsh_flutter/src/core/files/media_file_client.dart';
import 'package:dsh_flutter/src/core/files/workspace_files_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Scripted connection: answers `callMethod` from a table and `fetchMedia`
/// from a status/body table. Throws [RemoteMethodException] for error rows,
/// exactly like the unwrapped gateway envelope path.
class _FakeConnectionClient extends ConnectionClient {
  _FakeConnectionClient({
    Map<String, Object?> responses = const {},
    Map<String, http.Response> media = const {},
  }) : _responses = responses,
       _media = media,
       super(baseUrl: 'http://127.0.0.1:9');

  final Map<String, Object?> _responses;
  final Map<String, http.Response> _media;

  /// Last payload per method, for request-shape assertions.
  final Map<String, Map<String, dynamic>> seenPayloads = {};

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    seenPayloads[method] = payload;
    final response = _responses[method];
    if (response is RemoteMethodException) throw response;
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return response.cast<String, dynamic>();
    throw StateError('no scripted response for $method');
  }

  @override
  Future<http.Response> fetchMedia(Uri url, {bool head = false}) async {
    final response = _media[url.toString()];
    if (response != null) return response;
    return http.Response('missing', 404);
  }
}

class _FakeMux extends RemoteMuxClient {
  _FakeMux({this.frames = const []})
    : super(baseUrl: 'http://127.0.0.1:9', httpFetch: (_, _) async => {});

  /// Frames yielded for any opened stream.
  final List<Map<String, dynamic>> frames;

  /// Endpoints opened, in order.
  final List<String> opens = [];

  /// Payloads passed to [open], in order.
  final List<Map<String, dynamic>> payloads = [];

  @override
  Stream<Map<String, dynamic>> open(
    String endpoint,
    Map<String, dynamic> payload,
  ) async* {
    opens.add(endpoint);
    payloads.add(payload);
    for (final frame in frames) {
      yield frame;
    }
  }
}

RemoteMethodException _fileError(String wire, {Map<String, Object?> details = const {}}) {
  final code = RpcErrorCode.tryParse(wire)!;
  return RemoteMethodException(code: code, message: wire, details: details);
}

void main() {
  SessionId sid() => SessionId('s1');

  group('workspaceFiles request shapes', () {
    test('stat/read/list carry sessionId and path vocabularies', () async {
      final client = _FakeConnectionClient(
        responses: {
          'workspaceFiles/stat': {
            'absolutePath': '/w/a.txt',
            'version': 'v1',
          },
          'workspaceFiles/read': {
            'absolutePath': '/w/a.txt',
            'version': 'v1',
            'offset': 1,
            'text': 'hello\n',
            'lines': 1,
            'eof': true,
          },
          'workspaceFiles/list': {
            'path': '',
            'entries': [
              {'name': 'a.txt', 'type': 'file', 'size': 6},
            ],
            'truncated': false,
          },
        },
      );
      final files = WorkspaceFilesClient(client);
      final stat = await files.stat(sid(), '/w/a.txt');
      expect(stat.absolutePath, '/w/a.txt');
      expect(stat.version, 'v1');
      // Session travels with the call; read uses absolute paths.
      expect(client.seenPayloads['workspaceFiles/stat'], {
        'workspaceFileScopeId': 's1',
        'path': '/w/a.txt',
      });
      final text = await files.read(sid(), '/w/a.txt');
      expect(text.lines, 1);
      expect(text.eof, isTrue);
      expect(
        client.seenPayloads['workspaceFiles/read'],
        {
          'workspaceFileScopeId': 's1',
          'path': '/w/a.txt',
          'range': {'offset': 1},
        },
      );
      final listing = await files.list(sid(), '');
      expect(listing.entries.single.name, 'a.txt');
      expect(listing.entries.single.type, WorkspaceEntryType.file);
      expect(listing.truncated, isFalse);
    });

    test('readBytes carries byte ranges', () async {
      final client = _FakeConnectionClient(
        responses: {
          'workspaceFiles/readBytes': {
            'absolutePath': '/w/a.bin',
            'version': 'v3',
            'offset': 8,
            'data': 'aGk=',
            'eof': true,
          },
        },
      );
      final files = WorkspaceFilesClient(client);
      final bytes = await files.readBytes(sid(), '/w/a.bin', offset: 8, length: 16);
      expect(bytes.offset, 8);
      expect(bytes.data, 'aGk=');
      expect(
        client.seenPayloads['workspaceFiles/readBytes'],
        {
          'workspaceFileScopeId': 's1',
          'path': '/w/a.bin',
          'range': {'offset': 8, 'length': 16},
        },
      );
    });
  });

  group('workspaceFiles error mapping', () {
    test('all six file codes map with path and limit', () async {
      final cases = <String, Map<String, Object?>>{
        'workspace-file/not-found': {'path': '/w/nope'},
        'workspace-file/outside-workspace': {'path': '/etc/passwd'},
        'workspace-file/too-large': {'path': '/w/big', 'limit': 2097152},
        'workspace-file/not-text': {'path': '/w/a.png'},
        'workspace-file/not-regular-file': {'path': '/w/dir', 'kind': 'directory'},
        'workspace-file/not-directory': {'path': '/w/a.txt', 'kind': 'file'},
      };
      for (final entry in cases.entries) {
        final client = _FakeConnectionClient(
          responses: {
            'workspaceFiles/stat': _fileError(entry.key, details: entry.value),
          },
        );
        final files = WorkspaceFilesClient(client);
        try {
          await files.stat(sid(), '/w/x');
          fail('expected WorkspaceFileException for ${entry.key}');
        } on WorkspaceFileException catch (e) {
          expect(e.code.wire, entry.key);
          expect(e.path, entry.value['path']);
        }
      }
      // Limit rides along on too-large.
      final client = _FakeConnectionClient(
        responses: {
          'workspaceFiles/read': _fileError(
            'workspace-file/too-large',
            details: {'path': '/w/big', 'limit': 2097152},
          ),
        },
      );
      try {
        await WorkspaceFilesClient(client).read(sid(), '/w/big');
        fail('expected too-large');
      } on WorkspaceFileException catch (e) {
        expect(e.limit, 2097152);
      }
    });

    test('non-file errors pass through untouched', () async {
      final client = _FakeConnectionClient(
        responses: {
          'workspaceFiles/stat': _fileError('gateway/internal'),
        },
      );
      await expectLater(
        WorkspaceFilesClient(client).stat(sid(), '/w/a.txt'),
        throwsA(isA<RemoteMethodException>()),
      );
    });
  });

  group('workspace file changes', () {
    test('ready/change frames decode; watch opens the session feed', () async {
      final mux = _FakeMux(
        frames: [
          {'kind': 'ready'},
          {
            'kind': 'change',
            'change': {'absolutePath': '/w/a.txt', 'version': 'v2'},
          },
          {
            'kind': 'change',
            'change': {'absolutePath': '/w/gone.txt', 'absent': true},
          },
        ],
      );
      final client = _FakeConnectionClient();
      final files = WorkspaceFilesClient(
        client,
        muxForSession: () => mux,
      );
      final frames = await files.watch(sid()).toList();
      expect(mux.opens, ['workspaceFiles/changes']);
      expect(mux.payloads.single, {
        'args': {'workspaceFileScopeId': 's1'},
      });
      expect(frames.first.isReady, isTrue);
      expect(frames[1].change?.version, 'v2');
      expect(frames[2].change?.absent, isTrue);
    });

    test('watch without a mux generation fails loud', () async {
      final files = WorkspaceFilesClient(_FakeConnectionClient());
      await expectLater(
        files.watch(sid()).toList(),
        throwsStateError,
      );
    });
  });

  group('media file mapping and fetch', () {
    test('only absolute POSIX paths map', () {
      const origin = 'http://127.0.0.1:3080';
      expect(
        localPathMediaUrl(origin, '/w/a.png'),
        'http://127.0.0.1:3080/api/file?path=${Uri.encodeComponent('/w/a.png')}',
      );
      expect(localPathMediaUrl(origin, '//w/a.png'), isNull);
      expect(localPathMediaUrl(origin, 'file:///w/a.png'), isNull);
      expect(localPathMediaUrl(origin, 'relative/a.png'), isNull);
      expect(localPathMediaUrl(origin, 'https://x/y.png'), isNull);
      expect(localPathMediaUrl(origin, ''), isNull);
    });

    test('statuses map to unavailable/too-large/denied', () async {
      Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);
      final client = _FakeConnectionClient(
        media: {
          'http://h/api/file?path=%2Fa.png': http.Response.bytes(bytes('PNG'), 200),
          'http://h/api/file?path=%2Fbig.png': http.Response('cap', 413),
          'http://h/api/file?path=%2Fpriv.png': http.Response('no', 403),
          'http://h/api/file?path=%2Fnope.png': http.Response('no', 404),
        },
      );
      final media = MediaFileClient(client);
      final dataUrl = await media.fetchDataUrl('http://h/api/file?path=%2Fa.png');
      expect(dataUrl.startsWith('data:image/png;base64,'), isTrue);
      expect(
        media.fetchBytes('http://h/api/file?path=%2Fbig.png'),
        throwsA(
          isA<MediaFileException>().having((e) => e.failure, 'failure', MediaFileFailure.tooLarge),
        ),
      );
      expect(
        media.fetchBytes('http://h/api/file?path=%2Fpriv.png'),
        throwsA(
          isA<MediaFileException>().having((e) => e.failure, 'failure', MediaFileFailure.denied),
        ),
      );
      expect(
        media.fetchBytes('http://h/api/file?path=%2Fnope.png'),
        throwsA(
          isA<MediaFileException>().having((e) => e.failure, 'failure', MediaFileFailure.unavailable),
        ),
      );
      expect(await media.exists('http://h/api/file?path=%2Fa.png'), isTrue);
      expect(await media.exists('http://h/api/file?path=%2Fnope.png'), isFalse);
    });
  });

  group('remote file access over the same connection', () {
    test('reads carry the session scope remotely too', () async {
      final client = _FakeConnectionClient(
        responses: {
          'workspaceFiles/stat': {
            'absolutePath': '/remote/w/a.txt',
            'version': 'r7',
          },
        },
      );
      final files = WorkspaceFilesClient(client);
      final stat = await files.stat(SessionId('remote-session'), '/remote/w/a.txt');
      expect(stat.version, 'r7');
      expect(client.seenPayloads['workspaceFiles/stat']?['workspaceFileScopeId'], 'remote-session');
    });
  });
}
