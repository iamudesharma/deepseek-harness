import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'ds_button.dart';

/// One step in the onboarding flow.
class DsOnboardingStep {
  const DsOnboardingStep({
    required this.title,
    required this.description,
    this.illustration,
    this.ctaLabel = 'Next',
  });

  final String title;
  final String description;
  final Widget? illustration;
  final String ctaLabel;
}

/// Full-viewport takeover — Flutter port of `OnboardingSurface.tsx` +
/// `OnboardingSurface.module.css`.
///
/// Full-screen mask + opaque stage, centered step content. Keeps the
/// underlying UI inert while mounted (via [ModalBarrier]). Shows a progress
/// indicator and CTA row. Pure build, no `ctx`.
class DsOnboardingSurface extends ConsumerWidget {
  const DsOnboardingSurface({
    super.key,
    required this.steps,
    this.currentStep = 0,
    this.onNext,
    this.onSkip,
    this.onComplete,
    this.skipLabel = 'Skip',
    this.completeLabel = 'Get started',
  });

  /// Ordered steps.
  final List<DsOnboardingStep> steps;

  /// Index of the currently visible step.
  final int currentStep;

  /// Called when the primary CTA is pressed and more steps remain.
  final VoidCallback? onNext;

  /// Called when Skip is pressed.
  final VoidCallback? onSkip;

  /// Called when the final CTA is pressed.
  final VoidCallback? onComplete;

  /// Label for the skip affordance.
  final String skipLabel;

  /// Label for the final step CTA.
  final String completeLabel;

  bool get _isLast => currentStep >= steps.length - 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (steps.isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final int safeIndex = currentStep.clamp(0, steps.length - 1);
    final DsOnboardingStep step = steps[safeIndex];

    return Material(
      color: aliases.bgMask1,
      child: Stack(
        children: <Widget>[
          // Mask — covers the application, inert barrier
          Positioned.fill(child: Container(color: aliases.bgMask1)),
          // Stage — opaque centered surface
          Center(
            child: Container(
              width: 480,
              constraints: const BoxConstraints(maxWidth: 480),
              margin: const EdgeInsets.all(DswTokens.spaceXl),
              padding: const EdgeInsets.all(DswTokens.space2xl),
              decoration: BoxDecoration(
                color: aliases.bgLayer1,
                borderRadius: BorderRadius.circular(DswTokens.radius2xl),
                border: Border.all(color: aliases.borderInverted),
                boxShadow: DswTokens.shadowLv3,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Progress dots
                  if (steps.length > 1) ...<Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (int i = 0; i < steps.length; i++)
                          Container(
                            width: i == safeIndex ? 24 : 8,
                            height: 8,
                            margin: EdgeInsets.only(
                              right: i == steps.length - 1 ? 0 : 6,
                            ),
                            decoration: BoxDecoration(
                              color: i == safeIndex
                                  ? aliases.brandPrimaryNewColor
                                  : aliases.borderL2,
                              borderRadius: BorderRadius.circular(
                                DswTokens.radiusFull,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: DswTokens.spaceXl),
                  ],
                  if (step.illustration != null) ...<Widget>[
                    Center(child: step.illustration!),
                    const SizedBox(height: DswTokens.spaceXl),
                  ],
                  Text(
                    step.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: aliases.labelPrimary,
                      fontSize: DswTokens.fontSizeL20,
                      height: DswTokens.lineHeightL20 / DswTokens.fontSizeL20,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SF Pro',
                      fontFamilyFallback: DswTokens.fontFamilyFallback,
                    ),
                  ),
                  const SizedBox(height: DswTokens.spaceSm),
                  Text(
                    step.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: aliases.labelSecondary,
                      fontSize: DswTokens.fontSizeS14,
                      height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                      fontFamily: 'SF Pro',
                      fontFamilyFallback: DswTokens.fontFamilyFallback,
                    ),
                  ),
                  const SizedBox(height: DswTokens.spaceXl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (!_isLast && onSkip != null) ...<Widget>[
                        DsButton(
                          variant: DsButtonVariant.ghost,
                          label: skipLabel,
                          onPressed: onSkip,
                        ),
                        const SizedBox(width: DswTokens.spaceSm),
                      ],
                      DsButton(
                        variant: DsButtonVariant.primary,
                        label: _isLast ? completeLabel : step.ctaLabel,
                        onPressed: _isLast ? (onComplete ?? onNext) : onNext,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline overlay variant that portals via [Overlay] when [open] is true.
class DsOnboardingOverlay extends ConsumerWidget {
  const DsOnboardingOverlay({
    super.key,
    required this.open,
    required this.steps,
    this.currentStep = 0,
    this.onNext,
    this.onSkip,
    this.onComplete,
  });

  final bool open;
  final List<DsOnboardingStep> steps;
  final int currentStep;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!open) return const SizedBox.shrink();
    return DsOnboardingSurface(
      steps: steps,
      currentStep: currentStep,
      onNext: onNext,
      onSkip: onSkip,
      onComplete: onComplete,
    );
  }
}
