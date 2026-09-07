import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';
import '../locales.dart' show kWorkflowRunNamespace;

/// Workflow runs screen — empty surface.
///
/// Durable workflow runs render through the `workflow-run` chat-node panel
/// (`plugins/workflow_run/ui/workflow_run_panel.dart`); no list seam over
/// run data exists yet, so this screen renders its empty state rather than
/// fabricated rows. The only importer left on the features/ path is
/// lib/src/routing/app_router.dart; repoint it at this plugin surface and
/// delete the shim there.
class WorkflowScreen extends ConsumerWidget {
  /// Creates the workflow screen.
  const WorkflowScreen({super.key, this.sessionId});

  /// Optional session scoping — reserved for a future list seam.
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    // Flutter-surface keys (nav/empty chrome) live in the workflowRun dict;
    // React ships only the run-panel copy.
    final Translate t = ref.bindLocale(kWorkflowRunNamespace);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          t('screen.nav'),
          style: TextStyle(
            fontSize: DswTokens.fontSizeBase16,
            fontWeight: FontWeight.w600,
            color: aliases.labelPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: aliases.borderL2),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 32,
                color: aliases.labelCaption,
              ),
              const SizedBox(height: DswTokens.spaceMd),
              Text(
                t('screen.empty.title'),
                style: TextStyle(
                  fontSize: DswTokens.fontSizeBase16,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t('screen.empty.hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  color: aliases.labelSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
