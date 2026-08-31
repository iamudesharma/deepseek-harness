import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Minimal command descriptor — mirrors `CommandView` / `CommandCatalog` in
/// `@deepseek-ai/dsh-command` trimmed to UI-required fields.
class CommandItem {
  /// Command name without leading slash, e.g. `goal`, `help`.
  final String name;

  /// Short description.
  final String description;

  /// Optional category bucket for grouping.
  final String? category;

  /// Whether the command is hidden from discovery.
  final bool hidden;

  /// Creates a command item.
  const CommandItem({
    required this.name,
    required this.description,
    this.category,
    this.hidden = false,
  });
}

/// Demo catalog used as stub data for [CommandsScreen].
///
/// Real wiring would read the host `command/list` projection.
List<CommandItem> _demoCommands() => const <CommandItem>[
  CommandItem(
    name: 'goal',
    description: 'Create or update the session goal',
    category: 'Goal',
  ),
  CommandItem(
    name: 'help',
    description: 'Show available commands',
    category: 'General',
  ),
  CommandItem(
    name: 'clear',
    description: 'Clear the current goal',
    category: 'Goal',
  ),
  CommandItem(
    name: 'jobs',
    description: 'List background jobs',
    category: 'Jobs',
  ),
  CommandItem(name: 'skill', description: 'Invoke a skill', category: 'Skills'),
  CommandItem(
    name: 'compact',
    description: 'Compact the conversation',
    category: 'Context',
  ),
  CommandItem(
    name: 'workflow',
    description: 'Run a workflow',
    category: 'Workflow',
  ),
  CommandItem(
    name: 'subagent',
    description: 'Delegate to a subagent',
    category: 'Subagent',
  ),
];

/// Sync catalog provider.
final commandsProvider = Provider<List<CommandItem>>((ref) => _demoCommands());

/// Search query for the popup filter — mirrors `PopupSelectView` filter state.
final commandsQueryProvider = StateProvider<String>((ref) => '');

/// Filtered view of the catalog by [commandsQueryProvider].
final filteredCommandsProvider = Provider<List<CommandItem>>((ref) {
  final String q = ref.watch(commandsQueryProvider).trim().toLowerCase();
  final List<CommandItem> all = ref.watch(commandsProvider);
  if (q.isEmpty) return all;
  return all
      .where(
        (c) =>
            c.name.toLowerCase().contains(q) ||
            c.description.toLowerCase().contains(q),
      )
      .toList(growable: false);
});

/// Async wrapper for screens that want loading semantics.
final commandsAsyncProvider = FutureProvider<List<CommandItem>>((ref) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return ref.watch(filteredCommandsProvider);
});
