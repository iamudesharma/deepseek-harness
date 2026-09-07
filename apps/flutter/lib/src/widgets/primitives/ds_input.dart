import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

/// Input size — maps to 36 (regular) / 32 (compact) heights.
enum DsInputSize { regular, small }

/// Single-line text input atom — Flutter port of `Input.tsx` +
/// `Input.module.css`.
///
/// Wrap height 36 regular / 32 small, padding 0 8, gap 6, radius 8,
/// bgLayer1, borderL2, focus `stateBusinessPrimary`, error
/// `stateErrorPrimary`, disabled bg 50% opacity, prefix icon 16,
/// placeholder `labelCaption`. Supports validation and obscure for password.
/// Pure build, no ctx; slots → Widget? for [icon].
class DsInput extends ConsumerWidget {
  const DsInput({
    super.key,
    this.icon,
    this.controller,
    this.focusNode,
    this.hintText,
    this.label,
    this.errorText,
    this.helperText,
    this.required = false,
    this.validator,
    this.size = DsInputSize.regular,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.readOnly = false,
    this.suffix,
    this.hintStyle,
    this.style,
    this.contentPadding,
  });

  /// Optional leading 16px icon.
  final Widget? icon;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;

  /// Optional label above the field (12/16, labelSecondary).
  final String? label;

  /// Error text — when non-null shows error border (stateErrorPrimary).
  final String? errorText;

  /// Helper text below when no error.
  final String? helperText;

  /// When true empty value fails validation with required message.
  final bool required;

  /// Custom validator — composed with [required] check.
  final FormFieldValidator<String>? validator;

  /// Height variant: 36 regular / 32 small.
  final DsInputSize size;

  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? minLines;
  final bool readOnly;
  final Widget? suffix;
  final TextStyle? hintStyle;
  final TextStyle? style;
  final EdgeInsetsGeometry? contentPadding;

  bool get _hasError => errorText != null && errorText!.isNotEmpty;
  double get _height => size == DsInputSize.small
      ? DswTokens.inputHeightSmall
      : DswTokens.inputHeightRegular;

  String? _validate(String? v) {
    if (required && (v == null || v.isEmpty)) return 'Required';
    if (validator != null) return validator!(v);
    if (_hasError) return errorText;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final bool isMultiline = (maxLines == null || maxLines! > 1);
    final bool hasError = _hasError;

    final Color fillColor = hasError
        ? aliases.specificInputMajor
        : enabled
        ? aliases.bgLayer1
        : aliases.bgLayer1.withValues(alpha: 0.5);

    final Widget? labelWidget = label == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: DswTokens.spaceXs),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: DswTokens.fontSizeXxs12,
                height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
                color: aliases.labelSecondary,
                fontFamily: 'SF Pro',
                fontFamilyFallback: DswTokens.fontFamilyFallback,
              ),
            ),
          );

    // Wrap decoration mirrors .wrap in Input.module.css:
    // inline-flex gap 6, h32/h36, pad 0 8, border 1 L2, radius 8, bgLayer1.
    // Focus-within border stateBusinessPrimary, error stateErrorPrimary.
    final Widget field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      initialValue: controller == null ? initialValue : null,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      minLines: minLines,
      readOnly: readOnly,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      onTap: onTap,
      validator: _validate,
      autovalidateMode: hasError
          ? AutovalidateMode.always
          : AutovalidateMode.disabled,
      style:
          style ??
          TextStyle(
            fontSize: DswTokens.fontSizeS14,
            height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
            color: aliases.labelPrimary,
            fontFamily: 'SF Pro',
            fontFamilyFallback: DswTokens.fontFamilyFallback,
          ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle:
            hintStyle ??
            TextStyle(
              fontSize: DswTokens.fontSizeS14,
              height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
              color: aliases.labelCaption,
            ),
        filled: true,
        fillColor: fillColor,
        isDense: true,
        // Height handling: single-line uses fixed height via contentPadding
        // that centers 14/22 text within 36/32.
        contentPadding:
            contentPadding ??
            EdgeInsets.symmetric(
              horizontal: DswTokens.spaceSm,
              vertical: isMultiline
                  ? DswTokens.spaceSm
                  : (size == DsInputSize.small ? 5 : 7),
            ),
        prefixIcon: icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(
                  left: DswTokens.spaceSm,
                  right: DswTokens.inputGap,
                ),
                child: SizedBox(
                  width: DswTokens.iconSizeSm,
                  height: DswTokens.iconSizeSm,
                  child: Center(
                    child: IconTheme(
                      data: const IconThemeData(size: DswTokens.iconSizeSm),
                      child: IconTheme(
                        data: IconThemeData(
                          size: DswTokens.iconSizeSm,
                          color: aliases.labelTertiary,
                        ),
                        child: icon!,
                      ),
                    ),
                  ),
                ),
              ),
        prefixIconConstraints: icon == null
            ? null
            : const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: DswTokens.spaceSm),
                child: suffix,
              ),
        suffixIconConstraints: suffix == null
            ? null
            : const BoxConstraints(minWidth: 0, minHeight: 0),
        errorText: hasError ? errorText : null,
        errorStyle: TextStyle(
          fontSize: DswTokens.fontSizeXxs12,
          height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
          color: aliases.stateErrorPrimary,
        ),
        helperText: hasError ? null : helperText,
        helperStyle: TextStyle(
          fontSize: DswTokens.fontSizeXxs12,
          height: DswTokens.lineHeightXxs12 / DswTokens.fontSizeXxs12,
          color: aliases.labelTertiary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          borderSide: BorderSide(
            color: hasError ? aliases.stateErrorPrimary : aliases.borderL2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          borderSide: BorderSide(
            color: hasError ? aliases.stateErrorPrimary : aliases.borderL2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          borderSide: BorderSide(
            color: hasError
                ? aliases.stateErrorPrimary
                : aliases.stateBusinessPrimary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          borderSide: BorderSide(color: aliases.stateErrorPrimary),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          borderSide: BorderSide(color: aliases.stateErrorPrimary, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DswTokens.radiusMd),
          borderSide: BorderSide(color: aliases.borderL1),
        ),
      ),
    );

    final Widget constrained = isMultiline
        ? field
        : SizedBox(height: _height, child: field);

    if (labelWidget == null) return constrained;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[labelWidget, constrained],
    );
  }
}

/// Compact search-style input with fixed height 32 matching Input.module.css
/// `.wrap` geometry, for cases where [DsInput] multiline flexibility is not needed.
class DsSearchInput extends ConsumerWidget {
  const DsSearchInput({
    super.key,
    this.icon,
    this.hintText,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
  });

  final Widget? icon;
  final String? hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 32,
      child: DsInput(
        icon: icon,
        hintText: hintText,
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        enabled: enabled,
        autofocus: autofocus,
        maxLines: 1,
      ),
    );
  }
}
