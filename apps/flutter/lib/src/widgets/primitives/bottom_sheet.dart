import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'ds_button.dart';

/// Bottom sheet that mirrors web [Modal] on mobile.
///
/// Uses [showModalBottomSheet] + [DraggableScrollableSheet] with same
/// [bgMask], radius 16 ([radiusXl]), [shadowLv3], handle bar, and close
/// on drag. Props: [title], [child], [footer].
///
/// Responsive usage: show [DsModal] on web/wide and [DsBottomSheet] on
/// mobile/narrow (via [isNarrow] or [showDsAdaptiveDialog]).
class DsBottomSheet extends ConsumerWidget {
  const DsBottomSheet({
    super.key,
    required this.title,
    this.description,
    this.child,
    this.footer,
    this.onClose,
  });

  /// Sheet heading — mirrors Modal title (16/24, w500).
  final String title;

  /// Optional supporting text under the title.
  final String? description;

  /// Body content (inputs, etc.).
  final Widget? child;

  /// Action row (e.g. Cancel / Delete).
  final Widget? footer;

  /// Called on drag dismiss, handle tap, or outside tap.
  final VoidCallback? onClose;

  /// Present this sheet modally.
  ///
  /// Mirrors `showModalBottomSheet` with [DraggableScrollableSheet],
  /// [bgMask1] barrier, radius 16, [shadowLv3], handle bar, and drag-to-close.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? description,
    Widget? child,
    Widget? footer,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: DswTokens.transparent,
      barrierColor: aliases.bgMask1,
      builder: (BuildContext ctx) => DsBottomSheet(
        title: title,
        description: description,
        onClose: () => Navigator.of(ctx).pop(),
        footer: footer,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // Draggable sheet that sizes to content but allows drag-to-dismiss.
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      expand: false,
      builder: (BuildContext ctx, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: aliases.bgLayer2,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(DswTokens.radiusXl),
            ),
            border: Border.all(color: aliases.borderInverted),
            boxShadow: DswTokens.shadowLv3,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Handle bar — 36x4, borderL2, 8px top padding
              Padding(
                padding: const EdgeInsets.only(
                  top: DswTokens.spaceSm,
                  bottom: DswTokens.spaceSm,
                ),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: aliases.borderL2,
                      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                    ),
                  ),
                ),
              ),
              // Header — title row with 24/14/12 padding mirroring Modal header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DswTokens.spaceXl,
                  DswTokens.spaceSm,
                  DswTokens.spaceXl,
                  DswTokens.spaceSm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeBase16,
                          height:
                              DswTokens.lineHeightBase16 /
                              DswTokens.fontSizeBase16,
                          fontWeight: FontWeight.w500,
                          color: aliases.labelPrimary,
                          fontFamily: 'SF Pro',
                          fontFamilyFallback: DswTokens.fontFamilyFallback,
                        ),
                      ),
                    ),
                    if (onClose != null)
                      InkWell(
                        onTap: onClose,
                        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.close,
                            size: DswTokens.iconSizeSm,
                            color: aliases.labelSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (description != null && description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DswTokens.spaceXl,
                    0,
                    DswTokens.spaceXl,
                    DswTokens.spaceMd,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      description!,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                        fontWeight: FontWeight.w400,
                        color: aliases.labelPrimary,
                      ),
                    ),
                  ),
                ),
              // Scrollable body
              Flexible(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    DswTokens.spaceXl,
                    0,
                    DswTokens.spaceXl,
                    DswTokens.spaceMd,
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DswTokens.spaceXl,
                    DswTokens.spaceSm,
                    DswTokens.spaceXl,
                    DswTokens.spaceXl,
                  ),
                  child: footer!,
                ),
              // Bottom safe-area inset
              SizedBox(height: MediaQuery.paddingOf(ctx).bottom),
            ],
          ),
        );
      },
    );
  }
}

/// Responsive helper: show [DsBottomSheet] on narrow (mobile) and [DsModal]
/// dialog on wide (web). Use for delete confirmation and similar dialogs.
///
/// When [isNarrowOverride] is null, uses [MediaQuery] width < 768.
Future<T?> showDsAdaptiveDialog<T>({
  required BuildContext context,
  required String title,
  String? description,
  Widget? child,
  Widget? footer,
  bool barrierDismissible = true,
}) async {
  final bool isNarrow = MediaQuery.sizeOf(context).width < 768;
  if (isNarrow) {
    return DsBottomSheet.show<T>(
      context: context,
      title: title,
      description: description,
      footer: footer,
      isDismissible: barrierDismissible,
      child: child,
    );
  }
  // Wide: use Dialog path via DsModal.show — import lazily to avoid cycle
  final ThemeData theme = Theme.of(context);
  final DswAliases aliases =
      theme.extension<DswThemeExtension>()?.aliases ??
      (theme.brightness == Brightness.dark
          ? DswTokens.darkAliases
          : DswTokens.lightAliases);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: aliases.bgMask1,
    builder: (BuildContext ctx) => Dialog(
      backgroundColor: DswTokens.transparent,
      insetPadding: const EdgeInsets.all(DswTokens.spaceXl),
      elevation: 0,
      child: Container(
        width: 380,
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: aliases.bgLayer2,
          borderRadius: BorderRadius.circular(DswTokens.radius2xl),
          border: Border.all(color: aliases.borderInverted),
          boxShadow: DswTokens.shadowLv3,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DswTokens.spaceXl,
                22,
                DswTokens.spaceSm + 6,
                DswTokens.spaceMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeBase16,
                            height:
                                DswTokens.lineHeightBase16 /
                                DswTokens.fontSizeBase16,
                            fontWeight: FontWeight.w500,
                            color: aliases.labelPrimary,
                            fontFamily: 'SF Pro',
                            fontFamilyFallback: DswTokens.fontFamilyFallback,
                          ),
                        ),
                      ),
                      const SizedBox(width: DswTokens.spaceSm),
                      InkWell(
                        onTap: () => Navigator.of(ctx).pop(),
                        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: aliases.labelSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (description != null &&
                      description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: DswTokens.spaceMd),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeS14,
                        height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                        color: aliases.labelPrimary,
                      ),
                    ),
                  ],
                  if (child != null) ...<Widget>[
                    const SizedBox(height: 20),
                    child,
                  ],
                ],
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DswTokens.spaceXl,
                  0,
                  DswTokens.spaceXl,
                  DswTokens.spaceXl,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[Flexible(child: footer)],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Convenience for delete confirmation — responsive sheet/modal.
Future<bool?> showDsDeleteConfirmation({
  required BuildContext context,
  required String title,
  String? description,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
}) {
  Widget footerBuilder(BuildContext ctx) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: <Widget>[
      DsButton(
        variant: DsButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(false),
        label: cancelLabel,
      ),
      const SizedBox(width: DswTokens.spaceSm),
      DsButton(
        variant: DsButtonVariant.primary,
        onPressed: () => Navigator.of(ctx).pop(true),
        label: confirmLabel,
      ),
    ],
  );

  final bool isNarrow = MediaQuery.sizeOf(context).width < 768;
  if (isNarrow) {
    return DsBottomSheet.show<bool>(
      context: context,
      title: title,
      description: description,
      footer: Builder(builder: footerBuilder),
      child: const SizedBox.shrink(),
    );
  }
  return showDsAdaptiveDialog<bool>(
    context: context,
    title: title,
    description: description,
    footer: Builder(builder: footerBuilder),
  );
}
