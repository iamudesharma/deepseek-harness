import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate, kCommonNamespace;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/ds_input.dart';
import '../locales.dart' show kSkillNamespace;
import 'skill_provider.dart';

/// Skill references screen.
///
/// Mirrors `SkillRow` + skill catalog: compact accent row, disclosure for
/// instructions, inspection. Lists skill refs with search. Real `skillList()`
/// via [skillListProvider] FutureProvider (`ref.watch(connectionClientProvider).skillList(sessionId: ...)`),
/// renders `skills` with `name`/`description`. ConsumerWidget, Theme +
/// DswTokens, loading/error with `AsyncValue.when` and `Retry` that invalidates
/// the provider.
class SkillScreen extends ConsumerWidget {
  const SkillScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String query = ref.watch(skillQueryProvider);
    final AsyncValue<List<SkillRef>> async = ref.watch(skillListProvider);
    // bindLocale watches localeRevisionProvider so the screen copy follows a
    // Language-row switch.
    final Translate t = ref.bindLocale(kSkillNamespace);
    final Translate tcommon = ref.bindLocale(kCommonNamespace);

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
        actions: [
          IconButton(
            tooltip: t('refresh'),
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => ref.invalidate(skillListProvider),
          ),
          const SizedBox(width: DswTokens.spaceSm),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(DswTokens.spaceLg),
            child: DsInput(
              hintText: t('search.hint'),
              icon: Icon(Icons.search, size: 16, color: aliases.labelTertiary),
              initialValue: query,
              onChanged: (String v) =>
                  ref.read(skillQueryProvider.notifier).state = v,
            ),
          ),
          Divider(height: 1, color: aliases.borderL2),
          Expanded(
            child: async.when(
              data: (List<SkillRef> all) {
                final String q = query.trim().toLowerCase();
                final List<SkillRef> filtered = q.isEmpty
                    ? all
                    : all
                          .where(
                            (s) =>
                                s.name.toLowerCase().contains(q) ||
                                (s.description?.toLowerCase().contains(q) ??
                                    false),
                          )
                          .toList();
                if (filtered.isEmpty)
                  return _EmptySkills(
                    query: query,
                    aliases: aliases,
                    isNoSession: all.isEmpty && query.trim().isEmpty,
                  );
                return ListView.separated(
                  padding: const EdgeInsets.all(DswTokens.spaceLg),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: DswTokens.spaceSm),
                  itemBuilder: (BuildContext context, int index) =>
                      SkillRowView(skill: filtered[index], aliases: aliases),
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
                      t('loading'),
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
                        t('loadFailed'),
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
                        onPressed: () => ref.invalidate(skillListProvider),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(tcommon('retry')),
                        style: FilledButton.styleFrom(
                          backgroundColor: aliases.buttonPrimaryFill,
                          foregroundColor: aliases.labelPrimaryForeground,
                        ),
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

/// Dedicated skill row — accent summary + disclosure.
class SkillRowView extends StatefulWidget {
  const SkillRowView({super.key, required this.skill, required this.aliases});
  final SkillRef skill;
  final DswAliases aliases;

  @override
  State<SkillRowView> createState() => _SkillRowViewState();
}

class _SkillRowViewState extends State<SkillRowView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final SkillRef s = widget.skill;
    final DswAliases a = widget.aliases;
    return Container(
      decoration: BoxDecoration(
        color: a.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: a.borderL1),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DswTokens.spaceMd,
                vertical: DswTokens.spaceSm,
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: a.labelTertiary,
                  ),
                  const SizedBox(width: DswTokens.spaceSm),
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: a.labelTertiary,
                  ),
                  const SizedBox(width: DswTokens.spaceSm),
                  Text(
                    'Skill',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: a.labelCaption,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: DswTokens.spaceSm,
                    ),
                    width: 1,
                    height: 12,
                    color: a.borderL2,
                  ),
                  Expanded(
                    child: Text(
                      s.name,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w500,
                        color: a.labelPrimary,
                      ),
                    ),
                  ),
                  if (s.description != null)
                    Flexible(
                      child: Text(
                        s.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: a.labelSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: a.borderL1),
            Padding(
              padding: const EdgeInsets.all(DswTokens.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Instructions',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      fontWeight: FontWeight.w600,
                      color: a.labelCaption,
                    ),
                  ),
                  const SizedBox(height: DswTokens.spaceSm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(DswTokens.spaceMd),
                    decoration: BoxDecoration(
                      color: a.markdownCodeBlock,
                      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                    ),
                    child: SelectableText(
                      'Skill: ${s.name}\n${s.description ?? 'No description'}\nSource: ${s.source ?? 'unknown'}${s.modelInvocable == false ? '\nModel invocable: false' : ''}',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: a.labelSecondary,
                        fontFamily: 'SF Mono',
                      ),
                    ),
                  ),
                  const SizedBox(height: DswTokens.spaceSm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                            const SnackBar(content: Text('Inspect — stub')),
                          ),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Inspect'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptySkills extends ConsumerWidget {
  const _EmptySkills({
    required this.query,
    required this.aliases,
    this.isNoSession = false,
  });
  final String query;
  final DswAliases aliases;
  final bool isNoSession;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kSkillNamespace);
    final bool hasQuery = query.trim().isNotEmpty;
    if (isNoSession) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DswTokens.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
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
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.auto_awesome_outlined,
              size: 32,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              hasQuery ? t('noMatches') : t('screen.nav'),
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? 'No skills match "$query".'
                  : 'Skills will appear here once registered.',
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
