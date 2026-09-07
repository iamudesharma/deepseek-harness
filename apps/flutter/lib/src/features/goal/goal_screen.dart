/// Compatibility re-export: the goal surfaces moved to the `ui-goal` plugin
/// (`plugins/goal/ui/`). The only importer left on this path is
/// lib/src/routing/app_router.dart; delete this shim when the router
/// repoints at the plugin surface.
library;

export '../../plugins/goal/ui/goal_screen.dart';
