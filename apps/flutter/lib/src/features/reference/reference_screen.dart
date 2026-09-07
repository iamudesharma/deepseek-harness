import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/primitives/ds_input.dart';
import 'reference_provider.dart';

/// Reference source view — `@file` / `@session` picker.
///
/// Thin placeholder that renders header + filter + list, handles
/// empty/loading/error, and uses [DswTokens] via [Theme].
/// Mirrors web `ReferencePicker` / `FileMentionView` presentation.
class ReferenceScreen extends ConsumerWidget {
  /// Creates the reference screen.
  const ReferenceScreen({super.key, this.onSelect});

  /// Called when a source is chosen.
  final ValueChanged<ReferenceSource>? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String query = ref.watch(referenceQueryProvider);
    final ReferenceKind? kindFilter = ref.watch(referenceKindFilterProvider);
    final AsyncValue<List<ReferenceSource>> async = ref.watch(
      referencesAsyncProvider,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'References',
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DswTokens.spaceLg,
              DswTokens.spaceLg,
              DswTokens.spaceLg,
              DswTokens.spaceSm,
            ),
            child: DsInput(
              hintText: 'Search files or sessions…',
              icon: Icon(Icons.search, size: 16, color: aliases.labelTertiary),
              initialValue: query,
              onChanged: (String v) =>
                  ref.read(referenceQueryProvider.notifier).state = v,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceLg),
            child: _KindFilter(
              aliases: aliases,
              selected: kindFilter,
              onSelect: (ReferenceKind? k) =>
                  ref.read(referenceKindFilterProvider.notifier).state = k,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          Divider(height: 1, color: aliases.borderL2),
          Expanded(
            child: async.when(
              data: (List<ReferenceSource> items) {
                if (items.isEmpty)
                  return _EmptyReferences(query: query, aliases: aliases);
                return ListView.separated(
                  padding: const EdgeInsets.all(DswTokens.spaceLg),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: DswTokens.spaceSm),
                  itemBuilder: (BuildContext context, int index) {
                    final ReferenceSource src = items[index];
                    return _ReferenceTile(
                      source: src,
                      aliases: aliases,
                      onTap: () {
                        if (onSelect != null) {
                          onSelect!(src);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Selected ${src.label} — stub'),
                            ),
                          );
                        }
                      },
                    );
                  },
                );
              },
              loading: () => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: aliases.labelTertiary,
                      ),
                    ),
                    const SizedBox(height: DswTokens.spaceMd),
                    Text(
                      'Loading references…',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        color: aliases.labelSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              error: (Object err, StackTrace st) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(DswTokens.spaceLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 28,
                        color: aliases.stateErrorPrimary,
                      ),
                      const SizedBox(height: DswTokens.spaceSm),
                      Text(
                        'Failed to load references',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          fontWeight: FontWeight.w600,
                          color: aliases.labelPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        err.toString(),
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelSecondary,
                        ),
                      ),
                      const SizedBox(height: DswTokens.spaceMd),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.invalidate(referencesAsyncProvider),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindFilter extends StatelessWidget {
  const _KindFilter({
    required this.aliases,
    required this.selected,
    required this.onSelect,
  });

  final DswAliases aliases;
  final ReferenceKind? selected;
  final ValueChanged<ReferenceKind?> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, ReferenceKind? kind) {
      final bool active = selected == kind;
      return ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: DswTokens.fontSizeS14,
            color: active ? aliases.labelPrimary : aliases.labelSecondary,
          ),
        ),
        selected: active,
        onSelected: (_) => onSelect(kind),
        backgroundColor: aliases.bgLayer2,
        selectedColor: aliases.specificSidebarNavItemActive,
        side: BorderSide(
          color: active ? aliases.buttonGhostActiveBorder : aliases.borderL2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
        ),
      );
    }

    return Wrap(
      spacing: DswTokens.spaceSm,
      children: [
        chip('All', null),
        chip('@file', ReferenceKind.file),
        chip('@session', ReferenceKind.session),
      ],
    );
  }
}

class _ReferenceTile extends StatelessWidget {
  const _ReferenceTile({
    required this.source,
    required this.aliases,
    required this.onTap,
  });

  final ReferenceSource source;
  final DswAliases aliases;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData icon = source.kind == ReferenceKind.file
        ? Icons.description_outlined
        : Icons.chat_bubble_outline;
    final String kindLabel = source.kind == ReferenceKind.file
        ? 'file'
        : 'session';
    return Material(
      color: aliases.bgLayer2,
      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DswTokens.spaceMd,
            vertical: DswTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            border: Border.all(color: aliases.borderL1),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: aliases.bgOverlay,
                  borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                ),
                child: Icon(icon, size: 16, color: aliases.labelTertiary),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            source.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              fontWeight: FontWeight.w500,
                              color: aliases.labelPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: DswTokens.spaceSm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: aliases.bgOverlay,
                            borderRadius: BorderRadius.circular(
                              DswTokens.radiusFull,
                            ),
                          ),
                          child: Text(
                            kindLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: aliases.labelTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (source.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        source.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Icon(Icons.add, size: 16, color: aliases.labelTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyReferences extends StatelessWidget {
  const _EmptyReferences({required this.query, required this.aliases});

  final String query;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = query.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.folder_open,
              size: 32,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              hasQuery ? 'No matches' : 'No references',
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? 'No references match "$query".'
                  : 'Reference files or sessions with @ to attach context.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
