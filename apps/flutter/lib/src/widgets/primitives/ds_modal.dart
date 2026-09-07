import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';

/// Token-styled modal — Flutter port of `Modal.tsx` + `Modal.module.css`.
///
/// Overlay with blurred mask (`bgMask1` + blur), centered card (`bgLayer2`,
/// radius 24, `shadowLv3`). Dismiss on outside tap and Escape. Pure build,
/// no `ctx`; slot `child`/`footer` are Widget? params.
class DsModal extends ConsumerWidget {
  const DsModal({
    super.key,
    required this.title,
    this.description,
    this.closeLabel = 'Close',
    this.child,
    this.footer,
    this.onClose,
    this.barrierDismissible = true,
    this.width = 380,
    this.headless = false,
    this.contentPadding,
  });

  /// Dialog heading — used as `aria-label` / semantics.
  final String title;

  /// Optional supporting sentence under the title.
  final String? description;

  /// Accessible label for the close button.
  final String closeLabel;

  /// Body content.
  final Widget? child;

  /// Action row (e.g. Cancel / Create).
  final Widget? footer;

  /// Called on mask tap, close button, or Escape.
  final VoidCallback? onClose;

  /// Whether tapping the mask dismisses the modal.
  final bool barrierDismissible;

  /// Card width. Defaults to 380 matching web `min(380px, 100%)`.
  final double width;

  /// When true renders [child] directly without default header chrome.
  final bool headless;

  /// Optional padding override for the content region.
  final EdgeInsetsGeometry? contentPadding;

  /// Show this modal as a dialog. Mirrors web portal to `document.body`.
  ///
  /// Mask uses `bgMask1` + `blur(2px)` (`--dsw-mask-blur`). Escape closes.
  /// Returns the value passed to `Navigator.pop` inside the modal.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? description,
    String closeLabel = 'Close',
    Widget? child,
    Widget? footer,
    bool barrierDismissible = true,
    double width = 380,
    bool headless = false,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool reduced = prefersReducedMotion(context);

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: reduced
          ? Duration.zero
          : DswTokens.transitionDurationFast,
      pageBuilder:
          (BuildContext ctx, Animation<double> a1, Animation<double> a2) {
            return Stack(
              children: <Widget>[
                // Mask — bgMask1 + blur(2px) — mirrors `.mask { background: bgMask1; backdrop-filter: blur(2px) }`.
                Positioned.fill(
                  child: GestureDetector(
                    onTap: barrierDismissible
                        ? () => Navigator.of(ctx).pop()
                        : null,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                      child: Container(color: aliases.bgMask1),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DswTokens.spaceXl),
                    child: Material(
                      color: Colors.transparent,
                      child: CallbackShortcuts(
                        bindings: <ShortcutActivator, VoidCallback>{
                          const SingleActivator(
                            LogicalKeyboardKey.escape,
                          ): () => Navigator.of(ctx)
                              .maybePop(),
                        },
                        child: Focus(
                          autofocus: true,
                          child: DsModal(
                            title: title,
                            description: description,
                            closeLabel: closeLabel,
                            onClose: () => Navigator.of(ctx).pop(),
                            width: width,
                            headless: headless,
                            contentPadding: contentPadding,
                            footer: footer,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
      transitionBuilder:
          (
            BuildContext ctx,
            Animation<double> animation,
            Animation<double> secondary,
            Widget child,
          ) {
            if (reduced) return child;
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: DswTokens.easeInOut,
              ),
              child: child,
            );
          },
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

    // Dialog card — mirrors .dialog in Modal.module.css (width min(380,100%), confirmation 440).
    final Widget card = Container(
      width: width,
      constraints: BoxConstraints(maxWidth: width),
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radius2xl),
        border: Border.all(color: aliases.borderInverted),
        boxShadow: DswTokens.shadowLv3,
      ),
      clipBehavior: Clip.antiAlias,
      child: headless
          ? child
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding:
                      contentPadding ??
                      const EdgeInsets.fromLTRB(
                        DswTokens.spaceXl,
                        22,
                        DswTokens.spaceSm + 6, // 14px right to match web 14px
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
                                fontFamilyFallback:
                                    DswTokens.fontFamilyFallback,
                              ),
                              semanticsLabel: title,
                            ),
                          ),
                          const SizedBox(width: DswTokens.spaceSm),
                          InkWell(
                            onTap: onClose,
                            borderRadius: BorderRadius.circular(
                              DswTokens.radiusSm,
                            ),
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  DswTokens.radiusSm,
                                ),
                              ),
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
                          description!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: DswTokens.spaceMd),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          child: Text(
                            description!,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              height:
                                  DswTokens.lineHeightS14 /
                                  DswTokens.fontSizeS14,
                              fontWeight: FontWeight.w400,
                              color: aliases.labelPrimary,
                            ),
                          ),
                        ),
                      ],
                      if (child != null) ...<Widget>[
                        const SizedBox(height: 20),
                        child!,
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
                      children: <Widget>[Flexible(child: footer!)],
                    ),
                  ),
              ],
            ),
    );

    // Centered dialog — barrier handled by showDialog; direct build also
    // supports inline overlay with outside-tap dismiss.
    return Dialog(
      backgroundColor: DswTokens.transparent,
      insetPadding: const EdgeInsets.all(DswTokens.spaceXl),
      elevation: 0,
      child: card,
    );
  }
}

/// Inline overlay variant that includes its own mask and outside-tap handling
/// for controlled `open` usage (mirrors web `open` prop).
class DsModalOverlay extends ConsumerWidget {
  const DsModalOverlay({
    super.key,
    required this.open,
    required this.title,
    required this.onClose,
    this.description,
    this.closeLabel = 'Close',
    this.child,
    this.footer,
    this.width = 380,
    this.headless = false,
  });

  final bool open;
  final String title;
  final VoidCallback onClose;
  final String? description;
  final String closeLabel;
  final Widget? child;
  final Widget? footer;
  final double width;
  final bool headless;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!open) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): onClose,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: <Widget>[
            // Mask — bgMask1 + blur(2px) — mirrors `.mask { background: bgMask1; backdrop-filter: blur(2px) }`.
            Positioned.fill(
              child: GestureDetector(
                onTap: onClose,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                  child: Container(color: aliases.bgMask1),
                ),
              ),
            ),
            // Centered card
            Center(
              child: Padding(
                padding: const EdgeInsets.all(DswTokens.spaceXl),
                child: DsModal(
                  title: title,
                  description: description,
                  closeLabel: closeLabel,
                  onClose: onClose,
                  width: width,
                  headless: headless,
                  footer: footer,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
