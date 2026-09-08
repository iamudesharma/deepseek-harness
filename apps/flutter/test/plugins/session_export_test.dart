/// Session-log ZIP download tests — route, auth stripping, filename, save
/// sheet seam, and the export-aware executor wrapper.
library;

import 'dart:typed_data';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/commands/command_service.dart';
import 'package:dsh_flutter/src/plugins/commands/session_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ConnectionClient _client(http.Client transport) =>
    ConnectionClient(baseUrl: 'http://127.0.0.1:3080', httpClient: transport);

void main() {
  test('download GETs the export route and saves the ZIP', () async {
    Uri? requested;
    final transport = MockClient((http.Request req) async {
      requested = req.url;
      return http.Response.bytes(
        Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]),
        200,
        headers: {
          'content-type': 'application/zip',
          'content-disposition':
              'attachment; filename="dsh-session-s1.zip"',
        },
      );
    });
    Uint8List? saved;
    String? savedName;
    final service = SessionExportService(
      _client(transport),
      httpClient: transport,
      fileSaver: ({required bytes, required fileName}) async {
        saved = bytes;
        savedName = fileName;
        return '/tmp/dsh-session-s1.zip';
      },
    );
    await service.download(SessionId('s1'));
    expect(requested?.path, '/api/session.export');
    expect(requested?.queryParameters['sessionId'], 's1');
    expect(requested?.queryParameters['includeDescendants'], 'true');
    expect(requested?.queryParameters.containsKey('token'), isFalse);
    expect(saved, isNotNull);
    expect(savedName, 'dsh-session-s1.zip');
  });

  test('download falls back to the session id filename', () async {
    final transport = MockClient((http.Request req) async {
      return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200);
    });
    String? savedName;
    final service = SessionExportService(
      _client(transport),
      httpClient: transport,
      fileSaver: ({required bytes, required fileName}) async {
        savedName = fileName;
        return null;
      },
    );
    await service.download(SessionId('abc'));
    expect(savedName, 'dsh-session-abc.zip');
  });

  test('download throws user-presentable errors per status', () async {
    Future<String> messageFor(int status) async {
      final transport = MockClient((http.Request req) async {
        return http.Response('nope', status);
      });
      final service = SessionExportService(
        _client(transport),
        httpClient: transport,
        fileSaver: ({required bytes, required fileName}) async => null,
      );
      try {
        await service.download(SessionId('s1'));
        return 'no-throw';
      } on SessionExportException catch (e) {
        return e.message;
      }
    }

    expect(await messageFor(401), contains('not authorized'));
    expect(await messageFor(404), contains('not found'));
    expect(await messageFor(500), contains('status 500'));
  });

  test('export-aware executor downloads only on admitted bare /export', () async {
    var downloads = 0;
    Future<CommandExecutionOutcome> inner(SessionId _, String __) async =>
        CommandExecutionOutcome.success('Session log download requested.');
    var errors = <String>[];
    final wrapped = exportAwareExecutor(
      inner,
      exporter: SessionExportService(
        _client(MockClient((req) async => http.Response.bytes(Uint8List(4), 200))),
        httpClient: MockClient((req) async => http.Response.bytes(Uint8List(4), 200)),
        fileSaver: ({required bytes, required fileName}) async {
          downloads++;
          return null;
        },
      ),
      onExportError: errors.add,
    );
    final ok = await wrapped(SessionId('s1'), '/export');
    expect(ok.ok, isTrue);
    expect(downloads, 1);
    expect(errors, isEmpty);

    // Argued lines stay with the Host usage-error path: no download.
    await wrapped(SessionId('s1'), '/export foo.zip');
    expect(downloads, 1);

    // Failed commands never download.
    Future<CommandExecutionOutcome> failing(SessionId _, String __) async =>
        CommandExecutionOutcome.error('nope');
    final wrappedFailing = exportAwareExecutor(
      failing,
      exporter: SessionExportService(
        _client(MockClient((req) async => http.Response.bytes(Uint8List(4), 200))),
        httpClient: MockClient((req) async => http.Response.bytes(Uint8List(4), 200)),
        fileSaver: ({required bytes, required fileName}) async {
          downloads++;
          return null;
        },
      ),
      onExportError: errors.add,
    );
    await wrappedFailing(SessionId('s1'), '/export');
    expect(downloads, 1);
  });

  test('export-aware executor reports download failures without failing', () async {
    var errors = <String>[];
    Future<CommandExecutionOutcome> inner(SessionId _, String __) async =>
        CommandExecutionOutcome.success('ok');
    final wrapped = exportAwareExecutor(
      inner,
      exporter: SessionExportService(
        _client(MockClient((req) async => http.Response('x', 500))),
        httpClient: MockClient((req) async => http.Response('x', 500)),
        fileSaver: ({required bytes, required fileName}) async => null,
      ),
      onExportError: errors.add,
    );
    final outcome = await wrapped(SessionId('s1'), '/export');
    expect(outcome.ok, isTrue);
    expect(errors, hasLength(1));
  });
}
