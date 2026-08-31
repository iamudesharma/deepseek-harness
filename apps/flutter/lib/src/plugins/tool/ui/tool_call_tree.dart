import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/disclosure_row.dart';
import '../tool_models.dart';

/// Tool call tree — one [DisclosureRow] per tool call, supporting Generic,
/// Read, Diff, Search, Bash tool cards. Use [toolCallsProvider] family keyed
/// by session id string.
///
/// Keeps simple but functional; handles loading / error / empty states via
/// AsyncValue. Each row is expandable when args or result is non-empty.
/// Cards are pure builds with [DswTokens] styling.
class ToolCallTree extends ConsumerWidget {
  /// Creates the tool call tree.
  const ToolCallTree({super.key, required this.sessionId});

  /// Session id (raw string).
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ToolCall> live = ref.watch(liveToolCallsProvider(sessionId));
    final AsyncValue<List<ToolCall>> async = ref.watch(
      toolCallsProvider(sessionId),
    );
    final List<ToolCall> calls = live.isNotEmpty
        ? live
        : (async.valueOrNull ?? const <ToolCall>[]);
    if (calls.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: calls.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: Theme.of(context).dividerColor),
          itemBuilder: (BuildContext context, int index) {
            final ToolCall call = calls[index];
            return _ToolCallRow(call: call);
          },
        ),
      );
    }
    // Fallback to async loading/error when live is empty and async is still loading/error
    return async.when(
      data: (List<ToolCall> _) => const SizedBox.shrink(),
      loading: () => const Padding(
        padding: EdgeInsets.all(DswTokens.spaceLg),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (Object err, StackTrace st) =>
          _ToolErrorState(error: err.toString()),
    );
  }
}

class _ToolCallRow extends ConsumerStatefulWidget {
  const _ToolCallRow({required this.call});

  final ToolCall call;

  @override
  ConsumerState<_ToolCallRow> createState() => _ToolCallRowState();
}

class _ToolCallRowState extends ConsumerState<_ToolCallRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final bool expandable =
        widget.call.args.isNotEmpty || widget.call.result != null;
    final String title =
        '${widget.call.toolName} · ${_statusLabel(widget.call.status)}';

    return DisclosureRow(
      icon: _iconForKind(widget.call.kind, aliases),
      title: title,
      open: _open,
      expandable: expandable,
      onToggle: () => setState(() => _open = !_open),
      expandOnRowClick: true,
      collapsedContent: Text(
        _collapsedPreview(widget.call),
        style: TextStyle(
          fontSize: DswTokens.fontSizeXxs12,
          color: aliases.labelCaption,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DswTokens.spaceLg,
          DswTokens.spaceSm,
          DswTokens.spaceLg,
          DswTokens.spaceMd,
        ),
        child: _ToolCard(call: widget.call),
      ),
    );
  }

  String _statusLabel(ToolCallStatus s) => switch (s) {
    ToolCallStatus.pending => 'pending',
    ToolCallStatus.running => 'running',
    ToolCallStatus.success => 'done',
    ToolCallStatus.error => 'error',
    ToolCallStatus.cancelled => 'not executed',
  };

  String _collapsedPreview(ToolCall call) {
    final dynamic args = call.args;
    if (args is Map && args.isNotEmpty) {
      final String? path =
          args['path'] as String? ??
          args['file'] as String? ??
          args['command'] as String?;
      if (path != null) return path;
      return args.keys.first.toString();
    }
    return call.kind.name;
  }

  Widget _iconForKind(ToolCallKind kind, DswAliases aliases) {
    final IconData data = switch (kind) {
      ToolCallKind.read => Icons.article_outlined,
      ToolCallKind.diff => Icons.difference_outlined,
      ToolCallKind.search => Icons.search,
      ToolCallKind.bash => Icons.terminal,
      ToolCallKind.generic => Icons.build_outlined,
    };
    return Icon(data, size: 16, color: aliases.labelTertiary);
  }
}

