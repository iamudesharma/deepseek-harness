import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/core/session/sessions_controller.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart' show ChatNodeData;
import 'package:dsh_flutter/src/plugins/deliverables/deliverables_open.dart'
    show canOpenHostPathProvider;
import 'package:dsh_flutter/src/plugins/deliverables/ui/file_preview_dialog.dart'
    show FilePreviewDialog;
import 'package:dsh_flutter/src/plugins/tool/presentation/diff_model.dart'
    as diff_model;
import 'package:dsh_flutter/src/widgets/primitives/diff_block.dart'
    show DsDiffBlock;
import 'package:dsh_flutter/src/plugins/tool/tool_models.dart';
import 'package:dsh_flutter/src/plugins/tool/ui/keyed_tool_card.dart';
import 'package:dsh_flutter/src/plugins/tool/ui/tool_call_tree.dart'
    show DiffToolCard;
import 'package:dsh_flutter/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

ToolCall _call({
  required String toolName,
  required String argsRaw,
  String? result,
  ToolCallStatus status = ToolCallStatus.success,
  Object? meta,
  String? errorCode,
}) {
  return ToolCall(
    id: 'c1',
    toolName: toolName,
    kind: kindForTool(toolName),
    status: status,
    argsRaw: argsRaw,
    result: result,
    meta: meta,
    errorCode: errorCode,
    time: 0,
  );
}

class _TestAdapter implements ToolNodeAdapter {
  _TestAdapter(this.call);
  final ToolCall call;
  @override
  ToolCall toToolCall() => call;
}

Widget _row(String toolName, ToolCall call) {
  return KeyedToolCard(
    toolName: toolName,
    data: ChatNodeData(key: 't1', lines: const ['c1'], raw: _TestAdapter(call)),
    child: const SizedBox(),
  );
}

