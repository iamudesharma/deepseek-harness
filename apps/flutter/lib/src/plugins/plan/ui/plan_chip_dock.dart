/// Composer plan chip seat — Flutter port of `PlanModeControl.tsx`'s
/// `PlanChip`, mounted through the `conversation.input.plan` slot the
/// conversation hub declares (React ui-plan index.ts:52-53; rendered inside
/// the composer tool row at InputBar.tsx:713).
///
/// The chip renders only while the effective target is plan mode
/// (`pending ? !active : active` — a folded host value, not client optimism)
/// and otherwise renders nothing, so the tool row stays empty exactly like
/// the unoccupied React seat. Exit executes `/plan off` through the bound
/// [PlanControl].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../theme/app_theme.dart';
import '../locales.dart';
import '../plan_control.dart';
import 'plan_provider.dart';

/// Seat builder registered by the plugin.
Widget buildPlanSeat() => const _PlanChipSeat();

/// Module bridge binding the activated control for UI providers (the
/// bindActivatedHub pattern). UI reads the global in build — like
/// `activatedHub` — because control binding changes only around plugin
/// activation, not per frame.
PlanControl? _boundControl;

/// Bound control for widgets; null until `ui-plan` activates.
PlanControl? get boundPlanControl => _boundControl;

/// Binds (or clears) the plan control bridge.
void bindPlanControl(PlanControl? control) => _boundControl = control;

class _PlanChipSeat extends ConsumerWidget {
  const _PlanChipSeat();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final PlanState plan = ref.watch(planProvider);

    // Effective target: a pending switch shows the state it is heading to.
    final bool target = plan.pending ? !plan.active : plan.active;
    if (!target) return const SizedBox.shrink();

    return _PlanChip(
      locked: plan.pending,
      aliases: aliases,
      onExit: () async {
        final SessionId? sessionId = ref.read(currentSessionIdProvider);
        if (sessionId == null) return 'unknown command: /plan off';
        final PlanControl? control = boundPlanControl;
        if (control == null) {
          throw StateError(
            'plan control is not bound (ui-plan plugin inactive)',
          );
        }
        return control.exitPlanMode(sessionId);
      },
    );
  }
}

/// The chip itself: wordmark + close glyph, disabled while leaving.
class _PlanChip extends StatefulWidget {
  const _PlanChip({
    required this.locked,
    required this.aliases,
    required this.onExit,
  });

  final bool locked;
  final DswAliases aliases;
  final Future<String?> Function() onExit;

  @override
  State<_PlanChip> createState() => _PlanChipState();
}

class _PlanChipState extends State<_PlanChip> {
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
      setState(() {
        _leaving = false;
        _error = failure;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _leaving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool disabled = widget.locked || _leaving;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DswTokens.spaceSm,
      children: [
        Tooltip(
          message: kPlanEn['chip.on.title']!,
          child: Material(
            color: widget.aliases.stateBusinessTertiary,
            borderRadius: BorderRadius.circular(DswTokens.radiusFull),
            child: InkWell(
              onTap: disabled ? null : _off,
              borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                  border: Border.all(
                    color: widget.aliases.stateBusinessPrimary.withValues(
                      alpha: 0.2,
                    ),
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
                          color: widget.aliases.stateBusinessPrimary,
                        ),
                      )
                    else
                      Text(
                        'Plan',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeS14,
                          fontWeight: FontWeight.w600,
                          color: widget.aliases.stateBusinessPrimary,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.close,
                      size: 12,
                      color: widget.aliases.stateBusinessPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Failure copy stays English (error-surface policy: not localized).
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: widget.aliases.stateErrorPrimary,
            ),
          ),
      ],
    );
  }
}
