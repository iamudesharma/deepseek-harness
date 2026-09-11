/// The `ui-schedule` plugin — Flutter port of
/// `packages/client/ui-schedule/src/client/index.ts` `apply()`.
///
/// Registration, in React order: the `schedule.catalog` dictionaries plus the
/// session-header catalog action (`conversation.session.header.actions`, id
/// `schedule-catalog`, order 10). Read-only: rows come from the session's
/// `schedule` projection slice (`projections.values['schedule']`); no RPC,
/// no store, no mutation face.
library;

import 'package:flutter/widgets.dart';

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'locales.dart';
import 'ui/schedule_catalog_action.dart';

/// Plugin identity (the React package is `ui-schedule`).
const String kSchedulePluginId = 'ui-schedule';

/// Header actions entry id (React `id: 'schedule-catalog'`).
const String kScheduleCatalogId = 'schedule-catalog';

/// The `ui-schedule` plugin.
class SchedulePlugin extends DshPlugin {
  /// Creates the plugin.
  const SchedulePlugin();

  @override
  String get id => kSchedulePluginId;

  @override
  List<String> get inject => ['slots', 'sessions', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge.
    final LocaleService locale = ctx.require<LocaleService>('locale');
    ctx.require<SessionsService>('sessions');

    // Dictionaries leave with the plugin (the ctx.effect analog).
    ctx.onDispose(
      locale.register(kScheduleNamespace, {
        'zh': kScheduleZh,
        'en': kScheduleEn,
      }),
    );

    // Catalog action waits for the conversation-owned header hole, installs
    // atomically, and leaves with this plugin.
    final stopInject = ctx.slots.inject(
      'conversation.session.header.actions',
      () {
        return [
          ctx.slots.register(
            const RegistrationOptions(
              name: 'conversation.session.header.actions',
              id: kScheduleCatalogId,
              order: 10,
            ),
            (BuildContext context, dynamic props) =>
                const ScheduleCatalogAction(),
          ),
        ];
      },
    );
    ctx.onDispose(stopInject);
  }
}