void main() {
  group('KeyedToolCard rows', () {
    testWidgets('write row shows relative path plus diff stat, never the envelope', (
      tester,
    ) async {
      final call = _call(
        toolName: 'write',
        argsRaw: '{"file_path":"src/a.js","content":"a\\nb\\n"}',
        result:
            '<path>/abs/proj/src/a.js</path>\n<type>file</type>\n<content>\nCreated file\n</content>',
      );
      await tester.pumpWidget(_wrap(_row('write', call)));
      await tester.pumpAndSettle();
      expect(find.text('Write'), findsOneWidget);
      expect(find.text('src/a.js'), findsOneWidget);
      expect(find.text('+2 −0'), findsOneWidget);
      expect(find.textContaining('<path>'), findsNothing);
    });

    testWidgets('bash row shows the description, not the raw command', (
      tester,
    ) async {
      final call = _call(
        toolName: 'bash',
        argsRaw: '{"command":"npm run dev","description":"Start dev"}',
        result: 'ready\n[exit code: 0]',
      );
      await tester.pumpWidget(_wrap(_row('bash', call)));
      await tester.pumpAndSettle();
      expect(find.text('Bash'), findsOneWidget);
      expect(find.text('Start dev'), findsOneWidget);
    });

    testWidgets('todo row shows counts plus active item', (tester) async {
      final call = _call(
        toolName: 'todo_write',
        argsRaw:
            '{"todos":[{"content":"a","status":"completed"},{"content":"b","status":"in_progress"},{"content":"c","status":"pending"}]}',
        result: 'Updated todo list: 1 pending, 1 in progress, 1 completed.',
      );
      await tester.pumpWidget(_wrap(_row('todo_write', call)));
      await tester.pumpAndSettle();
      expect(find.text('Update to-do list'), findsOneWidget);
      expect(find.text('1/3 completed · b'), findsOneWidget);
    });

    testWidgets('error row shows the failure line', (tester) async {
      final call = _call(
        toolName: 'bash',
        argsRaw: '{"command":"npm run build"}',
        result: 'boom failed\nsecond line',
        status: ToolCallStatus.error,
      );
      await tester.pumpWidget(_wrap(_row('bash', call)));
      await tester.pumpAndSettle();
      expect(find.text('boom failed'), findsOneWidget);
    });
  });

  group('unifiedDiffText — DiffBlock.tsx buildRows/copyText parity', () {
    test('single edit flattens to path + del + add rows', () {
      const diffs = [
        diff_model.FileDiff(
          path: 'src/a.js',
          oldText: 'a\nb\n',
          newText: 'a\nB\n',
        ),
      ];
      expect(
        diff_model.unifiedDiffText(diffs),
        'src/a.js\n- a\n- b\n+ a\n+ B',
      );
    });

    test('create omits the removed side', () {
      const diffs = [
        diff_model.FileDiff(
          path: 'src/new.js',
          oldText: null,
          newText: 'x\n',
        ),
      ];
      expect(diff_model.unifiedDiffText(diffs), 'src/new.js\n+ x');
    });

    test('same-file second hunk opens with a gap, new file repeats path', () {
      const diffs = [
        diff_model.FileDiff(path: 'src/a.js', oldText: 'a', newText: 'b'),
        diff_model.FileDiff(path: 'src/a.js', oldText: 'c', newText: 'd'),
        diff_model.FileDiff(path: 'src/b.js', oldText: null, newText: 'e'),
      ];
      expect(
        diff_model.unifiedDiffText(diffs),
        'src/a.js\n- a\n+ b\n⋯\n- c\n+ d\nsrc/b.js\n+ e',
      );
    });
  });

  group('DiffToolCard expanded diff — FileMutationRow parity', () {
    Widget wrapCard(ToolCall call) => _wrap(DiffToolCard(call: call));

    testWidgets('settled edit with meta.diffs renders DsDiffBlock rows + footer', (
      tester,
    ) async {
      final call = _call(
        toolName: 'edit',
        argsRaw:
            '{"file_path":"src/a.js","old_string":"a\\nb\\n","new_string":"a\\nB\\n"}',
        result: 'ok',
        meta: {
          'diffs': [
            {'path': 'src/a.js', 'oldText': 'a\nb\n', 'newText': 'a\nB\n'},
          ],
        },
      );
      await tester.pumpWidget(wrapCard(call));
      await tester.pumpAndSettle();
      expect(find.byType(DsDiffBlock), findsOneWidget);
      // Banner header plus the body's own path row (React renders the path
      // as a body row; the banner is the shared block chrome).
      expect(find.text('src/a.js'), findsNWidgets(2));
      expect(find.text('- b'), findsOneWidget);
      expect(find.text('+ B'), findsOneWidget);
      expect(find.textContaining('└ +2 -2'), findsOneWidget);
    });

    testWidgets('running edit shows the intended args diff', (tester) async {
      final call = _call(
        toolName: 'edit',
        argsRaw:
            '{"file_path":"src/a.js","old_string":"a\\n","new_string":"b\\n"}',
        status: ToolCallStatus.running,
      );
      await tester.pumpWidget(wrapCard(call));
      await tester.pumpAndSettle();
      expect(find.byType(DsDiffBlock), findsOneWidget);
      expect(find.text('- a'), findsOneWidget);
      expect(find.text('+ b'), findsOneWidget);
      expect(find.textContaining('└ +1 -1'), findsOneWidget);
    });

    testWidgets('chat cap folds at 8 lines with head-tail slices', (
      tester,
    ) async {
      final lines = List.generate(12, (i) => 'l${i + 1}').join('\n');
      final call = _call(
        toolName: 'write',
        argsRaw: '{"path":"src/big.js","content":"seed"}',
        result: 'ok',
        meta: {
          'diffs': [
            {'path': 'src/big.js', 'oldText': null, 'newText': '$lines\n'},
          ],
        },
      );
      await tester.pumpWidget(wrapCard(call));
      await tester.pumpAndSettle();
      // 13 rows (path + 12 adds) cap at the chat 8: head 4 + tail 4.
      expect(find.text('+ l1'), findsOneWidget);
      expect(find.text('+ l4'), findsNothing);
      expect(find.text('+ l9'), findsOneWidget);
      expect(find.textContaining('其余 5'), findsOneWidget);
      await tester.tap(find.textContaining('其余'));
      await tester.pumpAndSettle();
      expect(find.text('+ l4'), findsOneWidget);
      expect(find.text('收起'), findsOneWidget);
    });
  });

  group('file summary tap — turn-tail preview chain parity', () {
    testWidgets('tap opens the in-app preview, never the host opener', (
      tester,
    ) async {
      final filesFake = _PreviewFakeClient();
      final call = _call(
        toolName: 'edit',
        argsRaw:
            '{"file_path":"src/a.js","old_string":"x\\n","new_string":"y\\n"}',
        result: 'ok',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionClientProvider.overrideWithValue(filesFake),
            canOpenHostPathProvider.overrideWith((ref) async => true),
          ],
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Scaffold(
              body: SingleChildScrollView(child: _row('edit', call)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyedToolCard)),
      );
      container.read(sessionsProvider.notifier).addSession(
            const SessionSummary(
              sessionId: SessionId('s1'),
              updatedAt: 1,
              running: false,
              blank: false,
              cwd: '/work/proj',
            ),
          );
      container
          .read(sessionsProvider.notifier)
          .setCurrent(const SessionId('s1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('src/a.js'));
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewDialog), findsOneWidget);
      expect(find.text('hello file'), findsOneWidget);
      expect(filesFake.openCalls, 0);
    });
  });
}

/// Answers `workspaceFiles/stat|read` for the preview chain and counts
/// Host-native opener ejections (which the preview-first tap must avoid).
class _PreviewFakeClient extends ConnectionClient {
  _PreviewFakeClient() : super(baseUrl: '');

  int openCalls = 0;

  @override
  Future<Map<String, dynamic>> callMethod(
    String method,
    Map<String, dynamic> payload,
  ) async {
    if (method == 'workspaceFiles/stat') {
      final path = (payload['path'] as String?) ?? '/work/proj/src/a.js';
      return {'absolutePath': path, 'version': 'v1'};
    }
    if (method == 'workspaceFiles/read') {
      final path = (payload['path'] as String?) ?? '/work/proj/src/a.js';
      return {
        'absolutePath': path,
        'version': 'v1',
        'offset': 1,
        'text': 'hello file',
        'lines': 1,
        'eof': true,
      };
    }
    throw UnsupportedError('unexpected callMethod $method in preview test');
  }

  @override
  Future<Map<String, dynamic>> openWorkspacePath({
    required String path,
  }) async {
    openCalls++;
    return {'opened': true};
  }
}
