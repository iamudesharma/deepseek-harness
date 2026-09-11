import 'package:dsh_flutter/src/core/api/rpc_envelope.dart';
import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/connection/remote_mux_client.dart';
import 'package:dsh_flutter/src/core/files/workspace_files_client.dart';
import 'package:dsh_flutter/src/core/services/runtime_services.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/plugins/deliverables/locales.dart';
import 'package:dsh_flutter/src/plugins/deliverables/ui/file_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConnectionClient extends ConnectionClient {
  _FakeConnectionClient({this.statResponse, this.readResponse})
    : super(baseUrl: 'http://127.0.0.1:9');

  final Map<String, dynamic>? statResponse;
  final Map<String, dynamic>? readResponse;

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    if (method == 'workspaceFiles/stat' && statResponse != null) {
      return statResponse!;
    }
    if (method == 'workspaceFiles/read' && readResponse != null) {
      return readResponse!;
    }
    throw RemoteMethodException(
      code: RpcErrorCode.workspaceFileNotFound,
      message: 'workspace-file/not-found',
      details: {'path': '/w/nope'},
    );
  }

  @override
  RemoteMuxClient createRemoteMuxClient() => throw UnimplementedError();
}

WorkspaceFilesClient _files({
  Map<String, dynamic>? stat,
  Map<String, dynamic>? read,
}) => WorkspaceFilesClient(
  _FakeConnectionClient(statResponse: stat, readResponse: read),
);

Widget _dialogApp(WorkspaceFilesClient files, {Future<void> Function()? onOpenHost}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final locale = container.read(localeServiceProvider);
  locale.register(kDeliverablesNamespace, {
    'zh': kDeliverablesZh,
    'en': kDeliverablesEn,
  });
  locale.setLocale('en');
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: FilePreviewDialog(
          files: files,
          sessionId: SessionId('s1'),
          path: '/w/a.txt',
          onOpenHost: onOpenHost,
        ),
      ),
    ),
  );
}

void main() {
  group('file preview dialog', () {
    testWidgets('renders the first page with truncated note', (tester) async {
      await tester.pumpWidget(
        _dialogApp(
          _files(
            stat: {'absolutePath': '/w/a.txt', 'version': 'v1'},
            read: {
              'absolutePath': '/w/a.txt',
              'version': 'v1',
              'offset': 1,
              'text': 'hello\nworld',
              'lines': 2,
              'eof': false,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('hello'), findsOneWidget);
      expect(find.textContaining('first 2 lines'), findsOneWidget);
      expect(find.text('/w/a.txt'), findsOneWidget);
    });

    testWidgets('failure line with retry reloads', (tester) async {
      var calls = 0;
      Future<Map<String, dynamic>> flakyStat() async {
        calls++;
        if (calls == 1) {
          throw RemoteMethodException(
            code: RpcErrorCode.workspaceFileNotFound,
            message: 'gone',
            details: const {'path': '/w/a.txt'},
          );
        }
        return {'absolutePath': '/w/a.txt', 'version': 'v1'};
      }

      await tester.pumpWidget(
        _localeApp(
          _FlakyPreview(
            stat: flakyStat,
            read: () async => {
              'absolutePath': '/w/a.txt',
              'version': 'v1',
              'offset': 1,
              'text': 'recovered',
              'lines': 1,
              'eof': true,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('does not exist'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      final texts = tester.widgetList(find.byType(Text)).map((w) => (w as Text).data ?? '?').toList();
      print('DBG AFTER RETRY: $texts');
      expect(find.textContaining('recovered'), findsOneWidget);
    });

    testWidgets('denied file shows denial without host fallback', (tester) async {
      await tester.pumpWidget(
        _dialogApp(
          _files(),
          onOpenHost: () async {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('does not exist'), findsOneWidget);
      // Not a directory-shaped failure: no host fallback offered.
      expect(find.text('Show in folder'), findsNothing);
    });
  });
}

/// Preview harness with injectable stat/read (drives the same dialog states
/// as the provider-backed client without transport).
class _FlakyPreview extends StatelessWidget {
  const _FlakyPreview({
    required this.stat,
    required this.read,
  });

  final Future<Map<String, dynamic>> Function() stat;
  final Future<Map<String, dynamic>> Function() read;

  @override
  Widget build(BuildContext context) {
    return FilePreviewDialog(
      files: _ScriptedFiles(statFn: stat, readFn: read),
      sessionId: SessionId('s1'),
      path: '/w/a.txt',
    );
  }
}

class _ScriptedFiles extends WorkspaceFilesClient {
  _ScriptedFiles({
    required this.statFn,
    required this.readFn,
  }) : super(_FakeConnectionClient());

  final Future<Map<String, dynamic>> Function() statFn;
  final Future<Map<String, dynamic>> Function() readFn;

  @override
  Future<WorkspaceFileStat> stat(SessionId sessionId, String path) async {
    try {
      return WorkspaceFileStat.fromJson(await statFn());
    } on RemoteMethodException catch (e) {
      throw WorkspaceFileException.fromTransport(e);
    }
  }

  @override
  Future<WorkspaceFileText> read(
    SessionId sessionId,
    String path, {
    int offset = 1,
    int? limit,
  }) async {
    return WorkspaceFileText.fromJson(await readFn());
  }
}

Widget _localeApp(Widget child) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final locale = container.read(localeServiceProvider);
  locale.register(kDeliverablesNamespace, {
    'zh': kDeliverablesZh,
    'en': kDeliverablesEn,
  });
  locale.setLocale('en');
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}
