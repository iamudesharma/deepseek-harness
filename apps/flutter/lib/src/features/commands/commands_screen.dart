import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/primitives/ds_input.dart';
import 'commands_provider.dart';

/// Command discovery screen — PopupSelectView.
///
/// Thin placeholder that renders header + searchable list, handles
/// empty/loading/error, and uses [DswTokens] via [Theme].
///
/// Mirrors web `PopupSelectView` / `CommandPalette` presentation: filter input
/// on top, grouped list below, selection callback stubbed via snackbar.
class CommandsScreen extends ConsumerWidget {
  /// Creates the commands screen.
  const CommandsScreen({super.key, this.onSelect});

  /// Called when a command is selected — stub when null.
  final ValueChanged<CommandItem>? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final AsyncValue<List<CommandItem>> async = ref.watch(
      commandsAsyncProvider,
    );
    final String query = ref.watch(commandsQueryProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Commands',
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
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            child: DsInput(
              hintText: 'Search commands…',
              icon: Icon(Icons.search, size: 16, color: aliases.labelTertiary),
              initialValue: query,
              onChanged: (String v) =>
                  ref.read(commandsQueryProvider.notifier).state = v,
            ),
          ),
          Divider(height: 1, color: aliases.borderL2),
          Expanded(
            child: async.when(
              data: (List<CommandItem> items) {
                if (items.isEmpty)
                  return _EmptyCommands(query: query, aliases: aliases);
                // Group by category for presentation parity with web catalog.
                final Map<String, List<CommandItem>> grouped =
                    <String, List<CommandItem>>{};
                for (final c in items) {
                  final String key = c.category ?? 'Other';
                  grouped.putIfAbsent(key, () => <CommandItem>[]).add(c);
                }
                final List<MapEntry<String, List<CommandItem>>> entries =
                    grouped.entries.toList();
                return ListView.builder(
                  padding: const EdgeInsets.all(DswTokens.spaceLg),
                  itemCount: entries.length,
                  itemBuilder: (BuildContext context, int index) {
                    final entry = entries[index];
                    return _CommandGroup(
                      title: entry.key,
                      items: entry.value,
                      aliases: aliases,
                      onSelect: (CommandItem c) {
                        if (onSelect != null) {
                          onSelect!(c);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('/${c.name} — stub')),
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
                      'Loading commands…',
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
                        'Failed to load commands',
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
                        onPressed: () => ref.invalidate(commandsAsyncProvider),
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

class _CommandGroup extends StatelessWidget {
  const _CommandGroup({
    required this.title,
    required this.items,
    required this.aliases,
    required this.onSelect,
  });

  final String title;
  final List<CommandItem> items;
  final DswAliases aliases;
  final ValueChanged<CommandItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DswTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              fontWeight: FontWeight.w600,
              color: aliases.labelCaption,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          ...items.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
              child: _CommandRow(item: c, aliases: aliases, onSelect: onSelect),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.item,
    required this.aliases,
    required this.onSelect,
  });

  final CommandItem item;
  final DswAliases aliases;
  final ValueChanged<CommandItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: aliases.bgLayer2,
      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
      child: InkWell(
        onTap: () => onSelect(item),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: aliases.bgOverlay,
                  borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                ),
                child: Text(
                  '/${item.name}',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    fontWeight: FontWeight.w600,
                    color: aliases.stateBusinessPrimary,
                  ),
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Expanded(
                child: Text(
                  item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    color: aliases.labelSecondary,
                  ),
                ),
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Icon(Icons.chevron_right, size: 16, color: aliases.labelCaption),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCommands extends StatelessWidget {
  const _EmptyCommands({required this.query, required this.aliases});

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
              hasQuery ? Icons.search_off : Icons.terminal,
              size: 32,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              hasQuery ? 'No matches' : 'No commands',
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? 'No commands match "$query".'
                  : 'No commands available.',
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