/// Card dispatcher — switch on discriminant tag, assertNever for closed union.
class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.call});

  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    return switch (call.kind) {
      ToolCallKind.generic => GenericToolCard(call: call),
      ToolCallKind.read => ReadToolCard(call: call),
      ToolCallKind.diff => DiffToolCard(call: call),
      ToolCallKind.search => SearchToolCard(call: call),
      ToolCallKind.bash => BashToolCard(call: call),
    };
  }
}

/// Generic tool card — shows args and result as pretty text.
class GenericToolCard extends StatelessWidget {
  /// Creates a generic tool card.
  const GenericToolCard({super.key, required this.call});

  /// Tool call.
  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      children: <Widget>[
        _JsonBlock(label: 'Args', value: call.args),
        if (call.result != null)
          _JsonBlock(label: 'Result', value: call.result),
        if (call.view != null) _JsonBlock(label: 'View', value: call.view!),
      ],
    );
  }
}

/// Read tool card — path + content preview.
class ReadToolCard extends StatelessWidget {
  /// Creates a read tool card.
  const ReadToolCard({super.key, required this.call});

  /// Tool call.
  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    final String? path =
        call.args['path'] as String? ?? call.args['file'] as String?;
    final String content = _stringify(call.result);
    return _CardShell(
      children: <Widget>[
        if (path != null) _KVRow(keyLabel: 'Path', value: path),
        if (content.isNotEmpty) _CodeBlock(code: content, maxLines: 20),
        if (content.isEmpty) _JsonBlock(label: 'Args', value: call.args),
      ],
    );
  }
}

/// Diff tool card — before/after or patch preview.
class DiffToolCard extends StatelessWidget {
  /// Creates a diff tool card.
  const DiffToolCard({super.key, required this.call});

  /// Tool call.
  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String? path =
        call.args['path'] as String? ?? call.args['file'] as String?;
    final String patch = _stringify(
      call.result ?? call.args['patch'] ?? call.args['content'] ?? '',
    );
    return _CardShell(
      children: <Widget>[
        if (path != null) _KVRow(keyLabel: 'File', value: path),
        if (patch.isNotEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: aliases.markdownCodeBlock,
              borderRadius: BorderRadius.circular(DswTokens.radiusSm),
              border: Border.all(color: aliases.borderL2),
            ),
            padding: const EdgeInsets.all(DswTokens.spaceSm),
            child: SelectableText(
              patch,
              style: TextStyle(
                fontSize: DswTokens.markdownCodeBlockSmallSize,
                height:
                    DswTokens.markdownCodeBlockSmallLineHeight /
                    DswTokens.markdownCodeBlockSmallSize,
                color: aliases.labelPrimary,
                fontFamily: 'SF Mono',
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
              ),
            ),
          )
        else
          _JsonBlock(label: 'Args', value: call.args),
      ],
    );
  }
}

/// Search tool card — query + matches.
class SearchToolCard extends StatelessWidget {
  /// Creates a search tool card.
  const SearchToolCard({super.key, required this.call});

  /// Tool call.
  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    final String? query =
        call.args['pattern'] as String? ??
        call.args['query'] as String? ??
        call.args['text'] as String?;
    final String result = _stringify(call.result);
    return _CardShell(
      children: <Widget>[
        if (query != null) _KVRow(keyLabel: 'Query', value: query),
        if (call.args['path'] case final String p?)
          _KVRow(keyLabel: 'Path', value: p),
        if (result.isNotEmpty)
          _CodeBlock(code: result, maxLines: 30)
        else
          _JsonBlock(label: 'Args', value: call.args),
      ],
    );
  }
}

/// Bash tool card — command + stdout/stderr.
class BashToolCard extends StatelessWidget {
  /// Creates a bash tool card.
  const BashToolCard({super.key, required this.call});

