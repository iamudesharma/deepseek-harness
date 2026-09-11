/// Session-header schedule catalog action — Flutter port of
/// `ScheduleCatalogAction.tsx` (read-only active-reminder dropdown).
///
/// Visibility matches React minus one documented gap: React also gates on
/// `openState === 'open'`, but Flutter's `SessionSummary` carries no
/// `openState`, so this renders whenever the `schedule` projection slice is
/// non-empty. Relative times tick every second while the menu is open
/// (React's `setInterval(1000)`); `PopupMenuButton` owns outside-dismiss and
/// Escape, matching `useDismissOnOutsidePointer` plus the Escape handler.
/// Local time uses Material localizations (medium date + short time) for
/// React's `Intl.DateTimeFormat` medium/short role.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart';
import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart';
import '../schedule_models.dart';
import '../schedule_provider.dart';

/// Session-header entry: reminder-count trigger + catalog menu.
class ScheduleCatalogAction extends ConsumerStatefulWidget {
  /// Creates the header action.
  const ScheduleCatalogAction({super.key});

  @override
  ConsumerState<ScheduleCatalogAction> createState() =>
      _ScheduleCatalogActionState();
}

class _ScheduleCatalogActionState
    extends ConsumerState<ScheduleCatalogAction> {
  Timer? _ticker;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  bool _open = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
    if (open) {
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(
            () => _nowMs = DateTime.now().millisecondsSinceEpoch,
          );
        }
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final ScheduleStrings t = scheduleStrings(
      ref.bindLocale(kScheduleNamespace),
    );

    final current = ref.watch(currentSessionIdProvider);
    if (current == null) return const SizedBox.shrink();
    // Live projection seat (follow snapshots plus push frames), mirroring
    // React `useProjection('schedule')` — never the session-list snapshot,
    // which carries no live projection values.
    final List<ScheduleRecord> records = ref.watch(
      scheduleProjectionProvider(current.value),
    );
    if (records.isEmpty) return const SizedBox.shrink();

    final String countLabel = t(
      records.length == 1 ? 'trigger.one' : 'trigger.other',
      {'count': records.length},
    );
    final List<ScheduleRecord> rows = orderScheduleRecords(records, _nowMs);

    return PopupMenuButton<String>(
      tooltip: countLabel,
      offset: const Offset(0, 33),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DswTokens.radiusXl),
      ),
      color: aliases.specificMenu,
      onOpened: () => _setOpen(true),
      onCanceled: () => _setOpen(false),
      onSelected: (_) => _setOpen(false),
      itemBuilder: (BuildContext ctx) {
        final MaterialLocalizations loc = MaterialLocalizations.of(ctx);
        return [
          for (final ScheduleRecord record in rows)
            PopupMenuItem<String>(
              enabled: false,
              value: record.id,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 304),
                child: _ScheduleRow(
                  record: record,
                  nowMs: _nowMs,
                  aliases: aliases,
                  t: t,
                  localTime: _localTime(record, loc),
                ),
              ),
            ),
        ];
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.alarm_outlined,
            size: 14,
            color: aliases.labelTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            countLabel,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelTertiary,
            ),
          ),
          Icon(
            _open ? Icons.expand_less : Icons.expand_more,
            size: 14,
            color: aliases.labelTertiary,
          ),
        ],
      ),
    );
  }

  /// Medium date + short time for the durable UTC target.
  String _localTime(ScheduleRecord record, MaterialLocalizations loc) {
    final target = record.scheduledAt;
    if (target == null) return '';
    final local = target.toLocal();
    return '${loc.formatMediumDate(local)} '
        '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}

/// One catalog row: status line, prompt, and frequency/time/relative metadata.
class _ScheduleRow extends StatelessWidget {
  /// Creates a row.
  const _ScheduleRow({
    required this.record,
    required this.nowMs,
    required this.aliases,
    required this.t,
    required this.localTime,
  });

  /// The reminder record.
  final ScheduleRecord record;

  /// Snapshot clock for overdue/relative derivation.
  final int nowMs;

  /// Theme aliases.
  final DswAliases aliases;

  /// Catalog copy face.
  final ScheduleStrings t;

  /// Preformatted local target time.
  final String localTime;

  @override
  Widget build(BuildContext context) {
    final bool overdue = record.isOverdue(nowMs);
    final String status = t(overdue ? 'status.overdue' : 'status.scheduled');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DswTokens.spaceSm,
        vertical: DswTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: overdue ? aliases.stateWarnTertiary : null,
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: overdue
                      ? aliases.stateWarnPrimary
                      : aliases.stateBusinessPrimary,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                status,
                style: TextStyle(
                  fontSize: 11,
                  color: overdue
                      ? aliases.stateWarnLabel
                      : aliases.labelTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            record.prompt,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXs13,
              color: aliases.labelPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 5,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatScheduleFrequency(record, t),
                style: _metaStyle(),
              ),
              Text('·', style: _metaStyle()),
              if (localTime.isNotEmpty) Text(localTime, style: _metaStyle()),
              if (localTime.isNotEmpty) Text('·', style: _metaStyle()),
              Text(
                formatScheduleRelative(record, nowMs, t),
                style: TextStyle(
                  fontSize: 11,
                  color: overdue
                      ? aliases.stateWarnLabel
                      : aliases.labelTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _metaStyle() {
    return TextStyle(fontSize: 11, color: aliases.labelTertiary);
  }
}
