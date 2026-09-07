import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/primitives/ds_input.dart';
import 'input_trigger_provider.dart';
import 'menu_view.dart';

/// Input trigger screen — inline trigger menu demo.
///
/// Thin placeholder that renders header + composer stub + popup menu view.
/// Handles empty/loading/error via [triggerAsyncProvider] and uses
/// [DswTokens] via [Theme]. Mirrors web `InputTrigger` / `TriggerHost`
/// presentation without importing host services.
///
/// When mounted as a route, this screen is a standalone debug harness for
/// the popup — real usage anchors [TriggerMenuView] inside the conversation
/// composer overlay.
class InputTriggerScreen extends ConsumerWidget {
  /// Creates the input trigger screen.
  const InputTriggerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final TriggerKind? kind = ref.watch(triggerKindProvider);
    final String query = ref.watch(triggerQueryProvider);
    final int selectedIndex = ref.watch(triggerSelectedIndexProvider);
    final AsyncValue<List<TriggerItem>> async = ref.watch(triggerAsyncProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Input Trigger',
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
      body: ListView(
        padding: const EdgeInsets.all(DswTokens.spaceLg),
        children: [
          _KindSelector(
            aliases: aliases,
            selected: kind,
            onSelect: (TriggerKind? k) {
              ref.read(triggerKindProvider.notifier).state = k;
              ref.read(triggerSelectedIndexProvider.notifier).state = 0;
            },
          ),
          const SizedBox(height: DswTokens.spaceLg),
          Container(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            decoration: BoxDecoration(
              color: aliases.bgLayer2,
              borderRadius: BorderRadius.circular(DswTokens.radiusLg),
              border: Border.all(color: aliases.borderL2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: aliases.labelTertiary,
                    ),
                    const SizedBox(width: DswTokens.spaceSm),
                    Text(
                      'Composer preview',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w600,
                        color: aliases.labelPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (kind == null)
                      Text(
                        'Menu hidden',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelCaption,
                        ),
                      )
                    else
                      Text(
                        'Trigger: ${kind.name}',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: DswTokens.spaceMd),
                DsInput(
                  hintText: kind == null
                      ? 'Type / @ # to open menu…'
                      : 'Filter…',
                  initialValue: query,
                  onChanged: (String v) =>
                      ref.read(triggerQueryProvider.notifier).state = v,
                  icon: Icon(
                    kind == null ? Icons.search : Icons.filter_alt_outlined,
                    size: 16,
                    color: aliases.labelTertiary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceLg),
                async.when(
                  data: (List<TriggerItem> items) {
                    if (kind == null) {
                      return _InlineEmpty(
                        aliases: aliases,
                        message:
                            'Select a trigger kind above to show the menu.',
                      );
                    }
                    if (items.isEmpty) {
                      return TriggerMenuView(
                        items: const [],
                        selectedIndex: -1,
                        onSelect: (_) {},
                        emptyLabel: 'No matches for "$query"',
                      );
                    }
                    return TriggerMenuView(
                      items: items,
                      selectedIndex: selectedIndex.clamp(0, items.length - 1),
                      onHover: (int idx) =>
                          ref
                                  .read(triggerSelectedIndexProvider.notifier)
                                  .state =
                              idx,
                      onSelect: (TriggerItem it) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Selected ${it.label} — stub'),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(DswTokens.spaceLg),
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
                            'Loading suggestions…',
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              color: aliases.labelSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  error: (Object err, StackTrace st) => _ErrorCard(
                    error: err.toString(),
                    aliases: aliases,
                    onRetry: () => ref.invalidate(triggerAsyncProvider),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DswTokens.spaceMd),
          Text(
            'Keyboard: ↑/↓ to move, Enter to select, Esc to dismiss.',
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelCaption,
            ),
          ),
        ],
      ),
    );
  }
}

class _KindSelector extends StatelessWidget {
  const _KindSelector({
    required this.aliases,
    required this.selected,
    required this.onSelect,
  });

  final DswAliases aliases;
  final TriggerKind? selected;
  final ValueChanged<TriggerKind?> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, TriggerKind? kind) {
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
      runSpacing: DswTokens.spaceSm,
      children: [
        chip('None', null),
        chip('/ slash', TriggerKind.slash),
        chip('@ mention', TriggerKind.at),
        chip('# tag', TriggerKind.hash),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.aliases, required this.message});

  final DswAliases aliases;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: aliases.bgOverlay,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL1),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: aliases.labelCaption),
          const SizedBox(width: DswTokens.spaceSm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.error,
    required this.aliases,
    required this.onRetry,
  });

  final String error;
  final DswAliases aliases;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceMd),
      decoration: BoxDecoration(
        color: aliases.bgOverlay,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(
          color: aliases.stateErrorPrimary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: aliases.stateErrorPrimary,
              ),
              const SizedBox(width: DswTokens.spaceSm),
              Text(
                'Failed to load suggestions',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: DswTokens.spaceSm),
          SelectableText(
            error,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelSecondary,
            ),
          ),
          const SizedBox(height: DswTokens.spaceSm),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
