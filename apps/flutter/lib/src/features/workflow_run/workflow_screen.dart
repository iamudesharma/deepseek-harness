/// Compatibility re-export: the workflow surface moved to the
/// `ui-workflow-run` plugin (`plugins/workflow_run/ui/`). The only importer
/// left on this path is lib/src/routing/app_router.dart; delete this shim
/// when the router repoints at the plugin surface.
library;

export '../../plugins/workflow_run/ui/workflow_screen.dart';
