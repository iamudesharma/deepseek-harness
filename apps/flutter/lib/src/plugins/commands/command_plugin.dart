/// The `ui-commands` plugin — Flutter port of
/// `packages/client/ui-commands/src/client/service.ts` plugin wiring: the
/// `commandUi` service over the session-keyed directory, and the `'/'` trigger
/// source registered into the input-trigger registry. Catalog invalidation
/// follows the forwarded host registry signal; a preset switch repulls exactly
/// that session's key.
library;

import 'dart:async';

import '../../core/connection/connection_client.dart';
import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/session/session_models.dart';
import '../../core/slots/slot_registry.dart';
import '../input_trigger/input_trigger_plugin.dart'
    show kInputTriggersServiceName;
import '../input_trigger/input_trigger_service.dart';
import '../input_trigger/trigger_source.dart';
import '../conversation/hub.dart' show ConversationController;
import 'command_directory.dart';
import 'command_service.dart';
import 'popup_select.dart' show TokenSegment;
import 'ui/popup_select_overlay.dart';

/// Plugin identity.
const String kCommandsPluginId = 'ui-commands';

/// Service name (React `ctx.commandUi`).
const String kCommandUiServiceName = 'commandUi';

/// The slash source's group name.
const String kCommandSourceName = 'command';

/// The `ui-commands` plugin.
class CommandsPlugin extends DshPlugin {
  /// Creates the plugin over an explicit executor (plan_control's
  /// constructor-injection pattern; defaults to the prompt-channel executor).
  const CommandsPlugin({CommandExecutor? executor}) : _executor = executor;

  final CommandExecutor? _executor;

  @override
  String get id => kCommandsPluginId;

  @override
  List<String> get inject => [
    'connection',
    'sessions',
    'slots',
    'remote',
    'conversation',
    'inputTriggers',
  ];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge.
    final client = ctx.require<ConnectionClient>('connection');
    ctx.require<SessionsService>('sessions');
    ctx.require<RemoteEventBus>('remote');
    ctx.require<ConversationController>('conversation');
    final inputTriggers = ctx.require<TriggerSourceRegistry>(
      kInputTriggersServiceName,
    );
    final remote = ctx.get<RemoteEventBus>('remote')!;

    final directory = CommandDirectory(
      fetchCommands: (sessionId) async {
        // `commands/list` host Typert method (`packages/interaction/commands`)
        // descriptor is `list(agent: Agent)` with `agent` lookup → wire
        // `agentId`. The carrier wraps the caller's wire fields in
        // `{args: {...}}` (see `ConnectionClient._postTypert`), so the caller
        // passes only the wire fields — never an outer `args` key, which
        // produces the host error `args fields do not match the descriptor:
        // missing 'agentId'; unexpected 'args'`.
        final value = await client.callMethod('commands/list', {
          'agentId': sessionId.value,
        });
        final raw =
            value['_list'] ??
            value['commands'] ??
            value['items'] ??
            value['value'];
        if (raw is List) {
          return raw
              .map(CommandDescriptor.tryFromJson)
              .whereType<CommandDescriptor>()
              .toList();
        }
        // Legacy shape where the map itself is the list wrapper (tests).
        if (value case {'_list': final List list}) {
          return list
              .map(CommandDescriptor.tryFromJson)
              .whereType<CommandDescriptor>()
              .toList();
        }
        return const [];
      },
    );
    final service = CommandUiService(
      directory: directory,
      execute: _executor ?? defaultCommandExecutor(client),
    );
    ctx.provide(kCommandUiServiceName, service);

    // The '/' trigger source: candidates merge host catalog + contributions;
    // picks route through the service decision tables; scope birth prewarms
    // the session's catalog.
    final disposeSource = inputTriggers.registerSource(
      _CommandSource(service, directory),
    );
    ctx.onDispose(disposeSource);

    // Registry-wide change → soft invalidate every touched key (ready
    // snapshots keep serving until the repull lands).
    final stopChange = remote.$on(
      'commands/change',
      (_) => directory.invalidateAll(),
    );
    // A preset switch changes which commands one session resolves and
    // registers nothing globally: repull that key alone, soft.
    final stopPreset = remote.$on('agent-preset/selected', (args) {
      if (args.isEmpty || args.first is! String) return;
      unawaited(directory.refresh(SessionId(args.first as String)));
    });

    // Widget bridge: the overlay seat resolves the service through this
    // global (bound at activation, cleared on teardown).
    bindActivatedCommandUi(service);

    // The popupSelect overlay waits for the conversation-owned overlay hole,
    // installs atomically, and leaves with this plugin (the MenuView entry
    // shares the anchor; list order refines by `order`).
    final stopOverlay = ctx.slots.inject('conversation.input.overlay', () {
      return [
        ctx.slots.register(
          const RegistrationOptions(
            name: 'conversation.input.overlay',
            id: 'ui-commands-popup',
            order: 20,
          ),
          (context, props) => const PopupSelectOverlay(),
        ),
      ];
    });

    ctx.onDispose(() {
      stopChange();
      stopPreset();
      bindActivatedCommandUi(null);
      service.disposePopups();
      disposeSource();
      stopOverlay();
      directory.clearAll();
    });
  }
}

class _CommandSource extends InputTriggerSource {
  _CommandSource(this._service, this._directory);

  final CommandUiService _service;
  final CommandDirectory _directory;

  @override
  TriggerChar get trigger => '/';

  @override
  String get name => kCommandSourceName;

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest request,
  ) {
    return _service.candidates(
      SessionId(sessionId),
      query: request.query,
      position: request.position,
    );
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    final name = pick.candidate.name;
    final sessionId = SessionId(pick.sessionId);
    if (_service.contributionNames.contains(name)) {
      // A popupSelect contribution opens its per-session shell over the
      // menu-path span (CAS-guarded consumption after a successful settle).
      final c = _service.contribution(name);
      if (c?.options != null && c!.available(sessionId)) {
        _service.openPopup(sessionId, name, TokenSegment.menu(span: pick.span));
      }
      return const HandledOutcome();
    }
    if (_directory.resolve(sessionId, name) == null) return null;
    final desc = _directory.resolve(sessionId, name)!;
    if (desc.hint != null || desc.images) {
      return ClaimOutcome(_leadingClaim(desc, sessionId));
    }
    // Menu-pick execute consumes the trigger span on the composer side once
    // the outcome sink is mounted; detached run starts regardless.
    unawaited(_detached(sessionId, '/$name'));
    return const HandledOutcome();
  }

  @override
  PickOutcome? matchSpace(String sessionId, String token) =>
      _service.matchSpace(SessionId(sessionId), token);

  @override
  void warm(String sessionId) => _directory.warm(SessionId(sessionId));

  CommandClaim _leadingClaim(CommandDescriptor desc, SessionId sessionId) {
    final token = '/${desc.name} ';
    return CommandClaim(
      token: token,
      hint: desc.hint,
      images: desc.images,
      submit: (args, images) async {
        final outcome = await _service.execute(sessionId, '$token$args');
        return SubmitOutcome(
          kind: outcome.ok ? 'success' : 'error',
          text: outcome.text,
        );
      },
    );
  }

  Future<void> _detached(SessionId sessionId, String line) async {
    try {
      await _service.execute(sessionId, line);
    } catch (_) {}
  }
}
