/// CommandUiService — Dart port of the `ui-commands` service face
/// (`packages/client/ui-commands/src/client/service.ts`), trimmed to what this
/// workstream grounds: the client-contribution registry, the '/' trigger
/// source over the session-keyed directory, and command execution through
/// `session.prompt` (a '/'-prefixed single text block executes through the
/// host command registry, never reaching the model).
///
/// The React popupSelect shell (per-session popups, decorations replacing bare
/// invocations) is a deferred seat: contributions/decorations register and
/// surface in candidates today; their popup UI mounts with the overlay
/// workstream.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/connection/connection_client.dart';
import '../../core/session/session_models.dart';
import '../input_trigger/input_trigger_plugin.dart'
    show kInputTriggersServiceName;
import '../input_trigger/trigger_source.dart';
import 'command_directory.dart';
import 'popup_select.dart';

/// Copy for an option that must be acknowledged before onSelect can run
/// (port of `SelectConfirmation`).
class SelectConfirmation {
  /// Creates the copy bundle.
  const SelectConfirmation({
    required this.title,
    required this.description,
    required this.acknowledgeLabel,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  /// Gate headline.
  final String title;

  /// Gate body.
  final String description;

  /// Checkbox label.
  final String acknowledgeLabel;

  /// Back-out label (returns to the picker).
  final String cancelLabel;

  /// Settle label (enabled once acknowledged).
  final String confirmLabel;
}

/// One option row of a popupSelect shell (port of `SelectOption`).
class SelectOption {
  /// Creates a row.
  const SelectOption({
    required this.id,
    required this.label,
    this.detail,
    this.active = false,
    this.confirmation,
  });

  /// Stable row id.
  final String id;

  /// Primary display text.
  final String label;

  /// Secondary line.
  final String? detail;

  /// Whether the row renders as currently active/enabled state.
  final bool active;

  /// Optional in-page risk gate owned by the shared popup shell.
  final SelectConfirmation? confirmation;
}

/// One client-owned command contribution: a slash-menu entry whose behavior
/// lives entirely on this client. Merged with the host catalog by name — a
/// collision fails loud at candidate synthesis, never shadows.
class CommandContribution {
  /// Creates a contribution. A popupSelect contribution carries both
  /// [options] and [onSelect]; a plain execution contribution carries
  /// neither (validated at [CommandUiService.register]).
  const CommandContribution({
    required this.name,
    required this.description,
    required this.available,
    this.options,
    this.onSelect,
  });

  /// Command name without the leading slash (unique across contributions).
  final String name;

  /// Menu row description.
  final String description;

  /// Capability filter, called per candidate pass.
  final bool Function(SessionId sessionId) available;

  /// popupSelect spec: load the option rows once per shell open.
  final Future<List<SelectOption>> Function(SessionId sessionId)? options;

  /// popupSelect spec: settle the picked option against the open-time session.
  final Future<void> Function(SelectOption option, SessionId sessionId)?
  onSelect;
}

/// Extra weight for command-name starts and separator boundaries
/// (`fuzzyScore`'s boundaryBonus).
int _boundaryBonus(String name, int index) =>
    index == 0 || name[index - 1] == '-' || name[index - 1] == '_' ? 8 : 0;

/// Score the strongest ordered-subsequence alignment in O(name × query)
/// (verbatim port of `fuzzyScore`). Null when [query] cannot align.
double? fuzzyScore(String name, String query) {
  if (query.isEmpty) return 0;
  if (query.length > name.length) return null;
  const noMatch = double.negativeInfinity;
  var previous = List<double>.filled(name.length, noMatch);
  for (var index = 0; index < name.length; index++) {
    if (name[index] == query[0]) {
      previous[index] = 1.0 + _boundaryBonus(name, index) - index;
    }
  }
  for (var queryIndex = 1; queryIndex < query.length; queryIndex++) {
    final current = List<double>.filled(name.length, noMatch);
    var bestGapped = noMatch;
    for (var index = 0; index < name.length; index++) {
      final gappedIndex = index - 2;
      if (gappedIndex >= 0 && gappedIndex < previous.length) {
        final prior = previous[gappedIndex];
        if (prior != noMatch)
          bestGapped = bestGapped > prior + gappedIndex
              ? bestGapped
              : prior + gappedIndex;
      }
      if (name[index] != query[queryIndex]) continue;
      final bonus = 1.0 + _boundaryBonus(name, index);
      final adjacent = index > 0 ? previous[index - 1] : noMatch;
      if (adjacent != noMatch) current[index] = adjacent + bonus + 4;
      if (bestGapped != noMatch) {
        final gapped = bestGapped + bonus + 1 - index;
        if (!(current[index] > gapped)) current[index] = gapped;
      }
    }
    previous = current;
  }
  var best = noMatch;
  for (final score in previous) {
    if (score > best) best = score;
  }
  return best == noMatch ? null : best;
}

class _Ranked {
  _Ranked(this.candidate, this.index, this.prefix, this.score);
  final InputTriggerCandidate candidate;
  final int index;
  final bool prefix;
  final double score;
}

/// Case-insensitive fuzzy filtering with stable ordering: prefix matches
/// first, then score, then source position (port of `fuzzyCandidates`).
List<InputTriggerCandidate> fuzzyCandidates(
  List<InputTriggerCandidate> candidates,
  String rawQuery,
) {
  final query = rawQuery.toLowerCase();
  if (query.isEmpty) return candidates;
  final ranked = <_Ranked>[];
  candidates.asMap().forEach((index, candidate) {
    final name = candidate.name.toLowerCase();
    final score = fuzzyScore(name, query);
    if (score != null) {
      ranked.add(_Ranked(candidate, index, name.startsWith(query), score));
    }
  });
  ranked.sort((left, right) {
    final byPrefix = (right.prefix ? 1 : 0).compareTo(left.prefix ? 1 : 0);
    if (byPrefix != 0) return byPrefix;
    final byScore = right.score.compareTo(left.score);
    if (byScore != 0) return byScore;
    return left.index.compareTo(right.index);
  });
  return [for (final match in ranked) match.candidate];
}

/// One settled execution outcome (plan_control's CommandOutcome mapping):
/// admitted success carries the host's optional success text; failures carry
/// a user-visible line.
class CommandExecutionOutcome {
  const CommandExecutionOutcome._({required this.ok, this.text});

  /// Admitted execution (the durable lifecycle renders as a flow node).
  factory CommandExecutionOutcome.success([String? text]) =>
      CommandExecutionOutcome._(ok: true, text: text);

  /// Refused or failed execution; [text] is the composer notice.
  factory CommandExecutionOutcome.error(String text) =>
      CommandExecutionOutcome._(ok: false, text: text);

  /// Whether the line was admitted and executed.
  final bool ok;

  /// Optional feedback text.
  final String? text;
}

/// Executes one slash line for a session over the connection's prompt channel.
typedef CommandExecutor = Future<CommandExecutionOutcome> Function(
  SessionId sessionId,
  String line,
);

/// Builds the default executor over [client]: `session.prompt` with a single
/// text block starting with '/'. Mapping (mirrors plan_control.dart):
/// an ok response carrying the `command` slot is an admitted execution; an ok
/// without it means the line was delivered as an ordinary prompt; an RPC
/// failure maps `unknown-command` to the plan-matching unknown line and every
/// other code to `'message (code)'`.
CommandExecutor defaultCommandExecutor(ConnectionClient client) {
  return (sessionId, line) async {
    try {
      final value = await client.callMethod('session/prompt', {
        'requestId': newRpcId(),
        'sessionId': sessionId.value,
        'mode': 'queue',
        'content': [
          {'type': 'text', 'text': line},
        ],
      });
      if (value['command'] is Map) {
        final command = value['command'] as Map;
        final kind = command['kind'];
        if (kind == 'success') {
          final text = command['text'];
          return CommandExecutionOutcome.success(text is String ? text : null);
        }
        final errText = command['text'];
        return CommandExecutionOutcome.error(
          errText is String ? errText : '/$line failed',
        );
      }
      // plan_control's mapping: an ok response without the admission slot
      // maps to the unknown-command line.
      return CommandExecutionOutcome.error('unknown command: $line');
    } on Exception catch (error) {
      final message = error.toString();
      if (message.contains('unknown-command')) {
        return CommandExecutionOutcome.error('unknown command: $line');
      }
      return CommandExecutionOutcome.error(message);
    } catch (error) {
      return CommandExecutionOutcome.error(error.toString());
    }
  };
}

/// The `'commandUi'` service: contribution registry + '/' source behavior +
/// execution.
class CommandUiService {
  /// Creates the service over its directory and executor.
  CommandUiService({
    required CommandDirectory directory,
    required CommandExecutor execute,
  }) : _directory = directory,
       execute = execute;

  final CommandDirectory _directory;

  /// The bound execution channel (the `command.execute` transaction slice).
  final CommandExecutor execute;

  final Map<String, CommandContribution> _contributions = {};

  /// Register one client command contribution; duplicate names throw, and a
  /// half-specified popupSelect spec (options without onSelect or vice versa)
  /// throws — misconfiguration fails loud at registration. Returns the
  /// disposer removing the registration.
  void Function() register(CommandContribution contribution) {
    if (_contributions.containsKey(contribution.name)) {
      throw StateError(
        'ui-commands: duplicate contribution for /${contribution.name}',
      );
    }
    if ((contribution.options == null) != (contribution.onSelect == null)) {
      throw StateError(
        'ui-commands: contribution /${contribution.name} specifies only '
        'one popupSelect half; options and onSelect are registered together',
      );
    }
    _contributions[contribution.name] = contribution;
    return () => _contributions.remove(contribution.name);
  }

  /// Registered contribution names (diagnostics).
  Iterable<String> get contributionNames => _contributions.keys;

  /// One contribution by name, or null.
  CommandContribution? contribution(String name) => _contributions[name];

  /// Menu candidates: host catalog + contribution availability, then position
  /// filtering and fuzzy name ranking. A contribution colliding with a host
  /// command fails loud (never shadows).
  Future<List<InputTriggerCandidate>> candidates(
    SessionId sessionId, {
    required String query,
    required TriggerPosition position,
  }) async {
    final list = await _directory.ensureReady(
      sessionId,
      deadline: DateTime.now().add(const Duration(seconds: 10)),
    );
    final rows = <InputTriggerCandidate>[];
    final seen = <String>{};
    for (final c in list) {
      seen.add(c.name);
      rows.add(
        InputTriggerCandidate(
          name: c.name,
          description: c.description,

          hint: c.hint,
        ),
      );
    }
    for (final contribution in _contributions.values) {
      if (!contribution.available(sessionId)) continue;
      if (seen.contains(contribution.name)) {
        throw StateError(
          'ui-commands: contribution /${contribution.name} collides with a host command',
        );
      }
      rows.add(
        InputTriggerCandidate(
          name: contribution.name,
          description: contribution.description,
        ),
      );
    }
    return fuzzyCandidates([
      // Input-taking commands stay out of inline (non-leading) menus.
      for (final c in rows)
        if (position == TriggerPosition.leading || c.hint == null) c,
    ], query);
  }

  /// Synchronous space-time adjudication: only a hot, resolvable host command
  /// with advertised input claims the leading token. Returns null otherwise.
  PickOutcome? matchSpace(SessionId sessionId, String token) {
    if (!token.startsWith('/')) return null;
    final name = token.substring(1);
    if (_contributions.containsKey(name))
      return null; // popup kinds never claim
    final desc = _directory.resolve(sessionId, name);
    // A descriptor without advertised input never claims.
    if (desc == null || (desc.hint == null && !desc.images)) return null;
    return ClaimOutcome(_leadingClaim(desc, sessionId));
  }

  /// Enter-time adjudication over the trimmed draft line: contributions act on
  /// the bare token only; input-taking host commands claim args-tolerant; a
  /// bare host command without input detaches to execution immediately.
  Future<PickOutcome?> matchEnter(SessionId sessionId, String line) async {
    final trimmed = line.trim();
    if (!trimmed.startsWith('/')) return null;
    final ws = trimmed.indexOf(RegExp(r'\s'));
    final token = ws == -1 ? trimmed : trimmed.substring(0, ws);
    final bare = ws == -1;
    final name = token.substring(1);
    if (name.isEmpty) return null;
    final contribution = _contributions[name];
    if (contribution != null && contribution.available(sessionId)) {
      if (!bare) return null;
      // A popupSelect contribution opens its per-session shell over the
      // enter-path segment (the input side consumes the bare token after a
      // successful settle); a spec-less contribution just closes.
      if (contribution.options != null) {
        openPopup(sessionId, name, TokenSegment.enter(token: token));
      }
      return const HandledOutcome();
    }
    final desc = _directory.resolve(sessionId, name);
    if (desc == null) return null;
    if (desc.hint != null || desc.images) {
      return ClaimOutcome(_leadingClaim(desc, sessionId));
    }
    if (!bare) return null;
    unawaited(_runDetached(sessionId, trimmed));
    return const HandledOutcome();
  }

  CommandClaim _leadingClaim(CommandDescriptor desc, SessionId sessionId) {
    final token = '/${desc.name} ';
    return CommandClaim(
      token: token,
      hint: desc.hint,
      images: desc.images,
      submit: (args, images) async {
        final outcome = await execute(sessionId, '$token$args');
        return SubmitOutcome(
          kind: outcome.ok ? 'success' : 'error',
          text: outcome.text,
        );
      },
    );
  }

  /// Fire-and-forget detached execution; outcomes are not surfaced here (the
  /// host durably logs the lifecycle and the flow node renders on every tab).
  Future<void> _runDetached(SessionId sessionId, String line) async {
    try {
      final outcome = await execute(sessionId, line);
      if (!outcome.ok) {
        debugPrint('[ui-commands] detached ${outcome.text ?? "$line failed"}');
      }
    } catch (error) {
      debugPrint('[ui-commands] detached execution failed: $error');
    }
  }

  /// Per-session popupSelect controllers, created lazily on first use and
  /// torn down with the plugin.
  final Map<String, PopupSelectController<SessionId>> _popups = {};

  /// Session wiring for popup settlement (token consumption + composer
  /// focus). Unbound defaults to no-op wiring — the pre-composer-seam
  /// adaptation mirroring input-trigger's absent outcome sink: settlements
  /// close the shell but consume nothing. [bindPopupDeps] overrides it for
  /// controllers created afterwards.
  PopupSelectDeps? _popupDeps;

  /// Bind the popup session wiring (the composer seam calls this).
  void bindPopupDeps(PopupSelectDeps deps) {
    _popupDeps = deps;
  }

  /// One session's popup controller (created lazily over current wiring).
  PopupSelectController<SessionId> popupOf(SessionId sessionId) {
    return _popups.putIfAbsent(
      sessionId.value,
      () => PopupSelectController<SessionId>(
        _popupDeps ?? const _NoopPopupDeps(),
      ),
    );
  }

  /// Open the session's shell for one popupSelect contribution over
  /// [segment]; a non-popup or unavailable name throws (callers route only
  /// after checking the contribution).
  void openPopup(SessionId sessionId, String name, TokenSegment segment) {
    final c = contribution(name);
    if (c == null || c.options == null || !c.available(sessionId)) {
      throw StateError(
        'ui-commands: /$name does not expose a popupSelect spec',
      );
    }
    popupOf(sessionId)
        .open(name, _ContributionPopupSpec(c), sessionId, segment);
  }

  /// Tear down every live popup controller (plugin teardown).
  void disposePopups() {
    for (final popup in _popups.values) {
      popup.dispose();
    }
    _popups.clear();
  }

  /// Directory access for wiring (invalidation events).
  CommandDirectory get directory => _directory;
}

/// Adapts one contribution's popupSelect members to the shell spec face,
/// capturing nothing: the controller carries the open-time session context.
class _ContributionPopupSpec implements PopupSpec<SessionId> {
  const _ContributionPopupSpec(this._c);

  final CommandContribution _c;

  @override
  Future<List<SelectOption>> options(SessionId context, PopupSignal signal) =>
      _c.options!(context);

  @override
  Future<void> onSelect(SelectOption option, SessionId context) =>
      _c.onSelect!(option, context);
}

/// No-op wiring for the unbound-wiring default (see [CommandUiService.bindPopupDeps]).
class _NoopPopupDeps implements PopupSelectDeps {
  const _NoopPopupDeps();

  @override
  bool consume(TokenSegment segment) => false;

  @override
  void focusComposer() {}
}
