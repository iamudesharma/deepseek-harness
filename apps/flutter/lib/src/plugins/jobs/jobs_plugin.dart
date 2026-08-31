/// The `ui-job` plugin — Flutter port of
/// `packages/client/ui-jobs/src/client/index.ts` `apply()`.
///
/// Registrations, in React order: the `job` locale dictionaries and the
/// session-header background-job action (`conversation.session.header.
/// actions`, id `job-list`, order 20 — after the subagent catalog, since
/// session lineage reads before process work). No RPC, no store: the rows
/// come from [jobsProvider], the authoritative `session/jobs` frame feed.
library;

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'locales.dart';
import 'ui/job_list_action.dart';

/// Plugin identity (the React package's locale namespace is `job`).
const String kJobsPluginId = 'ui-jobs';

/// Header list entry id (React `id: 'job-list'`).
const String kJobListActionId = 'job-list';

/// The `ui-jobs` plugin.
class JobsPlugin extends DshPlugin {
  /// Creates the plugin.
  const JobsPlugin();

  @override
  String get id => kJobsPluginId;

  @override
  List<String> get inject => ['slots', 'sessions', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    // Pin every declared injection edge. React reads the session id through
    // its runtime share; the Dart action reads the shared current-session
    // provider and the frame-fed jobsProvider, so 'sessions' is pinned
    // type-only here.
    ctx.require<SessionsService>('sessions');
    final LocaleService locale = ctx.require<LocaleService>('locale');

    ctx.onDispose(locale.register(kJobNamespace, {'zh': kJobZh, 'en': kJobEn}));

    // The header hole is conversation-owned; the wait-and-follow install
    // leaves with this plugin. A bare register into an undeclared slot would
    // fail loud by design.
    final stopInject = ctx.slots.inject(
      'conversation.session.header.actions',
      () {
        return [
          ctx.slots.register(
            const RegistrationOptions(
              name: 'conversation.session.header.actions',
              id: kJobListActionId,
              order: 20,
            ),
            (context, props) => const JobListAction(),
          ),
        ];
      },
    );
    ctx.onDispose(stopInject);
  }
}
