/// Composer model seat — the `conversation.input.model` occupant, port of
/// `ModelSelect.tsx` sliced to the Dart hub: trigger showing the host-reported
/// current selection, menu over the provider-grouped advisory directory
/// (`session.models`), pick submits through `session.selectModel` via the
/// shared per-session directory. Failure rows are listed for visibility but
/// never selectable; load errors surface on the directory state and keep the
/// last good trigger label.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart';
import '../../../features/model_selection/model_directory.dart';
import '../../../widgets/primitives/toast.dart';
import '../model_directory_service.dart';

/// Per-session directory for the seat, resolved through the activated
/// `modelDirectories` service so every surface shares one store instance
/// (watching this provider yields the [ModelDirectoryState] snapshot).
final seatDirectoryProvider =
    StateNotifierProvider.family<ModelDirectory, ModelDirectoryState, String>((
      ref,
      sessionId,
    ) {
      final directories = activatedModelDirectories;
      if (directories == null) {
        throw StateError('ui-model-selection: service not activated');
      }
      return directories.directoryFor(SessionId(sessionId));
    });

/// The composer's named model seat.
class ModelSeat extends ConsumerWidget {
  /// Creates the seat.
  const ModelSeat({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    if (session == null || activatedModelDirectories == null) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(seatDirectoryProvider(session.sessionId.value));
    final directory = ref.read(
      seatDirectoryProvider(session.sessionId.value).notifier,
    );
    // bindLocale watches localeRevisionProvider so the seat copy follows a
    // Language-row switch.
    return _seat(
      context,
      ref,
      ref.bindLocale(kModelNamespace),
      directory,
      state,
      session.sessionId.value,
    );
  }

  Widget _seat(
    BuildContext context,
    WidgetRef ref,
    Translate t,
    ModelDirectory directory,
    ModelDirectoryState state,
    String sessionId,
  ) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final current = state.current;

    // Find the exact selected model object to read its advertised reasoning.
    ModelInfo? currentModel;
    for (final g in state.groups) {
      for (final m in g.models) {
        if (current != null &&
            g.id == current.provider &&
            m.id == current.model) {
          currentModel = m;
          break;
        }
      }
      if (currentModel != null) break;
    }
    final reasoning = currentModel?.reasoning;
    final effectiveEffort =
        current?.reasoningEffort ?? reasoning?.defaultEffort;
    String? effortLabel;
    if (reasoning != null) {
      if (effectiveEffort == null) {
        effortLabel = t('effort.providerDefault');
      } else {
        final match = reasoning.efforts
            .where((e) => e.id == effectiveEffort)
            .firstOrNull;
        effortLabel = match?.name ?? effectiveEffort;
      }
    }

    final String label = current == null
        ? t('trigger.fallback')
        : currentModel?.name ?? current.model;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<(String, ModelInfo)>(
          tooltip: t('menu.aria'),
          color: aliases.specificMenu,
          onOpened: () {
            if (state.status == 'idle' || state.status == 'error') {
              directory.load().catchError(
                (Object _) => const <String, dynamic>{},
              );
            }
          },
          itemBuilder: (BuildContext context) => [
            for (final group in state.groups)
              for (final model in group.models)
                PopupMenuItem<(String, ModelInfo)>(
                  value: (group.id, model),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeS14,
                            color: aliases.labelPrimary,
                          ),
                        ),
                      ),
                      if (current?.provider == group.id &&
                          current?.model == model.id)
                        Icon(
                          Icons.check,
                          size: 14,
                          color: aliases.stateBusinessPrimary,
                        ),
                    ],
                  ),
                ),
            for (final failure in state.failures.whereType<Map>())
              PopupMenuItem<(String, ModelInfo)>(
                enabled: false,
                value: ('', ModelInfo(id: '${failure['id']}', name: '')),
                child: Text(
                  '${failure['name'] ?? failure['id']} — ${t('load.failed')}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelTertiary,
                  ),
                ),
              ),
          ],
          onSelected: ((String, ModelInfo) pick) async {
            if (current != null &&
                current.provider == pick.$1 &&
                current.model == pick.$2.id)
              return;
            final target = pick.$2;
            final defaultEffort = target.reasoning?.defaultEffort;
            final bool accepted = await directory
                .select(
                  ModelSelection(
                    provider: pick.$1,
                    model: target.id,
                    reasoningEffort: defaultEffort,
                  ),
                )
                .then((v) => v as bool? ?? true)
                .catchError((Object _) => false);
            if (!accepted && context.mounted) {
              final err =
                  ref
                      .read(seatDirectoryProvider(sessionId).notifier)
                      .state
                      .error ??
                  t('error.action');
              ref.read(toastProvider.notifier).showError(err);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceSm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: aliases.bgOverlay,
              borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              border: Border.all(color: aliases.borderL2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.memory_outlined,
                  size: 12,
                  color: aliases.labelSecondary,
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      fontWeight: FontWeight.w600,
                      color: aliases.labelSecondary,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, size: 12),
              ],
            ),
          ),
        ),
        if (reasoning != null) ...[
          const SizedBox(width: 6),
          PopupMenuButton<String?>(
            tooltip: t('menu.effort'),
            color: aliases.specificMenu,
            onOpened: () {
              if (state.status == 'idle' || state.status == 'error') {
                directory.load().catchError(
                  (Object _) => const <String, dynamic>{},
                );
              }
            },
            itemBuilder: (BuildContext context) {
              final items = <PopupMenuEntry<String?>>[];
              if (reasoning.defaultEffort == null) {
                items.add(
                  PopupMenuItem<String?>(
                    value: null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('effort.providerDefault'),
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              color: aliases.labelPrimary,
                            ),
                          ),
                        ),
                        if (effectiveEffort == null)
                          Icon(
                            Icons.check,
                            size: 14,
                            color: aliases.stateBusinessPrimary,
                          ),
                      ],
                    ),
                  ),
                );
              }
              for (final e in reasoning.efforts) {
                items.add(
                  PopupMenuItem<String?>(
                    value: e.id,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.name,
                                style: TextStyle(
                                  fontSize: DswTokens.fontSizeS14,
                                  color: aliases.labelPrimary,
                                ),
                              ),
                            ),
                            if (effectiveEffort == e.id)
                              Icon(
                                Icons.check,
                                size: 14,
                                color: aliases.stateBusinessPrimary,
                              ),
                          ],
                        ),
                        if (e.description != null)
                          Text(
                            e.description!,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              color: aliases.labelTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
              if (items.isEmpty) {
                items.add(
                  PopupMenuItem<String?>(
                    enabled: false,
                    value: null,
                    child: Text(t('empty.efforts')),
                  ),
                );
              }
              return items;
            },
            onSelected: (String? effort) async {
              if (current == null) return;
              if (effectiveEffort == effort) return;
              final bool accepted = await directory
                  .select(
                    ModelSelection(
                      provider: current.provider,
                      model: current.model,
                      reasoningEffort: effort,
                    ),
                  )
                  .then((v) => v as bool? ?? true)
                  .catchError((Object _) => false);
              if (!accepted && context.mounted) {
                final err =
                    ref
                        .read(seatDirectoryProvider(sessionId).notifier)
                        .state
                        .error ??
                    t('error.action');
                ref.read(toastProvider.notifier).showError(err);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DswTokens.spaceSm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: aliases.bgOverlay,
                borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                border: Border.all(color: aliases.borderL2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 12,
                    color: aliases.labelSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    effortLabel ?? t('menu.effort'),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      fontWeight: FontWeight.w600,
                      color: aliases.labelSecondary,
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 12),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
