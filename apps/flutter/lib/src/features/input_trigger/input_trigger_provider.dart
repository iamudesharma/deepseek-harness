import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kind of inline trigger — mirrors web `TriggerKind` / `SlashMenu` sources.
enum TriggerKind { slash, at, hash }

/// Single trigger suggestion — item shown in the inline popup.
class TriggerItem {
  /// Stable id.
  final String id;

  /// Display label (e.g. command name or file path).
  final String label;

  /// Short description / hint.
  final String? description;

  /// Leading icon name hint (maps to an [IconData] in the view).
  final String? icon;

  /// Creates a trigger item.
  const TriggerItem({
    required this.id,
    required this.label,
    this.description,
    this.icon,
  });
}

/// Demo suggestions for the inline trigger popup.
///
/// Real wiring would source from the live `TriggerRegistry` / `CommandCatalog`
/// and file index; stubbed so the placeholder menu is never blank without intent.
List<TriggerItem> _demoItemsFor(TriggerKind kind) {
  switch (kind) {
    case TriggerKind.slash:
      return const <TriggerItem>[
        TriggerItem(
          id: 'goal',
          label: '/goal',
          description: 'Set session goal',
        ),
        TriggerItem(id: 'help', label: '/help', description: 'Show help'),
        TriggerItem(id: 'clear', label: '/clear', description: 'Clear goal'),
        TriggerItem(
          id: 'compact',
          label: '/compact',
          description: 'Compact context',
        ),
      ];
    case TriggerKind.at:
      return const <TriggerItem>[
        TriggerItem(
          id: 'file-readme',
          label: '@README.md',
          description: 'Project readme',
        ),
        TriggerItem(
          id: 'file-main',
          label: '@lib/main.dart',
          description: 'App entry',
        ),
        TriggerItem(
          id: 'session-1',
          label: '@session:abc123',
          description: 'Reference session',
        ),
      ];
    case TriggerKind.hash:
      return const <TriggerItem>[
        TriggerItem(id: 'tag-bug', label: '#bug', description: 'Tag as bug'),
        TriggerItem(
          id: 'tag-feature',
          label: '#feature',
          description: 'Tag as feature',
        ),
      ];
  }
}

/// Active trigger kind — `null` means popup closed.
final triggerKindProvider = StateProvider<TriggerKind?>(
  (ref) => TriggerKind.slash,
);

/// Current query typed after the trigger prefix.
final triggerQueryProvider = StateProvider<String>((ref) => '');

/// Selected index in the filtered list.
final triggerSelectedIndexProvider = StateProvider<int>((ref) => 0);

/// All items for the current kind.
final triggerItemsProvider = Provider<List<TriggerItem>>((ref) {
  final TriggerKind? kind = ref.watch(triggerKindProvider);
  if (kind == null) return const [];
  return _demoItemsFor(kind);
});

/// Filtered items by query substring.
final filteredTriggerItemsProvider = Provider<List<TriggerItem>>((ref) {
  final String q = ref.watch(triggerQueryProvider).trim().toLowerCase();
  final List<TriggerItem> all = ref.watch(triggerItemsProvider);
  if (q.isEmpty) return all;
  return all
      .where(
        (i) =>
            i.label.toLowerCase().contains(q) ||
            (i.description?.toLowerCase().contains(q) ?? false),
      )
      .toList(growable: false);
});

/// Async wrapper for screens that want loading semantics.
final triggerAsyncProvider = FutureProvider<List<TriggerItem>>((ref) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return ref.watch(filteredTriggerItemsProvider);
});
