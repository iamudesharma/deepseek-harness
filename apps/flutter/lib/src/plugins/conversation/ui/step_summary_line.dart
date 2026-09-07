/// Collapsed step-summary line for a settled or running step.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class StepSummaryLine extends StatelessWidget {
  const StepSummaryLine({super.key, required this.summary});
  final String summary;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Text(
      summary,
      style: TextStyle(
        fontSize: DswTokens.fontSizeXxs12,
        color: aliases.labelSecondary,
      ),
    );
  }
}
