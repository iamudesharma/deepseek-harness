import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'brandwordmark.dart';

/// Official brand lockup — wordmark + optional subtitle.
///
/// Mirrors web `BrandOfficial` bar (used in onboarding / header).
/// ConsumerWidget, Theme + DswTokens.
class BrandOfficial extends ConsumerWidget {
  const BrandOfficial({super.key, this.subtitle, this.size = 24});
  final String? subtitle;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DsBrandWordmark(size: size),
        if (subtitle != null) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
            width: 1,
            height: size * 0.6,
            color: aliases.borderL2,
          ),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: DswTokens.fontSizeXxs12,
              color: aliases.labelSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
