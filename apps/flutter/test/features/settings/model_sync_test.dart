import 'package:dsh_flutter/src/core/connection/connection_client.dart'
    show ConnectionClient, connectionClientProvider, connectionStateProvider;
import 'package:dsh_flutter/src/core/services/remote_event_bus.dart'
    show remoteBusProvider;
import 'package:dsh_flutter/src/features/model_selection/model_directory.dart';
import 'package:dsh_flutter/src/features/settings_models/models_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _group(String id, List<String> models) => {
  'id': id,
  'name': id,
  'models': [
    for (final m in models)
      {'id': m, 'name': m},
  ],
};

/// Fake Host answering the global catalog + provider directory from mutable
/// fields, so a test can change the Host topology mid-test like an upstream
/// model add/remove.
class _FakeModelClient extends ConnectionClient {
  _FakeModelClient() : super(baseUrl: '');

  int catalogCalls = 0;
  int providersCalls = 0;
  List<Map<String, dynamic>> catalogGroups = [];
  List<Map<String, dynamic>> liveProviders = [];

  @override
  Future<Map<String, dynamic>> sessionModelCatalog() async {
    catalogCalls++;
    return {
      'default': {'provider': 'deepseek', 'model': 'deepseek-chat'},
      'groups': catalogGroups,
      'failures': const [],
      'routableProviders': const ['deepseek'],
    };
  }

  @override
  Future<Map<String, dynamic>> sessionModels({
    required String sessionId,
  }) async {
    throw UnimplementedError('per-session endpoint removed');
  }

  @override
  Future<List<Map<String, dynamic>>> llmListProviders() async {
    providersCalls++;
    return liveProviders;
  }

  @override
  Future<List<Map<String, dynamic>>> llmListConfigurableProviders() async =>
      const [];

  @override
  Future<Map<String, dynamic>> settingsDescribe() async => {
    'writable': false,
    'namespaces': const [],
  };

  @override
  Future<Map<String, dynamic>> credentialsDescribe(List<String> refs) async =>
      const {'credentials': {}};
}

ProviderContainer _container(_FakeModelClient client) {
  final container = ProviderContainer(
    overrides: [connectionClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _waitFor(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  expect(cond(), isTrue);
}

List<String> _modelIds(ModelDirectoryState state) => [
  for (final g in state.groups)
    for (final m in g.models) '${g.id}/${m.id}',
];

void main() {
  test('llm/adapters-updated refreshes the session catalog', () async {
    final client = _FakeModelClient()
      ..catalogGroups = [_group('deepseek', ['deepseek-chat', 'deepseek-reasoner'])];
    final container = _container(client);

    container.read(modelDirectoryProvider('s1'));
    await _waitFor(
      () =>
          client.catalogCalls >= 1 &&
          container.read(modelDirectoryProvider('s1')).status == 'ready',
    );
    expect(
      _modelIds(container.read(modelDirectoryProvider('s1'))),
      contains('deepseek/deepseek-reasoner'),
    );

    // Upstream removes deepseek-reasoner and adds deepseek-v4.
    client.catalogGroups = [_group('deepseek', ['deepseek-chat', 'deepseek-v4'])];
    container.read(remoteBusProvider).dispatch('llm/adapters-updated', []);
    await _waitFor(() => client.catalogCalls >= 2);
    await _waitFor(
      () => _modelIds(
        container.read(modelDirectoryProvider('s1')),
      ).contains('deepseek/deepseek-v4'),
    );
    expect(
      _modelIds(container.read(modelDirectoryProvider('s1'))),
      isNot(contains('deepseek/deepseek-reasoner')),
    );
  });

  test('settings and credentials pushes refresh the session catalog', () async {
    final client = _FakeModelClient()
      ..catalogGroups = [_group('deepseek', ['deepseek-chat'])];
    final container = _container(client);

    container.read(modelDirectoryProvider('s1'));
    await _waitFor(() => client.catalogCalls >= 1);
    expect(client.catalogCalls, 1);

    final bus = container.read(remoteBusProvider);
    bus.dispatch('settings/document-updated', []);
    bus.dispatch('credentials/reference-updated', []);
    await _waitFor(() => client.catalogCalls >= 3);
  });

  test('reconnect reloads a loaded session catalog', () async {
    final client = _FakeModelClient()
      ..catalogGroups = [_group('deepseek', ['deepseek-chat'])];
    final container = _container(client);

    container.read(modelDirectoryProvider('s1'));
    await _waitFor(() => client.catalogCalls >= 1);

    client.catalogGroups = [_group('deepseek', ['deepseek-chat', 'deepseek-v4'])];
    container.read(connectionStateProvider.notifier).markConnected();
    await _waitFor(() => client.catalogCalls >= 2);
    await _waitFor(
      () => _modelIds(
        container.read(modelDirectoryProvider('s1')),
      ).contains('deepseek/deepseek-v4'),
    );
  });

  test('refresh failure keeps the last-good list with a retry error', () async {
    final client = _FailingCatalogClient()
      ..catalogGroups = [_group('deepseek', ['deepseek-chat'])];
    final container = _container(client);

    container.read(modelDirectoryProvider('s1'));
    await _waitFor(
      () => container.read(modelDirectoryProvider('s1')).status == 'ready',
    );
    expect(
      _modelIds(container.read(modelDirectoryProvider('s1'))),
      contains('deepseek/deepseek-chat'),
    );

    container.read(remoteBusProvider).dispatch('llm/adapters-updated', []);
    await _waitFor(
      () => container.read(modelDirectoryProvider('s1')).error != null,
    );
    // Last-good groups stay on screen beside the retry error.
    expect(
      _modelIds(container.read(modelDirectoryProvider('s1'))),
      contains('deepseek/deepseek-chat'),
    );
  });

  test('models settings reloads providers on document-updated', () async {
    final client = _FakeModelClient()
      ..liveProviders = [
        {'id': 'deepseek-official', 'name': 'DeepSeek'},
      ];
    final container = _container(client);

    await container.read(modelsSettingsControllerProvider.notifier).load();
    expect(
      container
          .read(modelsSettingsControllerProvider)
          .rows
          .map((r) => r.entry.provider),
      contains('deepseek-official'),
    );
    expect(client.providersCalls, 1);

    client.liveProviders = [
      {'id': 'deepseek-official', 'name': 'DeepSeek'},
      {'id': 'opencode', 'name': 'OpenCode'},
    ];
    container.read(remoteBusProvider).dispatch('settings/document-updated', []);
    await _waitFor(() => client.providersCalls >= 2);
    await _waitFor(
      () => container
          .read(modelsSettingsControllerProvider)
          .rows
          .map((r) => r.entry.provider)
          .contains('opencode'),
    );
  });
}

/// Catalog succeeds once, then fails — exercises the keep-last-good path.
class _FailingCatalogClient extends _FakeModelClient {
  bool failNext = false;

  @override
  Future<Map<String, dynamic>> sessionModelCatalog() async {
    if (failNext) throw Exception('catalog unavailable');
    final value = await super.sessionModelCatalog();
    failNext = true;
    return value;
  }
}
