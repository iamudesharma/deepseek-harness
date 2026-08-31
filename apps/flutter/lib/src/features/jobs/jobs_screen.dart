/// Compatibility re-export: the jobs surface moved to the `ui-jobs` plugin
/// (`plugins/jobs/ui/`). The only importer left on this path is
/// lib/src/routing/app_router.dart; delete this shim when the router
/// repoints at the plugin surface.
library;

export '../../plugins/jobs/ui/jobs_screen.dart';
