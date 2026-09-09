import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/settings/settings_scope.dart';
import 'package:dsh_flutter/src/features/settings_plugins/cards/subagent_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake scope face answering one namespace section like `settings.describe`.
class _FakeScopeFace implements SettingsFace {
  Map<String, Object?> section = {
    'value': {
      'enabled': false,
      'allowedModels': <Map<String, Object?>>[],
    },
    'revision': 4,
    'writable': true,
  };

  final List<Map<String, Object?>> batches = [];

  @override
  Future<Map<String, Object?>> describe() async => {
    'namespaces': [
      {'ns': 'subagent-model-selection', ...section},
    ],
  };

  @override
  Future<Map<String, Object?>> mutate({
    required String ns,
    required List<Map<String, Object?>> ops,
    int? expectedRevision,
  }) async {
    batches.add({
      'ns': ns,
      'ops': ops,
      'expectedRevision': expectedRevision,
    });
    for (final op in ops) {
      if (op['op'] == 'set') {
        final path = op['path'] as List;
        (section['value'] as Map)[path.single] = op['value'];
      }
    }
    section = {
      ...section,
      'revision': ((section['revision'] as int?) ?? 0) + 1,
    };
    return {'namespace': section};
  }
}

class _FakeCatalogClient extends ConnectionClient {
  _FakeCatalogClient() : super(baseUrl: '');

  @override
  Future<Map<String, dynamic>> sessionModelCatalog() async => {
    'groups': [
      {
        'id': 'deepseek',
        'name': 'DeepSeek',
        'models': [
          {'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
        ],
      },
    ],
    'failures': const [],
  };
}

Future<void> _waitFor(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(cond(), isTrue);
}

void main() {
  test('save writes enabled plus allowedModels atomically at the draft fence', () async {
    final face = _FakeScopeFace();
    final scope = SettingsScope<Map<String, Object?>>(
      face: face,
      namespace: 'subagent-model-selection',
      decode: (raw) => Map<String, Object?>.from(raw),
    );
    await scope.refreshFromDescribe();
    final controller = SubagentController(
      scope: scope,
      client: _FakeCatalogClient(),
    );
    addTearDown(controller.dispose);

    controller.toggleEnabled();
    await _waitFor(() => controller.state.catalogStatus == 'ready');
    controller.toggleModel('deepseek\x00deepseek-chat');
    await controller.save();

    // One atomic batch (React: single mutate with both path ops), fenced at
    // the revision captured when the draft opened — not re-read at save.
    expect(face.batches, hasLength(1));
    final batch = face.batches.single;
    expect(batch['ns'], 'subagent-model-selection');
    expect(batch['expectedRevision'], 4);
    expect(batch['ops'], [
      {
        'op': 'set',
        'path': ['enabled'],
        'value': true,
      },
      {
        'op': 'set',
        'path': ['allowedModels'],
        'value': [
          {'provider': 'deepseek', 'model': 'deepseek-chat'},
        ],
      },
    ]);
    expect(controller.state.dirty, isFalse);
    expect(controller.state.failed, isFalse);
  });

  test('save refuses an enabled-but-empty selection like React invalid', () async {
    final face = _FakeScopeFace();
    final scope = SettingsScope<Map<String, Object?>>(
      face: face,
      namespace: 'subagent-model-selection',
      decode: (raw) => Map<String, Object?>.from(raw),
    );
    await scope.refreshFromDescribe();
    final controller = SubagentController(
      scope: scope,
      client: _FakeCatalogClient(),
    );
    addTearDown(controller.dispose);

    controller.toggleEnabled();
    await controller.save();

    expect(face.batches, isEmpty);
    expect(controller.state.invalid, isTrue);
  });
}
