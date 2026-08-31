import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../theme/app_theme.dart';
import '../locales.dart';
import 'produced_files_row.dart';

/// Deliverables screen — produced files for the scoped turn.
///
/// Flutter-side surface over [ProducedFilesRow] (React `ui-deliverables`
/// mounts only in the chat's turn-tail chain, which has no Dart seam yet):
/// paths arrive through [produced] — the same selector-matched list the
/// chain will feed — so the screen carries no derivation of its own.
class DeliverablesScreen extends ConsumerWidget {
  /// Creates the screen.
  const DeliverablesScreen({
    super.key,
    this.produced = const [],
    this.canOpenPath = false,
    this.onOpenFile,
  });

  /// Selector-matched produced paths.
  final List<String> produced;

  /// Whether the Host can open paths (loopback + `canOpenPath`).
  final bool canOpenPath;

  /// The file opener; defaults to no-op chips when absent.
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Translate t = ref.bindLocale(kDeliverablesNamespace);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          t('produced.label'),
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
      body: produced.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(DswTokens.spaceXl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 32,
                      color: aliases.labelCaption,
                    ),
                    const SizedBox(height: DswTokens.spaceMd),
                    Text(
                      t('empty.title'),
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeBase16,
                        fontWeight: FontWeight.w600,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('empty.hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        color: aliases.labelSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              children: [
                ProducedFilesRow(
                  paths: produced,
                  canOpenPath: canOpenPath,
                  onOpenFile: onOpenFile,
                ),
              ],
            ),
    );
  }
}
