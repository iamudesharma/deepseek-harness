import 'package:dsh_flutter/src/plugins/tool/tool_models.dart';
import 'package:dsh_flutter/src/plugins/tool/ui/keyed_tool_card.dart';
import 'package:dsh_flutter/src/plugins/conversation/hub.dart' show ChatNodeData;
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
}
