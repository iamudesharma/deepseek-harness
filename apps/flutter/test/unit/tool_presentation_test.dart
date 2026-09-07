import 'package:dsh_flutter/src/plugins/tool/presentation/diff_model.dart';
import 'package:dsh_flutter/src/plugins/tool/presentation/path_utils.dart';
import 'package:dsh_flutter/src/plugins/tool/presentation/read_model.dart';
import 'package:dsh_flutter/src/plugins/tool/presentation/terminal_model.dart';
import 'package:dsh_flutter/src/plugins/tool/presentation/todo_model.dart';
import 'package:dsh_flutter/src/plugins/tool/presentation/tool_row_model.dart';
import 'package:dsh_flutter/src/plugins/tool/tool_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toolRowModel', () {
    test('write summary uses file_path input, never the result envelope', () {
      final model = toolRowModel(
        toolName: 'write',
        argsRaw: '{"file_path":"src/data/products.js","content":"a\\nb\\n"}',
        running: false,
        resultText: '<path>/abs/proj/src/data/products.js</path>\n<type>file</type>\n<content>\nCreated file\n</content>',
        cwd: '/abs/proj',
      );
      expect(model.variant, ToolRowVariant.write);
      expect(model.titleKey, 'tool.title.write');
      expect(model.summary, 'src/data/products.js');
      expect(model.filePath, 'src/data/products.js');
    });

    test('absolute path outside cwd stays absolute; home abbreviates', () {
      final model = toolRowModel(
        toolName: 'read',
        argsRaw: '{"file_path":"/Users/ada/notes.md"}',
        running: true,
        cwd: '/Volumes/ws',
        home: '/Users/ada',
      );
      expect(model.summary, '~/notes.md');
      expect(model.filePath, '~/notes.md');
    });

    test('others variant prefixes the wire tool name', () {
      final model = toolRowModel(
        toolName: 'mystery_tool',
        argsRaw: '{"foo":"bar"}',
        running: true,
      );
      expect(model.variant, ToolRowVariant.others);
      expect(model.summary, 'mystery_tool · bar');
    });

    test('non-JSON args fall back to the raw first line', () {
      const raw = '<path>/x/y.ts</path>';
      final model = toolRowModel(toolName: 'write', argsRaw: raw, running: true);
      expect(model.summary, raw);
      expect(model.filePath, isNull);
    });

    test('error rows carry the failure first line', () {
      final model = toolRowModel(
        toolName: 'bash',
        argsRaw: '{"command":"npm run build","description":"Build"}',
        running: false,
        isError: true,
        resultText: 'boom failed\nsecond line',
      );
      expect(model.state, ToolRowState.error);
      expect(model.errorSummary, 'boom failed');
    });

    test('search joins multiple queries', () {
      final model = toolRowModel(
        toolName: 'grep',
        argsRaw: '{"queries":["foo","bar\\nbaz"]}',
        running: true,
      );
      expect(model.summary, 'foo, bar');
    });
  });

  group('path_utils', () {
    test('relativizeToCwd strips root prefix and trailing slashes', () {
      expect(relativizeToCwd('a/b.ts', null), 'a/b.ts');
      expect(relativizeToCwd('/ws/src/a.ts', '/ws/'), 'src/a.ts');
      expect(relativizeToCwd('/other/a.ts', '/ws'), '/other/a.ts');
    });
  });

  group('diffModel', () {
    test('contentLineCount treats one trailing newline as terminator', () {
      expect(contentLineCount(''), 0);
      expect(contentLineCount('a'), 1);
      expect(contentLineCount('a\nb\n'), 2);
      expect(contentLineCount('a\nb'), 2);
    });

    test('create counts +88 −0 from args content', () {
      final content = List.filled(88, 'line').join('\n');
      final diffs = diffsFor(
        toolName: 'write',
        argsRaw: '{"file_path":"src/a.js","content":${_json(content)}}',
        running: false,
        meta: const {'diffs': []},
      );
      expect(diffs, hasLength(1));
      expect(diffStat(diffs!), '+88 −0');
    });

    test('settled update prefers applied meta hunks over args', () {
      final diffs = diffsFor(
        toolName: 'edit',
        argsRaw: '{"file_path":"a.ts","old_string":"x","new_string":"y\\nz"}',
        running: false,
        meta: const {
          'diffs': [
            {'path': 'a.ts', 'oldText': 'x', 'newText': 'y'},
          ],
        },
      );
      expect(diffStat(diffs!), '+1 −1');
    });

    test('settled edit with empty meta falls back to generic (null)', () {
      expect(
        diffsFor(
          toolName: 'edit',
          argsRaw: '{"file_path":"a","old_string":"x","new_string":"y"}',
          running: false,
          meta: const {'diffs': []},
        ),
        isNull,
      );
    });

    test('malformed meta is rejected', () {
      expect(narrowDiffs(null), isNull);
      expect(narrowDiffs(const {'diffs': 'nope'}), isNull);
      expect(
        narrowDiffs(const {
          'diffs': [
            {'path': 'a'},
          ],
        }),
        isNull,
      );
    });
  });

  group('terminalModel', () {
    test('parses exit-code marker and strips it from the body', () {
      final out = parseTerminalOutcome('hello\n[exit code: 1]');
      expect(out.exitCode, 1);
      expect(out.body, 'hello');
      expect(out.signal, isNull);
    });

    test('parses signal marker', () {
      final out = parseTerminalOutcome('out\n[killed by signal: SIGTERM]');
      expect(out.signal, 'SIGTERM');
      expect(out.exitCode, isNull);
    });

    test('background launches stay generic', () {
      expect(isBackgroundCall('{"command":"x","run_in_background":true}'), isTrue);
      expect(isBackgroundCall('{"command":"x"}'), isFalse);
    });

    test('description wins the summary', () {
      expect(
        terminalSummary('{"command":"npm run dev","description":"Start dev"}'),
        'Start dev',
      );
      expect(terminalSummary('{"command":"ls -la"}'), 'ls -la');
    });
  });

  group('todoModel', () {
    test('summarizes counts plus first active item', () {
      final s = summarizeTodos(
        '{"todos":[{"content":"a","status":"completed"},{"content":"b","status":"in_progress"},{"content":"c","status":"pending"}]}',
      );
      expect(s.done, 1);
      expect(s.total, 3);
      expect(s.text, '1/3 completed · b');
      expect(s.extra, 1);
    });

    test('missing list degrades to Todo update', () {
      expect(summarizeTodos('{}').head, 'Todo update');
    });
  });

  group('readModel', () {
    test('accepts the exact file envelope only', () {
      expect(
        isReadEnvelope('<path>p</path>\n<type>file</type>\n<content>\nbody\n</content>'),
        isTrue,
      );
      expect(isReadEnvelope('plain'), isFalse);
    });

    test('validates meta ordering and bounds', () {
      final model = narrowReadMeta(const {
        'path': 'a.ts',
        'offset': 1,
        'totalLines': 2,
        'lines': [
          {'number': 1, 'text': 'a'},
          {'number': 2, 'text': 'b'},
        ],
      });
      expect(model, isNotNull);
      expect(
        narrowReadMeta(const {
          'path': 'a.ts',
          'offset': 1,
          'totalLines': 1,
          'lines': [
            {'number': 2, 'text': 'b'},
          ],
        }),
        isNull,
      );
    });
  });

  group('toolModels decoding', () {
    test('decodeCallArgs preserves raw JSON and maps file_path', () {
      const raw = '{"file_path":"src/a.ts","content":"hi"}';
      final decoded = decodeCallArgs({'arguments': raw});
      expect(decoded.argsRaw, raw);
      expect(decoded.args['file_path'], 'src/a.ts');
    });

    test('decodeResult captures text, error code, and meta', () {
      final decoded = decodeResult({
        'message': {
          'content': [
            {
              'type': 'tool-result',
              'content': [
                {'type': 'text', 'text': 'Created file'},
              ],
            },
          ],
        },
        'meta': {
          'diffs': [],
        },
      });
      expect(decoded.text, 'Created file');
      expect(decoded.isError, isFalse);
      expect(decoded.meta, isNotNull);
    });

    test('kindForTool covers write/edit/web images', () {
      expect(kindForTool('write'), ToolCallKind.diff);
      expect(kindForTool('edit'), ToolCallKind.read == ToolCallKind.diff ? ToolCallKind.diff : ToolCallKind.diff);
      expect(kindForTool('web_search'), ToolCallKind.search);
      expect(kindForTool('web_fetch'), ToolCallKind.read);
      expect(kindForTool('pwsh'), ToolCallKind.bash);
    });
  });
}

String _json(String raw) {
  final escaped = raw.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n');
  return '"$escaped"';
}
