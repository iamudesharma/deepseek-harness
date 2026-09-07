import 'package:dsh_flutter/src/core/plugin/plugin_contract.dart';
import 'package:dsh_flutter/src/core/plugin/plugin_host.dart';
import 'package:dsh_flutter/src/core/slots/slot_registry.dart';
import 'package:flutter_test/flutter_test.dart';

final List<String> applicationOrder = [];

class _RecordingPlugin extends DshPlugin {
  _RecordingPlugin(this.id, {this.inject = const [], this.provides});

  @override
  final String id;

  @override
  final List<String> inject;

  /// Service name this plugin provides during apply, when set.
  final String? provides;

  var disposedViaContext = false;

  @override
  Future<void> apply(DshContext ctx) async {
    applicationOrder.add(id);
    if (provides != null) ctx.provide(provides!, Object());
    ctx.onDispose(() => disposedViaContext = true);
  }
}

void main() {
  setUp(applicationOrder.clear);

  test(
    'activation waits on injected services regardless of registration order',
    () async {
      final host = PluginHost();
      host.provide('slots', host.slots);
      host.register(
        _RecordingPlugin(
          'ui-conversation',
          inject: ['slots', 'layout'],
          provides: 'conversation',
        ),
      );
      host.register(_RecordingPlugin('ui-layout', provides: 'layout'));

      await host.activateAll();

      expect(applicationOrder, ['ui-layout', 'ui-conversation']);
      expect(host.hasService('layout'), isTrue);
      expect(host.hasService('conversation'), isTrue);
    },
  );

  test('deactivation removes contributions and provided services', () async {
    final host = PluginHost();
    host.provide('slots', host.slots);

    // ui-layout owns root's single cell; ui-shell occupies the declared child
    // hole — the composition shape every business plugin uses.
    final layout = _DeclaringPlugin('ui-layout');
    final shell = _RegisteringIntoPlugin(
      'ui-shell',
      'app.frame',
      'shell-widget',
    );
    host.register(layout);
    host.register(shell);

    await host.activateAll();

    // Deactivating only the occupant leaves the declaration intact.
    host.deactivate('ui-shell');
    expect(host.slots.entries('app.frame'), isEmpty);
    expect(host.slots.isDeclared('app.frame'), isTrue);
    expect(shell.disposedViaContext, isTrue);

    // Deactivating the declarer collapses declared children.
    host.deactivate('ui-layout');
    expect(host.slots.isDeclared('app.frame'), isFalse);
    expect(layout.disposedViaContext, isTrue);
  });

  test(
    'unsatisfiable injections fail loud naming the missing services',
    () async {
      final host = PluginHost();
      host.provide('slots', host.slots);
      host.register(_RecordingPlugin('orphan', inject: ['sessions']));

      await expectLater(
        host.activateAll(),
        throwsA(
          predicate(
            (e) => e is StateError && e.toString().contains('"sessions"'),
          ),
        ),
      );
    },
  );

  test('duplicate plugin ids throw at register', () {
    final host = PluginHost();
    host.register(_RecordingPlugin('same'));
    expect(() => host.register(_RecordingPlugin('same')), throwsStateError);
  });

  test('require fails loud for absent services; get stays nullable', () async {
    final host = PluginHost();
    host.provide('slots', host.slots);
    final probe = _ProbePlugin('probe');
    host.register(probe);

    await host.activateAll();

    expect(probe.optionalResult, isNull);
    expect(probe.requiredError, isA<StateError>());
  });
}

/// Declares `root` with an `app.frame` child, the shell-shaped plugin.
class _DeclaringPlugin extends DshPlugin {
  _DeclaringPlugin(String id) : _id = id;

  final String _id;

  @override
  String get id => _id;

  var disposedViaContext = false;

  @override
  Future<void> apply(DshContext ctx) async {
    applicationOrder.add(id);
    final disposeEntry = ctx.slots.register(
      const RegistrationOptions(
        name: 'root',
        children: {
          'app.frame': SlotSpec(kind: SlotKind.single, scope: SlotScope.root),
        },
      ),
      'frame-component',
    );
    ctx.onDispose(disposeEntry);
    ctx.onDispose(() => disposedViaContext = true);
  }
}

class _RegisteringIntoPlugin extends DshPlugin {
  _RegisteringIntoPlugin(String id, this.slot, this.component) : _id = id;

  final String _id;

  @override
  String get id => _id;

  final String slot;
  final Object component;
  var disposedViaContext = false;

  @override
  Future<void> apply(DshContext ctx) async {
    applicationOrder.add(_id);
    ctx.onDispose(
      ctx.slots.register(RegistrationOptions(name: slot), component),
    );
    ctx.onDispose(() => disposedViaContext = true);
  }
}

class _ProbePlugin extends DshPlugin {
  _ProbePlugin(String id) : id = id;

  @override
  final String id;

  Object? optionalResult;
  Object? requiredError;

  @override
  Future<void> apply(DshContext ctx) async {
    applicationOrder.add(id);
    optionalResult = ctx.get<Object>('nothing');
    try {
      ctx.require<Object>('nothing');
    } catch (error) {
      requiredError = error;
    }
  }
}
