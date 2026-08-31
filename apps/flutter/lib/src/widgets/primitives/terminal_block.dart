import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/clipboard.dart';
import '../../theme/app_theme.dart';

/// Output lines shown before the height cap collapses the middle — mirrors
/// `DEFAULT_TERMINAL_MAX_LINES` in TerminalBlock.tsx so both front ends cut
/// a long command's output at the same place.
const int defaultTerminalMaxLines = 16;

/// Head/tail window for a capped line list, mirroring `head-tail-cap.ts`.
class HeadTailWindow {
  const HeadTailWindow._({
    required this.hidden,
    required this.capped,
    required this.headLines,
    required this.tailLines,
  });

  /// Computes the window for [total] lines under [maxLines].
  factory HeadTailWindow.compute(int total, int maxLines, bool expanded) {
    final hidden = total - maxLines;
    final headLines = (maxLines / 2).ceil();
    return HeadTailWindow._(
      hidden: hidden,
      capped: hidden > 0 && !expanded,
      headLines: headLines,
      tailLines: maxLines - headLines,
    );
  }

  /// Lines hidden while collapsed.
  final int hidden;

  /// Whether the middle collapse applies right now.
  final bool capped;

  /// Visible leading lines.
  final int headLines;

  /// Visible trailing lines.
  final int tailLines;
}

/// Display copy for the terminal surface; owners pass localized labels.
/// Every field defaults to the built-in value, matching DEFAULT_LABELS.
@immutable
class DsTerminalBlockLabels {
  /// Creates labels; omitted fields keep the Chinese built-ins.
  const DsTerminalBlockLabels({
    this.signal = _defaultSignal,
    this.exitCode = _defaultExitCode,
    this.running = '运行中',
    this.failed = '失败',
    this.done = '完成',
    this.copy = '复制',
    this.copied = '已复制',
    this.noOutput = '无输出',
    this.collapseAria = '收起输出',
    this.collapse = '收起',
    this.expandAria = _defaultExpandAria,
    this.expand = _defaultExpand,
  });

  /// Status pill text for a signal-terminated command.
  final String Function(String signal) signal;

  /// Status pill text for a non-zero exit code.
  final String Function(int exitCode) exitCode;

  /// Run-state text while the command is still running.
  final String running;

  /// Run-state text for a signal or non-zero-exit settle.
  final String failed;

  /// Run-state text for a clean settle.
  final String done;

  /// Copy-button idle label.
  final String copy;

  /// Copy-button label during the post-copy confirmation window.
  final String copied;

  /// Placeholder when a settled command produced no visible output.
  final String noOutput;

  /// Collapse-toggle aria label while expanded.
  final String collapseAria;

  /// Collapse-toggle text while expanded.
  final String collapse;

  /// Expand-toggle aria label while capped, given the hidden count.
  final String Function(int hidden) expandAria;

  /// Expand-toggle text while capped, given the hidden count.
  final String Function(int hidden) expand;

  static String _defaultSignal(String signal) => '信号 $signal';
  static String _defaultExitCode(int code) => '退出码 $code';
  static String _defaultExpandAria(int hidden) => '展开 $hidden 行';
  static String _defaultExpand(int hidden) => '展开 $hidden 行';
}

/// Terminal surface for a shell command and its output — prompt line
/// (run-state dot + shortened cwd + command), plain-text output lines from
/// the ANSI-stripped content, settled status pill, copy control, and a
/// middle-collapse height cap. Mirrors `TerminalBlock.tsx` + `TerminalBlock.module.css`
/// geometry: `radius 12` on `markdownCodeBlock` with `borderL1` when hosted
/// inside a ToolRow's `ioCard` (outer card's hairline), else the block itself
/// owns `borderL1` so a standalone terminal still reads as one family with a
/// fenced block. Cap is `kBlockCap=16` with unified `ceil(16/2)` head-tail
/// slice and `… 其余 N 行` expander plus `复制` — the same `BlockHeadTailCap`
/// + `BlockCopyButton` every primitive shares.
class DsTerminalBlock extends ConsumerStatefulWidget {
  /// Creates a terminal block.
  const DsTerminalBlock({
    super.key,
    required this.command,
    this.cwd,
    this.home,
    this.output = '',
    this.exitCode,
    this.signal,
    this.running = false,
    this.maxLines = defaultTerminalMaxLines,
    this.labels = const DsTerminalBlockLabels(),
  });

  /// The command shown on the prompt line.
  final String command;

  /// Working directory for the prompt label; absent renders a plain `$`.
  final String? cwd;

  /// Absolute home directory, so cwd equal to it collapses to `~`.
  final String? home;

