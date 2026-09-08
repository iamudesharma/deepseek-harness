/// `/model` contribution tests — options flatten the shared directory,
/// selection settles through it, failures surface loudly.
library;

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/model_selection/model_directory.dart';
import 'package:dsh_flutter/src/plugins/commands/command_service.dart'
    show SelectOption;
import 'package:dsh_flutter/src/plugins/model_selection/model_command.dart';
import 'package:dsh_flutter/src/plugins/model_selection/model_directory_service.dart';
import 'package:flutter_test/flutter_test.dart';

ConnectionClient _dummyClient() =>
    ConnectionClient(baseUrl: 'http://127.0.0.1:1');

/// Scripted directory: preset state, recorded selections.
class FakeModelDirectory extends ModelDirectory {
  FakeModelDirectory(this.preset) : super(_dummyClient(), SessionId('s1'));

  ModelDirectoryState preset;
  int loads = 0;
  final List<ModelSelection> selected = [];

  @override
  ModelDirectoryState get state => preset;

  @override
  Future<Map<String, dynamic>> load() async {
    loads++;
    return const {};
  }

  @override
  Future<void> select(ModelSelection selection) async {
    selected.add(selection);
  }
}

class FakeDirectories extends ModelDirectoryService {
  FakeDirectories(this.directory) : super(_dummyClient());

  final FakeModelDirectory directory;

  @override
  ModelDirectory directoryFor(SessionId sessionId) => directory;
}

ModelDirectoryState _state() => ModelDirectoryState(
  current: const ModelSelection(provider: 'p1', model: 'm1'),
  groups: const [
    ModelProviderGroup(
      id: 'p1',
      name: 'Provider One',
      models: [
        ModelInfo(id: 'm1', name: 'Model One'),
        ModelInfo(
          id: 'm2',
          name: 'Model Two',
          reasoning: ModelReasoning(
            efforts: [ModelReasoningEffort(id: 'high', name: 'High')],
            defaultEffort: 'high',
          ),
        ),
      ],
    ),
  ],
  status: 'ready',
);

void main() {
  test('contribution carries the snapshotted description', () {
    final c = buildModelContribution(
      FakeDirectories(FakeModelDirectory(_state())),
      'Select the model for this conversation',
    );
    expect(c.name, 'model');
    expect(c.description, 'Select the model for this conversation');
  });

  test('options flatten groups with the active mark', () async {
    final dir = FakeModelDirectory(_state());
    final c = buildModelContribution(FakeDirectories(dir), 'd');
    final options = await c.options!(SessionId('s1'));
    expect(options.map((o) => o.id), ['p1/m1', 'p1/m2']);
    expect(options.map((o) => o.label), ['Model One', 'Model Two']);
    expect(options.map((o) => o.detail), ['Provider One', 'Provider One']);
    expect(options.map((o) => o.active), [true, false]);
    expect(dir.loads, 1);
  });

  test('options throw when the catalog failed with no rows', () async {
    final dir = FakeModelDirectory(
      const ModelDirectoryState(status: 'error', error: 'boom'),
    );
    final c = buildModelContribution(FakeDirectories(dir), 'd');
    await expectLater(
      c.options!(SessionId('s1')),
      throwsA(isA<StateError>()),
    );
  });

  test('onSelect settles through the shared directory', () async {
    final dir = FakeModelDirectory(_state());
    final c = buildModelContribution(FakeDirectories(dir), 'd');
    final options = await c.options!(SessionId('s1'));
    await c.onSelect!(options[1], SessionId('s1'));
    expect(dir.selected, hasLength(1));
    expect(dir.selected.single.provider, 'p1');
    expect(dir.selected.single.model, 'm2');
    expect(dir.selected.single.reasoningEffort, 'high');
  });

  test('onSelect rejects failure and malformed rows', () async {
    final dir = FakeModelDirectory(_state());
    final c = buildModelContribution(FakeDirectories(dir), 'd');
    await expectLater(
      c.onSelect!(const SelectOption(id: 'failure/0', label: 'x'), SessionId('s1')),
      throwsStateError,
    );
    await expectLater(
      c.onSelect!(const SelectOption(id: 'malformed', label: 'x'), SessionId('s1')),
      throwsStateError,
    );
    expect(dir.selected, isEmpty);
  });
}
