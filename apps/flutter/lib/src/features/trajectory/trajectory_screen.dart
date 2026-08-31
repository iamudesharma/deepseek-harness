/// Compatibility re-export: the trajectory screen moved to the `ui-trajectory`
/// plugin (plugins/trajectory/ui/trajectory_screen.dart). The only importer
/// left on this path is lib/src/routing/app_router.dart; delete this shim when
/// the router repoints at the plugin surface.
library;

export '../../plugins/trajectory/ui/trajectory_screen.dart';
