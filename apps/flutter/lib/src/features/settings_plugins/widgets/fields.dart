/// Hand-written controls for plugin configuration forms.
///
/// Mirrors `packages/client/ui-settings-plugins/src/client/fields.tsx`:
/// ValueField (staged value + Overridden/Reset + invalid hint) and
/// SecretField (write-only credential).
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// One staged value field.
///
/// [numeric] only hints keypad; validation is spec-driven so control never
/// silently rewrites typed text.
class ValueField extends StatelessWidget {
  const ValueField({
    super.key,
    required this.id,
    required this.label,
    required this.hint,
    required this.text,
    required this.overridden,
    required this.invalid,
    required this.overriddenLabel,
    required this.resetLabel,
    required this.invalidLabel,
    required this.disabled,
    required this.onEdit,
    required this.onReset,
    this.numeric = false,
    this.placeholder = '',
  });

  final String id;
  final String label;
  final String hint;
  final String text;
  final bool overridden;
  final bool invalid;
  final String overriddenLabel;
  final String resetLabel;
  final String invalidLabel;
  final bool disabled;
  final ValueChanged<String> onEdit;
  final VoidCallback onReset;
  final bool numeric;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
            (Theme.of(context).brightness == Brightness.dark
                ? DswTokens.darkAliases
                : DswTokens.lightAliases);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w500,
                  color: aliases.labelPrimary,
                ),
              ),
            ),
            if (overridden) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: aliases.bgOverlay,
                  borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                ),
                child: Text(
                  overriddenLabel,
                  style: TextStyle(fontSize: 11, color: aliases.labelTertiary),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: disabled ? null : onReset,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  resetLabel,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          key: ValueKey<String>(id),
          controller: TextEditingController(text: text)
            ..selection = TextSelection.collapsed(offset: text.length),
          enabled: !disabled,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          obscureText: false,
          decoration: InputDecoration(
            hintText: placeholder.isEmpty ? null : placeholder,
            filled: true,
            fillColor: aliases.specificInputMajor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceMd,
              vertical: DswTokens.spaceSm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(
                color: invalid ? aliases.stateErrorPrimary : aliases.borderL2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(
                color: invalid ? aliases.stateErrorPrimary : aliases.borderL2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(
                color: invalid ? aliases.stateErrorPrimary : aliases.stateBusinessPrimary,
                width: 1.5,
              ),
            ),
          ),
          style: TextStyle(
            fontSize: DswTokens.fontSizeS14,
            color: aliases.labelPrimary,
          ),
          onChanged: onEdit,
        ),
        const SizedBox(height: 4),
        Text(
          invalid ? invalidLabel : hint,
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: invalid ? aliases.stateErrorPrimary : aliases.labelTertiary,
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
      ],
    );
  }
}

/// Write-only credential control — value never rides describe response.
///
/// Shows configured badge; blank draft writes nothing.
class SecretField extends StatelessWidget {
  const SecretField({
    super.key,
    required this.id,
    required this.label,
    required this.hint,
    required this.text,
    required this.disabled,
    required this.configured,
    required this.stateLabel,
    required this.onEdit,
  });

  final String id;
  final String label;
  final String hint;
  final String text;
  final bool disabled;
  final bool configured;
  final String stateLabel;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
            (Theme.of(context).brightness == Brightness.dark
                ? DswTokens.darkAliases
                : DswTokens.lightAliases);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeS14,
                  fontWeight: FontWeight.w500,
                  color: aliases.labelPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: configured ? aliases.stateSuccessTertiary : aliases.bgOverlay,
                borderRadius: BorderRadius.circular(DswTokens.radiusFull),
              ),
              child: Text(
                stateLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: configured ? aliases.stateSuccessPrimary : aliases.labelTertiary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          key: ValueKey<String>(id),
          controller: TextEditingController(text: text)
            ..selection = TextSelection.collapsed(offset: text.length),
          enabled: !disabled,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            filled: true,
            fillColor: aliases.specificInputMajor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceMd,
              vertical: DswTokens.spaceSm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(color: aliases.borderL2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(color: aliases.borderL2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DswTokens.radiusMd),
              borderSide: BorderSide(color: aliases.stateBusinessPrimary, width: 1.5),
            ),
          ),
          style: TextStyle(
            fontSize: DswTokens.fontSizeS14,
            color: aliases.labelPrimary,
          ),
          onChanged: onEdit,
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(
            fontSize: DswTokens.fontSizeXxs12,
            color: aliases.labelTertiary,
          ),
        ),
        const SizedBox(height: DswTokens.spaceMd),
      ],
    );
  }
}