  /// Tool call.
  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String? command =
        call.args['command'] as String? ?? call.args['cmd'] as String?;
    final String result = _stringify(call.result);
    return _CardShell(
      children: <Widget>[
        if (command != null)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: aliases.markdownCodeBlockBanner,
              borderRadius: BorderRadius.circular(DswTokens.radiusSm),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: DswTokens.spaceSm,
              vertical: 6,
            ),
            child: SelectableText(
              '\$ $command',
              style: TextStyle(
                fontSize: DswTokens.markdownCodeSize,
                color: aliases.labelPrimary,
                fontFamily: 'SF Mono',
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
              ),
            ),
          ),
        if (result.isNotEmpty)
          _CodeBlock(code: result, maxLines: 40)
        else if (command == null)
          _JsonBlock(label: 'Args', value: call.args),
      ],
    );
  }
}

/// Web tool card — fetch URL or search query + retrieval preview.
class WebToolCard extends StatelessWidget {
  const WebToolCard({super.key, required this.call});
  final ToolCall call;
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String? url =
        call.args['url'] as String? ??
        call.args['query'] as String? ??
        call.args['q'] as String?;
    final String result = _stringify(call.result);
    // Title discriminates by toolName: fetch vs search.
    final String title = call.toolName == 'web_fetch' ? 'Fetch' : 'Search';
    return _CardShell(
      children: <Widget>[
        if (url != null) _KVRow(keyLabel: title, value: url),
        if (result.isNotEmpty)
          _CodeBlock(code: result, maxLines: 30)
        else if (url == null)
          _JsonBlock(label: 'Args', value: call.args),
        if (result.isEmpty && url != null)
          Text(
            'No results yet',
            style: TextStyle(
              fontSize: 11,
              color: aliases.labelCaption,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

/// Todo tool card — completed count + active items summary.
class TodoToolCard extends StatelessWidget {
  const TodoToolCard({super.key, required this.call});
  final ToolCall call;
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final todos = call.args['todos'];
    int done = 0, total = 0;
    String? active;
    int extra = 0;
    if (todos is List) {
      total = todos.length;
      for (final t in todos) {
        if (t is Map && t['status'] == 'completed') done++;
      }
      final activeItems = todos
          .where((t) => t is Map && t['status'] != 'completed')
          .toList();
      if (activeItems.isNotEmpty) {
        final first = activeItems.first;
        if (first is Map)
          active = first['content'] as String? ?? first['text'] as String?;
        if (activeItems.length > 1) extra = activeItems.length - 1;
      }
    }
    final String summary = todos is List
        ? '$done/$total completed'
        : 'Todo update';
    final String? extraText = extra > 0 ? '+$extra' : null;
    return _CardShell(
      children: <Widget>[
        Row(
          children: [
            Icon(
              Icons.checklist_rounded,
              size: 14,
              color: aliases.labelTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              summary,
              style: TextStyle(fontSize: 12, color: aliases.labelSecondary),
            ),
            if (extraText != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: aliases.bgLayer2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: aliases.borderL2),
                ),
                child: Text(
                  extraText,
                  style: TextStyle(fontSize: 10, color: aliases.labelCaption),
                ),
              ),
            ],
          ],
        ),
        if (active != null)
          Text(
            active,
            style: TextStyle(
              fontSize: 11,
              color: aliases.labelTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        if (call.result != null && _stringify(call.result).isNotEmpty)
          _CodeBlock(code: _stringify(call.result), maxLines: 20)
        else if (todos is! List)
          _JsonBlock(label: 'Args', value: call.args),
      ],
    );
  }
}

/// Ask question tool card — waiting / answered / cancelled summary.
class AskQuestionToolCard extends StatelessWidget {
  const AskQuestionToolCard({super.key, required this.call});
  final ToolCall call;
  @override
  Widget build(BuildContext context) {
    final DswAliases aliases =
        Theme.of(context).extension<DswThemeExtension>()?.aliases ??
        (Theme.of(context).brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final dynamic result = call.result;
    String summary;
    if (call.status == ToolCallStatus.running) {
      summary = 'Waiting for answer…';
    } else if (call.status == ToolCallStatus.error) {
      final text = result?.toString() ?? '';
      if (text.contains('ASK_CANCELLED')) {
        summary = 'Cancelled';
      } else if (text.contains('ASK_ABORTED')) {
        summary = 'Interrupted';
      } else {
        summary = 'Failed';
      }
    } else {
      // Try to parse answered count from result JSON.
      summary = 'Answered';
      if (result is String) {
        try {
          // Very small JSON check: look for answers array.
          final reg = RegExp(r'"answers"\s*:\s*\[');
          if (reg.hasMatch(result)) {
            final count = RegExp(r'"selected"\s*:').allMatches(result).length;
            summary = 'Answered $count';
          }
        } catch (_) {}
      } else if (result is Map && result['answers'] is List) {
        final total = (result['answers'] as List).length;
        summary = 'Answered $total';
      }
    }
    final String questionPreview = () {
      final qs = call.args['questions'];
      if (qs is List && qs.isNotEmpty) {
        final first = qs.first;
        if (first is Map)
          return first['question'] as String? ?? first['text'] as String? ?? '';
        if (first is String) return first;
      }
      final q = call.args['question'] as String?;
      return q ?? '';
    }();
    return _CardShell(
      children: <Widget>[
        Row(
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 14,
              color: aliases.labelTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              summary,
              style: TextStyle(fontSize: 12, color: aliases.labelSecondary),
            ),
          ],
        ),
        if (questionPreview.isNotEmpty)
          Text(
            questionPreview,
            style: TextStyle(fontSize: 11, color: aliases.labelTertiary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (result != null && call.status != ToolCallStatus.running)
          _CodeBlock(code: _stringify(result), maxLines: 20),
      ],
    );
  }
}

// Shared card primitives (no literal Colors).

class _CardShell extends StatelessWidget {
  const _CardShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          children[i],
          if (i != children.length - 1)
            const SizedBox(height: DswTokens.spaceSm),
        ],
      ],
    );
  }
}

