/// New-session agent-preset chip — Flutter port of
/// `packages/client/ui-agent-preset/src/client/AgentPresetSeat.tsx`, mounted
/// on the `conversation.hero.agentPreset` seat in the blank-session hero's
/// workspace row (React ConversationRoot.tsx:122 renders it right after the
/// workspace slot). Read-only header label lives in
/// `agent_preset_label.dart`; this is the before-the-fact choice.
///
/// The menu opens on the current choice (the session summary's preset, else
/// the deployment default); a pick applies to the current blank session via
/// `agentPreset.select` — a running session keeps the composition it began
/// with (AgentPresetSeat.tsx module doc). Renders nothing while the roster
/// is empty (`!ready` → null).
///
/// The dropdown uses the shared [AnchoredMenu] overlay (trigger rect →
/// CompositedTransformTarget → follower, viewport clamp + bottom-edge flip),
/// mirroring React's `Menu portal` placement — labels resolve through the
/// active locale at render time via [presetDisplayText], never cached.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate, localeRevisionProvider;
import '../../../core/session/session_models.dart'
    show SessionId, SessionSummary;
import '../../../core/session/session_provider.dart';
import '../../../core/session/sessions_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/anchored_menu.dart';
import '../locales.dart';
import 'agent_preset_provider.dart';

/// Hero seat rendering the staged/current preset as one compact chip beside
/// the workspace picker.
class AgentPresetHeroSeat extends ConsumerWidget {
  /// Creates the seat.
  const AgentPresetHeroSeat({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Locale revision watch supplies the rebuild so the label follows the
    // active dictionary (directory_picker_flows.dart pattern). The mode model
    // holds stable identifiers; visible text is resolved from the active locale
    // at render time via [presetDisplayText] — never cached.
    ref.watch(localeRevisionProvider);
    final Translate t = ref.bindLocale(kAgentPresetNamespace);

    // Loading / error / empty roster all render nothing — React's `!ready`
    // posture (AgentPresetSeat.tsx): the chip appears only when there is a
    // live roster to choose from. `asData` keeps a failed fetch from
    // rethrowing inside build.
    final List<AgentPresetOption> options =
        ref.watch(agentPresetListProvider).asData?.value.presets ??
        const <AgentPresetOption>[];
    if (options.isEmpty) return const SizedBox.shrink();

    final SessionSummary? summary = ref.watch(currentSessionProvider);
    final String? sessionPreset = summary?.agentPreset;
    final String deploymentDefault =
        options.where((o) => o.isDefault).firstOrNull?.id ?? options.first.id;
    final String current = sessionPreset ?? deploymentDefault;
    final AgentPresetOption? chosenRaw = options
        .where((o) => o.id == current)
        .firstOrNull;
    final ({String name, String? description})? chosenText = chosenRaw == null
        ? null
        : presetDisplayText(
            id: chosenRaw.id,
            builtIn: chosenRaw.trust == PresetTrust.system,
            t: t,
            name: chosenRaw.name,
            description: chosenRaw.description,
          );

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return AnchoredMenu(
      aliases: aliases,
      maxWidth: 280,
      items: [
        for (final AgentPresetOption o in options)
          (() {
            final display = presetDisplayText(
              id: o.id,
              builtIn: o.trust == PresetTrust.system,
              t: t,
              name: o.name,
              description: o.description,
            );
            return AnchoredMenuItem(
              value: o.id,
              label: display.name,
              description: display.description ?? t('noDescription'),
              selected: o.id == current,
            );
          })(),
      ],
      onSelected: (String id) async {
        final SessionId? sessionId = ref.read(currentSessionIdProvider);
        if (sessionId == null) return;
        final String beforeCurrent = current;
        if (id == beforeCurrent) return;
        try {
          final result = await ref
              .read(connectionClientProvider)
              .agentPresetSelect(sessionId: sessionId.value, agentPreset: id);
          final String newPreset =
              (result['agentPreset'] as String?) ?? id;
          // Host-authoritative: update session summary from RPC echo; the
          // remote-event fanout (live_sync remoteBus) will also fold the
          // committed agent-preset/selected, idempotently.
          ref
              .read(sessionsProvider.notifier)
              .updateSession(sessionId, (s) => s.copyWith(agentPreset: newPreset));
        } catch (_) {
          // Host rejected (agent-preset-locked, not-found, etc.) — preserve
          // previous mode and keep checkmark on it.
        }
      },
      triggerBuilder: (context, open) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DswTokens.spaceSm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: open ? aliases.interactiveBgHover : aliases.bgOverlay,
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          border: Border.all(color: aliases.borderL2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.tune, size: 12, color: aliases.labelTertiary),
            const SizedBox(width: 4),
            Text(
              chosenText?.name ?? chosenRaw?.name ?? current,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                fontWeight: FontWeight.w600,
                color: aliases.labelSecondary,
              ),
            ),
            Icon(Icons.expand_more, size: 12, color: aliases.labelTertiary),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    for (final E e in this) {
      return e;
    }
    return null;
  }
}
