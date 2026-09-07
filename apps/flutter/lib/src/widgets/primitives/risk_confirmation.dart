import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'ds_button.dart';
import 'ds_modal.dart';

/// Risk acknowledgement dialog — Flutter port of `RiskConfirmation.tsx` +
/// `RiskConfirmation.module.css`.
///
/// Gates a sensitive action behind an explicit checkbox. Primary action is
/// disabled until [acknowledged] is true. Pure build, no `ctx`.
class DsRiskConfirmation extends ConsumerWidget {
  const DsRiskConfirmation({
    super.key,
    required this.open,
    required this.title,
    required this.description,
    required this.acknowledgeLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.acknowledged,
    required this.onAcknowledgedChange,
    required this.onCancel,
    required this.onConfirm,
    this.disabled = false,
  });

  /// Whether the dialog is visible.
  final bool open;

  /// Dialog heading.
  final String title;

  /// Warning body text.
  final String description;

  /// Checkbox label (e.g. "I understand the risks").
  final String acknowledgeLabel;

  /// Cancel button label.
  final String cancelLabel;

  /// Confirm button label.
  final String confirmLabel;

  /// Controlled checkbox state.
  final bool acknowledged;

  /// When true disables both checkbox and confirm button.
  final bool disabled;

  /// Called when the checkbox value changes.
  final ValueChanged<bool> onAcknowledgedChange;

  /// Called on cancel / mask dismiss.
  final VoidCallback onCancel;

  /// Called on confirm. Guarded by [acknowledged] && !disabled.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!open) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return DsModalOverlay(
      open: open,
      title: title,
      onClose: onCancel,
      width: 440,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72),
            child: DsButton(
              variant: DsButtonVariant.elevated,
              label: cancelLabel,
              onPressed: onCancel,
            ),
          ),
          const SizedBox(width: DswTokens.spaceSm),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 136),
            child: DsButton(
              variant: DsButtonVariant.primary,
              label: confirmLabel,
              onPressed: (disabled || !acknowledged) ? null : onConfirm,
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Warning row — icon + description — mirrors `RiskConfirmation.module.css .warning`.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: aliases.stateErrorPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  description,
                  style: TextStyle(
                    color: aliases.labelSecondary,
                    fontSize: DswTokens.fontSizeS14,
                    height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                    fontFamily: 'SF Pro',
                    fontFamilyFallback: DswTokens.fontFamilyFallback,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Acknowledgement checkbox — mirrors `.acknowledgement`.
          InkWell(
            onTap: disabled ? null : () => onAcknowledgedChange(!acknowledged),
            borderRadius: BorderRadius.circular(DswTokens.radiusSm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Checkbox(
                    value: acknowledged,
                    onChanged: disabled
                        ? null
                        : (bool? v) => onAcknowledgedChange(v ?? false),
                    activeColor: aliases.buttonPrimaryFill,
                    checkColor: aliases.labelPrimaryInverted,
                    side: BorderSide(color: aliases.borderL3),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    acknowledgeLabel,
                    style: TextStyle(
                      color: aliases.labelPrimary,
                      fontSize: DswTokens.fontSizeS14,
                      height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                      fontFamily: 'SF Pro',
                      fontFamilyFallback: DswTokens.fontFamilyFallback,
                    ),
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
