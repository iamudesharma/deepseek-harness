import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Source kind for a reference — mirrors web `@file` / `@session` triggers.
enum ReferenceKind { file, session }

/// Minimal reference source — an `@file` path or `@session` entry.
class ReferenceSource {
  /// Stable id (path or sessionId).
  final String id;

  /// Display label.
  final String label;

  /// Kind discriminant.
  final ReferenceKind kind;

  /// Optional subtitle — snippet or session title.
  final String? subtitle;

  /// Optional file extension / language hint for icons.
  final String? language;

  /// Creates a reference source.
  const ReferenceSource({
    required this.id,
    required this.label,
    required this.kind,
    this.subtitle,
    this.language,
  });
}

List<ReferenceSource> _demoReferences() => const <ReferenceSource>[
  ReferenceSource(
    id: 'lib/main.dart',
    label: 'lib/main.dart',
    kind: ReferenceKind.file,
    subtitle: 'App entry — 42 lines',
    language: 'dart',
  ),
  ReferenceSource(
    id: 'packages/goal/goal/src/domain.ts',
    label: 'packages/goal/goal/src/domain.ts',
    kind: ReferenceKind.file,
    subtitle: 'Goal domain — host vocabulary',
    language: 'ts',
  ),
  ReferenceSource(
    id: 'apps/flutter/lib/src/theme/dsw_tokens.dart',
    label: 'apps/flutter/lib/src/theme/dsw_tokens.dart',
    kind: ReferenceKind.file,
    subtitle: 'Design tokens — 641 lines',
    language: 'dart',
  ),
  ReferenceSource(
    id: 'session-abc123',
    label: '@session:abc123',
    kind: ReferenceKind.session,
    subtitle: 'Previous trajectory — 3 turns',
  ),
  ReferenceSource(
    id: 'session-xyz789',
    label: '@session:xyz789',
    kind: ReferenceKind.session,
    subtitle: 'Blank session',
  ),
];

/// Sync catalog.
final referenceSourcesProvider = Provider<List<ReferenceSource>>(
  (ref) => _demoReferences(),
);

/// Search query.
final referenceQueryProvider = StateProvider<String>((ref) => '');

/// Selected kind filter — null means all.
final referenceKindFilterProvider = StateProvider<ReferenceKind?>(
  (ref) => null,
);

/// Filtered view by query + kind.
final filteredReferencesProvider = Provider<List<ReferenceSource>>((ref) {
  final String q = ref.watch(referenceQueryProvider).trim().toLowerCase();
  final ReferenceKind? kind = ref.watch(referenceKindFilterProvider);
  Iterable<ReferenceSource> items = ref.watch(referenceSourcesProvider);
  if (kind != null) items = items.where((r) => r.kind == kind);
  if (q.isNotEmpty) {
    items = items.where(
      (r) =>
          r.label.toLowerCase().contains(q) ||
          (r.subtitle?.toLowerCase().contains(q) ?? false),
    );
  }
  return items.toList(growable: false);
});

/// Async wrapper.
final referencesAsyncProvider = FutureProvider<List<ReferenceSource>>((
  ref,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return ref.watch(filteredReferencesProvider);
});
