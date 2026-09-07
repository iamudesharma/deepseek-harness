import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Full-viewport drop invitation shown while a file drag is over the page —
/// Flutter port of `packages/client/ui-attachment/src/DropOverlay.tsx`.
///
/// Decoration only: [IgnorePointer] keeps pointer and drag targeting on the
/// page below so the owning scope's enter/leave count stays accurate.
///
/// @param disabled - drops are currently refused; renders the blocked
/// illustration and drops the limits line.
class DropOverlay extends StatelessWidget {
  /// Creates the overlay.
  const DropOverlay({
    super.key,
    required this.disabled,
    this.limitsText,
    this.title = 'Drop images to attach',
    this.disabledTitle = 'Image uploads are unavailable right now',
  });

  /// Whether drops are refused (locked / machine busy / no intake).
  final bool disabled;

  /// Display-ready limits line; shown only while drops are accepted.
  final String? limitsText;

  /// Headline inviting the drop.
  final String title;

  /// Headline naming why drops are unavailable.
  final String disabledTitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: Container(
          // Mask scrim over the page while the drag is active.
          color: aliases.bgOverlay.withValues(alpha: 0.72),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _DropIllustration(disabled: disabled, aliases: aliases),
              const SizedBox(height: DswTokens.spaceMd),
              Text(
                disabled ? disabledTitle : title,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeBase16,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelPrimary,
                ),
              ),
              if (!disabled && limitsText != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  limitsText!,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    color: aliases.labelSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tilted photo cards — simplified vector port of React's upload
/// illustrations (token-colored; greyed pair with a blocked badge when
/// disabled).
class _DropIllustration extends StatelessWidget {
  const _DropIllustration({required this.disabled, required this.aliases});

  final bool disabled;
  final DswAliases aliases;

  @override
  Widget build(BuildContext context) {
    final Color cardA = disabled
        ? aliases.labelTertiary
        : const Color(0xFF9CE5ED);
    final Color cardB = disabled
        ? aliases.labelTertiary
        : const Color(0xFF679EFE);
    final Color cardC = disabled
        ? aliases.stateWarnPrimary
        : const Color(0xFF3964FE);
    return SizedBox(
      width: 115,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 2,
            top: 14,
            child: Transform.rotate(angle: -0.397, child: _card(44, 44, cardA)),
          ),
          Positioned(
            right: 2,
            top: 8,
            child: Transform.rotate(angle: 0.304, child: _card(44, 50, cardB)),
          ),
          Center(child: _card(45, 44, cardC)),
          if (disabled)
            Center(child: Icon(Icons.block, size: 28, color: aliases.bgLayer1))
          else
            Center(
              child: Icon(
                Icons.add_photo_alternate_outlined,
                size: 24,
                color: aliases.bgLayer1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(double w, double h, Color color) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(DswTokens.radiusLg),
    ),
  );
}