class _KVRow extends StatelessWidget {
  const _KVRow({required this.keyLabel, required this.value});

  final String keyLabel;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$keyLabel: ',
          style: TextStyle(
            fontSize: 12,
            color: aliases.labelTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(fontSize: 12, color: aliases.labelSecondary),
          ),
        ),
      ],
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final String text = _stringify(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: aliases.labelTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _CodeBlock(code: text, maxLines: 24),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, this.maxLines = 40});

  final String code;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final List<String> lines = code.split('\n');
    final bool truncated = lines.length > maxLines;
    final String display = truncated
        ? '${lines.take(maxLines).join('\n')}\n… (${lines.length - maxLines} more lines)'
        : code;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        borderRadius: BorderRadius.circular(DswTokens.radiusSm),
        border: Border.all(color: aliases.borderL2),
      ),
      padding: const EdgeInsets.all(DswTokens.spaceSm),
      child: SelectableText(
        display,
        style: TextStyle(
          fontSize: DswTokens.markdownCodeBlockSmallSize,
          height:
              DswTokens.markdownCodeBlockSmallLineHeight /
              DswTokens.markdownCodeBlockSmallSize,
          color: aliases.labelPrimary,
          fontFamily: 'SF Mono',
          fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
        ),
      ),
    );
  }
}

String _stringify(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is Map || v is List) {
    try {
      // Simple pretty-ish fallback.
      return v.toString();
    } catch (_) {
      return '$v';
    }
  }
  return '$v';
}

class _ToolErrorState extends StatelessWidget {
  const _ToolErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return Padding(
      padding: const EdgeInsets.all(DswTokens.spaceLg),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, size: 16, color: aliases.stateErrorPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(fontSize: 12, color: aliases.stateErrorPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
