import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'disclosure_row.dart';

/// Collapsible JSON tree — Flutter port of the web JSON preview.
///
/// Each object/array node is a [DisclosureRow]; leaves render inline
/// with type-tinted values via [DswTokens]. Pure build, recursive.
class DsJsonTree extends ConsumerWidget {
  const DsJsonTree({
    super.key,
    required this.data,
    this.initiallyExpanded = false,
  });

  /// JSON-compatible value: Map, List, String, num, bool, or null.
  final dynamic data;

  /// Whether composite nodes start expanded.
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return Container(
      decoration: BoxDecoration(
        color: aliases.markdownCodeBlock,
        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
        border: Border.all(color: aliases.borderL2),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(DswTokens.spaceSm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // DisclosureRow stretches to its Column's max width; left unbounded
        // under the horizontal viewport that is an infinite-width crash.
        // IntrinsicWidth pins the max to the tree's intrinsic width so rows
        // size naturally and wide trees still scroll instead of wrapping.
        child: IntrinsicWidth(
          child: _JsonNode(
            data: data,
            name: null,
            initiallyExpanded: initiallyExpanded,
            isRoot: true,
          ),
        ),
      ),
    );
  }
}

class _JsonNode extends StatefulWidget {
  const _JsonNode({
    required this.data,
    required this.name,
    required this.initiallyExpanded,
    this.isRoot = false,
  });

  final dynamic data;
  final String? name;
  final bool initiallyExpanded;
  final bool isRoot;

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool _open = widget.initiallyExpanded;

  bool get _isComposite => widget.data is Map || widget.data is List;

  int get _childCount {
    if (widget.data is Map) return (widget.data as Map).length;
    if (widget.data is List) return (widget.data as List).length;
    return 0;
  }

  String get _summary {
    if (widget.data is Map) {
      final int n = (widget.data as Map).length;
      return n == 0 ? '{}' : '{ $n }';
    }
    if (widget.data is List) {
      final int n = (widget.data as List).length;
      return n == 0 ? '[]' : '[ $n ]';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    // Leaf — render inline key: value
    if (!_isComposite) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.name != null) ...<Widget>[
              Text(
                '"${widget.name}"',
                style: TextStyle(
                  fontSize: DswTokens.markdownCodeBlockSmallSize,
                  fontFamily: DswTokens.fontFamilyCode,
                  fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                  color: aliases.stateBusinessPrimary,
                ),
              ),
              Text(
                ': ',
                style: TextStyle(
                  fontSize: DswTokens.markdownCodeBlockSmallSize,
                  fontFamily: DswTokens.fontFamilyCode,
                  fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                  color: aliases.labelTertiary,
                ),
              ),
            ],
            _valueText(widget.data, aliases),
            if (!widget.isRoot)
              Text(
                ',',
                style: TextStyle(
                  fontSize: DswTokens.markdownCodeBlockSmallSize,
                  color: aliases.labelTertiary,
                ),
              ),
          ],
        ),
      );
    }

    // Empty composite inline
    if (_childCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.name != null) ...<Widget>[
              Text(
                '"${widget.name}"',
                style: TextStyle(
                  fontSize: DswTokens.markdownCodeBlockSmallSize,
                  fontFamily: DswTokens.fontFamilyCode,
                  fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                  color: aliases.stateBusinessPrimary,
                ),
              ),
              Text(
                ': ',
                style: TextStyle(
                  fontSize: DswTokens.markdownCodeBlockSmallSize,
                  color: aliases.labelTertiary,
                ),
              ),
            ],
            Text(
              _summary,
              style: TextStyle(
                fontSize: DswTokens.markdownCodeBlockSmallSize,
                fontFamily: DswTokens.fontFamilyCode,
                fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
                color: aliases.labelTertiary,
              ),
            ),
          ],
        ),
      );
    }

    // Composite with DisclosureRow
    final String title = widget.name == null
        ? (widget.data is List ? 'Array $_summary' : 'Object $_summary')
        : '"${widget.name}"  $_summary';

    return DisclosureRow(
      icon: Icon(
        widget.data is List ? Icons.data_array : Icons.data_object,
        size: 12,
      ),
      title: title,
      open: _open,
      expandable: true,
      onToggle: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.only(left: DswTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.data is Map)
              for (final MapEntry<dynamic, dynamic> e
                  in (widget.data as Map).entries)
                _JsonNode(
                  data: e.value,
                  name: e.key.toString(),
                  initiallyExpanded: widget.initiallyExpanded,
                ),
            if (widget.data is List)
              for (int idx = 0; idx < (widget.data as List).length; idx++)
                _JsonNode(
                  data: (widget.data as List)[idx],
                  name: '[$idx]',
                  initiallyExpanded: widget.initiallyExpanded,
                ),
          ],
        ),
      ),
    );
  }

  Widget _valueText(dynamic v, DswAliases aliases) {
    late final String text;
    late final Color color;
    if (v == null) {
      text = 'null';
      color = aliases.labelCaption;
    } else if (v is String) {
      text = '"$v"';
      color = aliases.stateSuccessPrimary;
    } else if (v is num) {
      text = v.toString();
      color = aliases.stateWarnLabel;
    } else if (v is bool) {
      text = v.toString();
      color = DswTokens.deepseek500;
    } else {
      text = v.toString();
      color = aliases.labelPrimary;
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: DswTokens.markdownCodeBlockSmallSize,
        fontFamily: DswTokens.fontFamilyCode,
        fontFamilyFallback: DswTokens.fontFamilyCodeFallback,
        color: color,
      ),
    );
  }
}
