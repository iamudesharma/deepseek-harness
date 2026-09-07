import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef, Translate;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart' show kPlanNamespace;
import '../plan_control.dart';
import 'plan_chip_dock.dart' show boundPlanControl;
import 'plan_provider.dart';

/// Plan screen — PlanModeControl + status.
///
/// Mirrors `PlanChip` (ui-plan): chip renders only while effective target is
/// plan mode (`pending ? !active : active`) and executes /plan off through
/// the plugin-bound [PlanControl]. ConsumerWidget, Theme + DswTokens.
class PlanScreen extends ConsumerWidget {
  /// Creates the plan screen.
  const PlanScreen({super.key});

  Future<String?> _exitPlanMode(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(planProvider.notifier);
    final SessionId? sessionId = ref.read(currentSessionIdProvider);
    if (sessionId == null) return 'unknown command: /plan off';
    final PlanControl? control = boundPlanControl;
    if (control == null) {
      throw StateError('plan control is not bound (ui-plan plugin inactive)');
    }
    notifier.setPending();
    final String? failure = await control.exitPlanMode(sessionId);
    notifier.settle(active: failure != null, error: failure);
    return failure;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final PlanState plan = ref.watch(planProvider);
    // bindLocale watches localeRevisionProvider so the screen copy follows a
    // Language-row switch.
    final Translate t = ref.bindLocale(kPlanNamespace);

    final bool target = plan.pending ? !plan.active : plan.active;
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
      body: !target
          ? _InactivePlan(
              aliases: aliases,
              onEnter: () => ref.read(planProvider.notifier).enter(),
            )
          : ListView(
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              children: [
                PlanModeControl(
                  plan: plan,
                  onExit: () => _exitPlanMode(context, ref),
                ),
                const SizedBox(height: DswTokens.spaceLg),
                _PlanStatusCard(plan: plan, aliases: aliases),
                if (plan.error != null) ...[
                  const SizedBox(height: DswTokens.spaceSm),
                  Container(
                    padding: const EdgeInsets.all(DswTokens.spaceMd),
                    decoration: BoxDecoration(
                      color: aliases.stateErrorPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                      border: Border.all(
                        color: aliases.stateErrorPrimary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'failed to exit plan mode: ${plan.error}',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        color: aliases.stateErrorPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Reusable PlanModeControl chip — matches web PlanChip visuals.
class PlanModeControl extends ConsumerStatefulWidget {
  /// Creates the chip.
  const PlanModeControl({super.key, required this.plan, required this.onExit});

  /// Folded projection state.
  final PlanState plan;

  /// Exit execution through the bound control.
  final Future<String?> Function() onExit;

  @override
  ConsumerState<PlanModeControl> createState() => _PlanModeControlState();
}

class _PlanModeControlState extends ConsumerState<PlanModeControl> {
  bool _leaving = false;
  String? _error;

  Future<void> _off() async {
    setState(() {
      _leaving = true;
      _error = null;
    });
    try {
      final String? failure = await widget.onExit();
      if (!mounted) return;
      setState(() => _error = failure);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool locked = widget.plan.pending || _leaving;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DswTokens.spaceSm,
      children: [
        Material(
          color: aliases.stateBusinessTertiary,
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          child: InkWell(
            onTap: locked ? null : _off,
            borderRadius: BorderRadius.circular(DswTokens.radiusFull),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                border: Border.all(
                  color: aliases.stateBusinessPrimary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_leaving)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: aliases.stateBusinessPrimary,
                      ),
                    )
                  else
                    Text(
                      'Plan',
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w600,
                        color: aliases.stateBusinessPrimary,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.close,
                    size: 12,
                    color: aliases.stateBusinessPrimary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_error != null)
          Text(
            'failed to exit plan mode',
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.stateErrorPrimary,
            ),
          ),
      ],
    );
  }
}

class _PlanStatusCard extends StatelessWidget {
  const _PlanStatusCard({required this.plan, required this.aliases});

  final PlanState plan;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final String status = plan.pending
        ? 'Switching…'
        : plan.active
        ? 'Plan mode active'
        : 'Plan mode off';
    final String desc = plan.active
        ? 'The agent is in read-only planning. Exit to allow edits.'
        : 'Planning complete — agent may edit.';
    return Container(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: plan.active
                  ? aliases.stateBusinessTertiary
                  : aliases.bgOverlay,
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
            ),
            child: Icon(
              plan.active ? Icons.map_outlined : Icons.check_circle_outline,
              size: 18,
              color: plan.active
                  ? aliases.stateBusinessPrimary
                  : aliases.labelTertiary,
            ),
          ),
          const SizedBox(width: DswTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    fontWeight: FontWeight.w600,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InactivePlan extends ConsumerWidget {
  const _InactivePlan({required this.aliases, required this.onEnter});

  final DswAliases aliases;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Translate t = ref.bindLocale(kPlanNamespace);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DswTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.layers_clear_outlined,
              size: 32,
              color: aliases.labelCaption,
            ),
            const SizedBox(height: DswTokens.spaceMd),
            Text(
              t('off.title'),
              style: TextStyle(
                fontSize: DswTokens.fontSizeBase16,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('off.hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelSecondary,
              ),
            ),
            const SizedBox(height: DswTokens.spaceLg),
            OutlinedButton.icon(
              onPressed: onEnter,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: Text(t('enter')),
            ),
          ],
        ),
      ),
    );
  }
}
