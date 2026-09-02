/// One plugin's card chrome — header + disclosure + save footer.
///
/// Mirrors `packages/client/ui-settings-plugins/src/client/PluginCard.tsx`:
/// stacked name over description, Unsaved pending badge, 14px chevron,
/// available===false → nothing, writable readOnly banner, saving/failed states,
/// collapse only after host-confirmed settlement.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../card_form.dart';

class PluginCard extends StatefulWidget {
  const PluginCard({
    super.key,
    required this.title,
    required this.description,
    required this.shell,
    required this.onSave,
    required this.onDiscard,
    required this.child,
    this.pendingLabel = 'Unsaved',
    this.readOnlyLabel = 'This deployment stores settings read-only.',
    this.saveLabel = 'Save',
    this.savingLabel = 'Saving…',
    this.discardLabel = 'Discard',
    this.saveFailedLabel =
        'The deployment did not accept these values; they were left for you to correct.',
    this.expandLabel = 'Show settings',
    this.collapseLabel = 'Hide settings',
  });

  final String title;
  final String description;
  final CardShell shell;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final Widget child;

  final String pendingLabel;
  final String readOnlyLabel;
  final String saveLabel;
  final String savingLabel;
  final String discardLabel;
  final String saveFailedLabel;
  final String expandLabel;
  final String collapseLabel;

  @override
  State<PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<PluginCard> {
  bool _open = false;
  bool _saveStarted = false;

  @override
  void didUpdateWidget(covariant PluginCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final CardShell s = widget.shell;
    if (s.saving) {
      _saveStarted = true;
      return;
    }
    if (!_saveStarted) return;
    _saveStarted = false;
    if (!s.dirty && !s.failed) {
      setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CardShell shell = widget.shell;
    if (!shell.available) return const SizedBox.shrink();

    final DswAliases aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
            (Theme.of(context).brightness == Brightness.dark
                ? DswTokens.darkAliases
                : DswTokens.lightAliases);

    final bool blocked = !shell.dirty || shell.invalid || shell.saving;

    return Container(
      decoration: BoxDecoration(
        color: aliases.bgLayer2,
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
        border: Border.all(color: aliases.borderL2),
        boxShadow: DswTokens.shadowLv1,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(DswTokens.radiusLg),
            hoverColor: aliases.interactiveBgHover,
            child: Semantics(
              button: true,
              label: '${_open ? widget.collapseLabel : widget.expandLabel}: ${widget.title}',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DswTokens.spaceLg,
                  vertical: DswTokens.spaceMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              fontWeight: FontWeight.w600,
                              color: aliases.labelPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.description,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              color: aliases.labelSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (shell.dirty) ...[
                      const SizedBox(width: DswTokens.spaceSm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: aliases.bgOverlay,
                          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                        ),
                        child: Text(
                          widget.pendingLabel,
                          style: TextStyle(fontSize: 11, color: aliases.labelTertiary),
                        ),
                      ),
                    ],
                    const SizedBox(width: DswTokens.spaceSm),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: DswTokens.transitionDurationFast,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: aliases.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: aliases.borderL1)),
              ),
              padding: const EdgeInsets.all(DswTokens.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!shell.writable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DswTokens.spaceMd),
                      child: Text(
                        widget.readOnlyLabel,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.stateWarnLabel,
                        ),
                      ),
                    ),
                  widget.child,
                  if (shell.failed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DswTokens.spaceSm),
                      child: Text(
                        widget.saveFailedLabel,
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.stateErrorPrimary,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: (!shell.dirty || shell.saving) ? null : widget.onDiscard,
                        child: Text(widget.discardLabel),
                      ),
                      const SizedBox(width: DswTokens.spaceSm),
                      FilledButton(
                        onPressed: blocked ? null : widget.onSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: aliases.buttonPrimaryFill,
                          foregroundColor: aliases.labelPrimaryForeground,
                          disabledBackgroundColor: aliases.buttonPrimaryDimmed,
                        ),
                        child: Text(shell.saving ? widget.savingLabel : widget.saveLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