  /// The command's output text; may contain ANSI escape sequences.
  final String output;

  /// Settled exit code; non-zero renders the status pill.
  final int? exitCode;

  /// Terminating signal name; takes precedence over [exitCode].
  final String? signal;

  /// Still running: the block shows the prompt line alone.
  final bool running;

  /// Height cap in output lines before the middle collapses.
  final int maxLines;

  /// Localized display copy.
  final DsTerminalBlockLabels labels;

  static final RegExp _ansiRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  /// Prompt label: `~` for home, else the path's last segment.
  static String promptLabel(String? cwd, String? home) {
    if (cwd == null) return '\$';
    final trimmed = cwd.replaceAll(RegExp(r'[/\\]+$'), '');
    if (home != null && trimmed == home.replaceAll(RegExp(r'[/\\]+$'), ''))
      return '~';
    final segment = trimmed
        .split(RegExp(r'[/\\]'))
        .where((s) => s.isNotEmpty)
        .toList();
    return segment.isEmpty ? cwd : segment.last;
  }

  @override
  ConsumerState<DsTerminalBlock> createState() => _DsTerminalBlockState();
}

class _DsTerminalBlockState extends ConsumerState<DsTerminalBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // Output lines, ANSI-stripped (color rendering is a recorded gap).
    final rawLines = widget.output.isEmpty
        ? const <String>[]
        : widget.output.replaceAll(DsTerminalBlock._ansiRegex, '').split('\n');
    while (rawLines.isNotEmpty && rawLines.last.trim().isEmpty) {
      rawLines.removeLast();
    }

    final window = HeadTailWindow.compute(
      rawLines.length,
      widget.maxLines,
      _expanded,
    );
    final visible = window.capped
        ? [
            ...rawLines.take(window.headLines),
            ...rawLines.sublist(rawLines.length - window.tailLines),
          ]
        : rawLines;

    // Run state precedence: signal > exitCode > running/done.
    final String? pillText;
    if (widget.signal != null) {
      pillText = widget.labels.signal(widget.signal!);
    } else if (widget.exitCode != null && widget.exitCode != 0) {
      pillText = widget.labels.exitCode(widget.exitCode!);
    } else {
      pillText = null;
    }
    final runState = widget.running
        ? widget.labels.running
        : pillText != null
        ? widget.labels.failed
        : widget.labels.done;

    return Container(
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        border: Border.all(color: aliases.borderL1),
        borderRadius: BorderRadius.circular(DswTokens.radiusLg),
      ),
      padding: const EdgeInsets.all(12),
      child: DefaultTextStyle(
        style: TextStyle(
          color: aliases.labelPrimary,
          fontSize: DswTokens.markdownCodeBlockSmallSize,
          height:
              DswTokens.markdownCodeBlockSmallLineHeight /
              DswTokens.markdownCodeBlockSmallSize,
          fontFamily: 'SF Mono',
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RunDot(done: !widget.running && pillText == null),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${DsTerminalBlock.promptLabel(widget.cwd, widget.home)} \$ ${widget.command}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!widget.running)
              switch (visible.isEmpty) {
                true => Text(widget.labels.noOutput),
                false => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in visible)
                              Text(line, overflow: TextOverflow.clip),
                          ],
                        ),
                      ),
                    ),
                    if (window.hidden > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Text(
                            _expanded
                                ? widget.labels.collapse
                                : widget.labels.expand(window.hidden),
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              color: aliases.labelTertiary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              },
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  pillText ?? runState,
                  style: TextStyle(
                    color: aliases.labelTertiary,
                    fontSize: DswTokens.fontSizeXxs12,
                  ),
                ),
                if (!widget.running) ...[
                  const Spacer(),
                  _CopyControl(output: widget.output, labels: widget.labels),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RunDot extends StatelessWidget {
  const _RunDot({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final Color color = done
        ? aliases.stateSuccessPrimary
        : aliases.stateWarnPrimary;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _CopyControl extends StatefulWidget {
  const _CopyControl({required this.output, required this.labels});

  final String output;
  final DsTerminalBlockLabels labels;

  @override
  State<_CopyControl> createState() => _CopyControlState();
}

class _CopyControlState extends State<_CopyControl> {
  bool _copiedRecently = false;

  Future<void> _copy() async {
    await ClipboardHelper.copy(widget.output);
    if (!mounted) return;
    setState(() => _copiedRecently = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copiedRecently = false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return InkWell(
      onTap: _copy,
      child: Text(
        _copiedRecently ? widget.labels.copied : widget.labels.copy,
        style: TextStyle(
          fontSize: DswTokens.fontSizeXxs12,
          color: aliases.labelTertiary,
        ),
      ),
    );
  }
}
