import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate, kCommonNamespace;
import '../../../core/session/session_models.dart'
    show SessionId, SessionSummary;
import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/anchored_menu.dart';
import '../locales.dart';
import '../permission_session_provider.dart';

/// Current-session permission seat — port of React's `ui-permission-presets`
/// popupSelect over the `permissions` projection. Reads the projection
/// (`PermissionSelect`) and submits `/permission <preset>` via the command
/// admission channel; the pushed projection frame is the confirmation.
///
/// The menu uses the shared [AnchoredMenu] overlay (trigger rect →
/// CompositedTransformTarget → follower), so it opens attached to the chip
/// and follows it through resize/scroll — never the detached
/// `PopupMenuButton` route position.
///
/// Risk acknowledgement for `danger-full-access` mirrors React's
/// `RiskConfirmation` modal: a checkbox must be acknowledged before the
/// dangerous switch is enabled. After a successful switch the seat re-pulls
/// the session's tail projections as a belt-and-braces confirmation so the
/// chip updates even when the live projection frame is missed.
class PermissionSeat extends ConsumerStatefulWidget {
  const PermissionSeat({super.key});

  @override
  ConsumerState<PermissionSeat> createState() => _PermissionSeatState();
}

class _PermissionSeatState extends ConsumerState<PermissionSeat> {
  bool _switching = false;
  bool _seedAttempted = false;
  String? _lastSeedSessionId;

  Future<void> _apply(String value, SessionSummary session) async {
    if (_switching) return;
    setState(() => _switching = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(connectionClientProvider).callMethod(
        'commands/execute',
        {
          'agentId': session.sessionId.value,
          'line': '/permission $value',
          'images': [],
        },
      );
      final res = result['result'];
      if (res is Map && res['kind'] == 'error') {
        final Translate t = ref.bindLocale(kPermissionAccessNamespace);
        messenger.showSnackBar(
          SnackBar(content: Text(res['text'] as String? ?? t('switchFailed'))),
        );
        return;
      }
      // Confirmation fallback: the live `session/projection key:permissions`
      // frame is the primary confirmation; re-pull the tail block too so the
      // chip updates even when that frame is missed (e.g. stream gap).
      await _refreshProjection(session.sessionId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// Seeds [permissionSelectProvider] from the authoritative
  /// `session/follow` snapshot / `session/projection` live frame —
  /// no `session/page` fallback.
  Future<void> _refreshProjection(SessionId id) async {
    // Permission projection is authoritative via `session/follow` snapshot
    // `projections` baseline and live `session/projection` frames
    // (`live_sync.dart` → `permissionSelectProvider`). No `session/page`
    // history pull is needed; the live state is the source.
    return;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    if (session == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final select = ref.watch(permissionSelectProvider(session.sessionId.value));
    // Capability absent → hide (key absence = not composed). For blank
    // sessions the host projection arrives via `session.history` tail or the
    // live `session/projection` frame; the sidebar's create path now seeds
    // immediately, but a pre-existing blank session or a missed push would
    // otherwise leave the tool row collapsed with no access control visible.
    // Schedule a one-shot history pull and show a disabled placeholder so the
    // hero never appears without its permission chip.
    if (select == null) {
      final String sid = session.sessionId.value;
      if (_lastSeedSessionId != sid) {
        _lastSeedSessionId = sid;
        _seedAttempted = false;
      }
      if (!_seedAttempted) {
        _seedAttempted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshProjection(session.sessionId);
        });
      }
      return Container(
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
              Icons.shield_outlined,
              size: 12,
              color: aliases.labelSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'workspace-write',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // bindLocale watches localeRevisionProvider so the gate copy follows a
    // Language-row switch without remount.
    final Translate t = ref.bindLocale(kPermissionAccessNamespace);
    final Translate tcommon = ref.bindLocale(kCommonNamespace);
    final current = select.currentValue;
    final isCustom = select.isCustom;
    final label = isCustom
        ? t('custom')
        : select.options.where((o) => o.value == current).firstOrNull?.name ??
              current;

    return AnchoredMenu(
      aliases: aliases,
      items: [
        for (final opt in select.options)
          AnchoredMenuItem(
            value: opt.value,
            label: opt.name,
            description: opt.description,
            selected: current == opt.value,
            enabled: opt.value != 'custom' && !_switching,
          ),
      ],
      onSelected: (value) async {
        if (value == 'custom' || value == current) return;
        if (value == 'danger-full-access') {
          final confirmed = await showPermissionRiskDialog(
            context,
            aliases,
            t,
            tcommon,
          );
          if (confirmed != true) return;
        }
        if (!mounted) return;
        await _apply(value, session);
      },
      triggerBuilder: (context, open) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DswTokens.spaceSm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: isCustom
              ? aliases.stateWarnPrimary.withValues(alpha: 0.12)
              : open
              ? aliases.interactiveBgHover
              : aliases.bgOverlay,
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          border: Border.all(
            color: isCustom ? aliases.stateWarnPrimary : aliases.borderL2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCustom ? Icons.warning_amber_rounded : Icons.shield_outlined,
              size: 12,
              color: isCustom
                  ? aliases.stateWarnPrimary
                  : aliases.labelSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  fontWeight: FontWeight.w600,
                  color: isCustom
                      ? aliases.stateWarnPrimary
                      : aliases.labelSecondary,
                ),
              ),
            ),
            const Icon(Icons.expand_more, size: 12),
          ],
        ),
      ),
    );
  }
}

/// Risk confirmation for Full Access — mirrors React's `RiskConfirmation`
/// with an acknowledge checkbox. Returns true when the user confirms. Copy
/// resolves through the `permission.access` dictionaries registered by the
/// owning plugin's `apply`.
Future<bool?> showPermissionRiskDialog(
  BuildContext context,
  DswAliases aliases,
  Translate t,
  Translate tcommon,
) {
  bool acknowledged = false;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text(t('confirm.title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('confirm.description')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: acknowledged,
                    onChanged: (v) => setState(() => acknowledged = v ?? false),
                  ),
                  Expanded(child: Text(t('confirm.acknowledge'))),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tcommon('cancel')),
            ),
            FilledButton(
              onPressed: acknowledged
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: Text(t('confirm.enable')),
            ),
          ],
        );
      },
    ),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
