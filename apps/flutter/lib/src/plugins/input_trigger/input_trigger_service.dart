/// InputTriggerService (`ctx.inputTriggers`) — the root half of the trigger
/// pipeline, Dart port of `packages/client/ui-input-trigger/src/client/
/// service.ts`: the stateless source registry plus the per-session controller
/// map. Every piece of mutable interaction state lives on
/// [InputTriggerController]; the service only registers sources, resolves
/// controllers by session id, and relays roster changes.
library;

import 'input_trigger_controller.dart';
import 'trigger_source.dart';

/// The trigger pipeline service: root registry + controller resolution.
/// Provided as the `'inputTriggers'` service.
class TriggerSourceRegistry implements SourceRoster {
  final List<InputTriggerSource> _sources = [];
  final Map<String, InputTriggerController> _controllers = {};

  /// Register one trigger source. Live session controllers are notified so a
  /// source arriving after scope birth still warms and joins the lexicon.
  ///
  /// Duplicate `(trigger, name)` pairs throw. Returns the disposer removing
  /// this source; disposal while a controller shows the source's menu group
  /// drops that group.
  void Function() registerSource(InputTriggerSource src) {
    for (final s in _sources) {
      if (s.trigger == src.trigger && s.name == src.name) {
        throw StateError(
          'slash source "${src.trigger}${src.name}" is already registered',
        );
      }
    }
    _sources.add(src);
    for (final controller in List.of(_controllers.values)) {
      try {
        controller.sourceAdded(src);
      } catch (error) {
        // Contain faulty source callbacks (warm/subscribeLexicon): the
        // registration must stand with a usable disposer and the remaining
        // controllers must still be notified.
        assert(() {
          // ignore: avoid_print
          print(
            '[ui-input-trigger] source "${src.trigger}${src.name}" '
            'late-registration setup failed: $error',
          );
          return true;
        }());
      }
    }
    return () {
      final at = _sources.indexOf(src);
      if (at < 0) return;
      _sources.removeAt(at);
      for (final controller in List.of(_controllers.values)) {
        controller.sourceRemoved(src);
      }
    };
  }

  @override
  List<InputTriggerSource> sources(TriggerChar trigger) {
    final matching = _sources.where((s) => s.trigger == trigger).toList();
    matching.sort((a, b) => a.order.compareTo(b.order));
    return matching;
  }

  @override
  List<InputTriggerSource> all() => List.unmodifiable(_sources);

  /// Live per-session controllers (read-only view for widget layers).
  Map<String, InputTriggerController> get controllers =>
      Map.unmodifiable(_controllers);

  /// Resolve the per-session controller for [sessionId] (lazy). Construction
  /// warms the source roster once — scope birth is the single prewarm moment.
  /// The Flutter host has no session-scoped fiber, so disposal is explicit:
  /// session teardown calls [disposeController].
  InputTriggerController controllerFor(String sessionId, {OutcomeSink? sink}) {
    final existing = _controllers[sessionId];
    if (existing != null) return existing;
    final controller = InputTriggerController(
      sessionId: sessionId,
      roster: this,
      sink: sink,
    );
    _controllers[sessionId] = controller;
    return controller;
  }

  /// Dispose and forget one session's controller.
  void disposeController(String sessionId) {
    _controllers.remove(sessionId)?.dispose();
  }

  /// Drop every controller (plugin teardown).
  void disposeAllControllers() {
    for (final id in List.of(_controllers.keys)) {
      disposeController(id);
    }
  }
}

TriggerSourceRegistry? _activatedRegistry;

/// Currently bound trigger registry (null before first activation) — the
/// widget-layer bridge, mirroring the conversation hub's activated-hub
/// binding.
TriggerSourceRegistry? get activatedRegistry => _activatedRegistry;

/// Binds (or clears) the widget-visible registry.
void bindActivatedRegistry(TriggerSourceRegistry? registry) {
  _activatedRegistry = registry;
}
