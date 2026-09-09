import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, kCommonNamespace;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/ds_select.dart';
import '../../../plugins/conversation/locales.dart' show kConversationNamespace;

// ---------------------------------------------------------------------------
// Transcript-view store — mirrors `TranscriptViewPolicy` in
// `packages/client/ui-chat/src/client/transcript-view.ts`
// ---------------------------------------------------------------------------

/// Settings namespace owned by the Chat target (React `CHAT_SETTINGS_NAMESPACE`).
const String kChatSettingsNamespace = 'ui-chat';

/// Field carrying the completed-Turn transcript mode (React `TRANSCRIPT_VIEW_FIELD`).
const String kTranscriptViewField = 'transcriptView';

/// Transcript presentation modes (React `TRANSCRIPT_VIEW_MODES`).
enum TranscriptViewMode { normal, compact }

/// Default preserves the compact process disclosure (React `DEFAULT_TRANSCRIPT_VIEW_MODE`).
const TranscriptViewMode kDefaultTranscriptViewMode =
    TranscriptViewMode.compact;

/// Store state mirrored from the chat settings snapshot.
class TranscriptViewState {
  const TranscriptViewState({
    this.mode = kDefaultTranscriptViewMode,
    this.revision = -1,
    this.loading = false,
    this.error,
  });

  final TranscriptViewMode mode;
  final int revision;
  final bool loading;
  final String? error;

  TranscriptViewState copyWith({
    TranscriptViewMode? mode,
    int? revision,
    bool? loading,
    String? error,
  }) => TranscriptViewState(
    mode: mode ?? this.mode,
    revision: revision ?? this.revision,
    loading: loading ?? this.loading,
    error: error,
  );
}

/// Controller for [TranscriptViewState] — mirrors `TranscriptViewPolicy`.
class TranscriptViewController extends Notifier<TranscriptViewState> {
  @override
  TranscriptViewState build() => const TranscriptViewState();

  /// Sync from a remote snapshot — respects revision monotonicity.
  void sync(TranscriptViewMode mode, int revision) {
    if (revision <= state.revision) return;
    state = state.copyWith(mode: mode, revision: revision);
  }

  Map<String, dynamic>? _chatSection(Map<String, dynamic> describe) {
    final namespaces = describe['namespaces'];
    if (namespaces is List) {
      for (final entry in namespaces) {
        if (entry is Map && entry['ns'] == kChatSettingsNamespace) {
          return entry.cast<String, dynamic>();
        }
      }
      return null;
    }
    if (namespaces is Map) {
      final entry = namespaces[kChatSettingsNamespace];
      if (entry is Map) return entry.cast<String, dynamic>();
    }
    return null;
  }

  /// Load the persisted transcript mode from the Host settings document.
  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    final client = ref.read(connectionClientProvider);
    try {
      final describe = await client.settingsDescribe();
      final section = _chatSection(describe);
      final value = section?['value'] as Map<String, dynamic>?;
      final mode = value?[kTranscriptViewField] == 'normal'
          ? TranscriptViewMode.normal
          : TranscriptViewMode.compact;
      sync(mode, section?['revision'] as int? ?? 0);
      state = state.copyWith(loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Change the completed-Turn transcript presentation. A failed write rolls
  /// back to the last confirmed mode, mirroring the policy's snapshot echo.
  Future<String?> setMode(TranscriptViewMode mode) async {
    final client = ref.read(connectionClientProvider);
    final prevMode = state.mode;
    final prevRevision = state.revision;
    state = state.copyWith(mode: mode, error: null);
    try {
      final describe = await client.settingsDescribe();
      final section = _chatSection(describe);
      await client.settingsMutate(
        ns: kChatSettingsNamespace,
        ops: [
          {'op': 'set', 'path': [kTranscriptViewField], 'value': mode.name},
        ],
        expectedRevision: section?['revision'] as int?,
      );
      await load();
      return null;
    } catch (e) {
      state = state.copyWith(
        mode: prevMode,
        revision: prevRevision,
        error: e.toString(),
      );
      return e.toString();
    }
  }
}

/// Global transcript-view row provider. Override in `ProviderScope` for tests.
final transcriptViewProvider =
    NotifierProvider<TranscriptViewController, TranscriptViewState>(
      TranscriptViewController.new,
    );

// ---------------------------------------------------------------------------
// Widget — mirrors `TranscriptViewRow.tsx`
// ---------------------------------------------------------------------------

/// Completed-Turn transcript mode row: title + description + normal/compact
/// selector pill. Copy rides the `conversation` locale namespace under
/// `settings.transcript.*`, next to the sibling Enter-behavior row.
class TranscriptViewRow extends ConsumerStatefulWidget {
  const TranscriptViewRow({super.key});

  @override
  ConsumerState<TranscriptViewRow> createState() => _TranscriptViewRowState();
}

class _TranscriptViewRowState extends ConsumerState<TranscriptViewRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(transcriptViewProvider);
      if (s.revision == -1 && !s.loading) {
        ref.read(transcriptViewProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final TranscriptViewState rowState = ref.watch(transcriptViewProvider);
    final TranscriptViewController controller = ref.read(
      transcriptViewProvider.notifier,
    );
    final t = ref.bindLocale(kConversationNamespace);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: aliases.borderL2, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('settings.transcript.title'),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                      fontWeight: FontWeight.w400,
                      color: aliases.labelPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t('settings.transcript.description'),
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelTertiary,
                    ),
                  ),
                  if (rowState.error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      rowState.error!,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.stateErrorPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: DsSelect(
                value: rowState.mode.name,
                placeholder: ref.bindLocale(kCommonNamespace)(
                  rowState.loading ? 'loading' : 'select',
                ),
                options: [
                  for (final m in TranscriptViewMode.values)
                    DsSelectOption(
                      value: m.name,
                      label: t('settings.transcript.${m.name}'),
                    ),
                ],
                onChanged: (String next) async {
                  final mode = TranscriptViewMode.values.firstWhere(
                    (e) => e.name == next,
                    orElse: () => TranscriptViewMode.compact,
                  );
                  final err = await controller.setMode(mode);
                  if (!mounted || err == null) return;
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err),
                      backgroundColor: aliases.stateErrorPrimary,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
