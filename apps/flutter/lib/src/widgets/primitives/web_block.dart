import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/open_external.dart';
import '../../theme/app_theme.dart';
import 'block.dart';

/// Web fetch/search result block — Flutter port of `WebBlock.tsx` + `WebBlock.module.css`.
///
/// Shared geometry mirrors the block family: `radius 12`, surface
/// `markdownCodeBlock` without the consumer-owned `8 + L2` mismatch.
/// Sources list scrolls vertically in a capped height; `复制` is unified
/// via `BlockCopyButton`. Card's `sources` max-height 320 mirrors the web
/// `320px` cap; whole citation list is scrolled in place rather than growing
/// unbounded.
class DsWebBlock extends ConsumerWidget {
  const DsWebBlock({
    super.key,
    required this.title,
    required this.url,
    required this.snippet,
  });

  /// Page title.
  final String title;

  /// Source URL.
  final String url;

  /// Text excerpt / summary.
  final String snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    return DsBlockFrame(
      aliases: aliases,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Floating copy control top-right — unified affordance
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
              child: BlockCopyButton(
                copyText: '$title\n$url\n$snippet',
                aliases: aliases,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DswTokens.spaceMd,
              DswTokens.spaceSm,
              DswTokens.spaceMd,
              DswTokens.spaceSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Builder(
                  builder: (context) {
                    final canOpen = isExternalHttpUrl(url);
                    final titleWidget = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title.isEmpty ? 'Untitled' : title,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeS14,
                              height:
                                  DswTokens.lineHeightS14 /
                                  DswTokens.fontSizeS14,
                              fontWeight: FontWeight.w600,
                              color: canOpen
                                  ? aliases.stateBusinessPrimary
                                  : aliases.labelPrimary,
                              fontFamily: 'SF Pro',
                              fontFamilyFallback: DswTokens.fontFamilyFallback,
                              decoration: canOpen
                                  ? TextDecoration.underline
                                  : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: DswTokens.spaceSm),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 14,
                          color: aliases.labelCaption,
                        ),
                      ],
                    );
                    return canOpen
                        ? InkWell(
                            onTap: () => openExternal(url),
                            borderRadius: BorderRadius.circular(
                              DswTokens.radiusSm,
                            ),
                            child: titleWidget,
                          )
                        : titleWidget;
                  },
                ),
                const SizedBox(height: DswTokens.spaceXs),
                Builder(
                  builder: (context) {
                    final canOpen = isExternalHttpUrl(url);
                    final urlRow = Row(
                      children: <Widget>[
                        Icon(
                          Icons.link_rounded,
                          size: 12,
                          color: aliases.labelCaption,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            url,
                            style: TextStyle(
                              fontSize: DswTokens.fontSizeXxs12,
                              height:
                                  DswTokens.lineHeightXxs12 /
                                  DswTokens.fontSizeXxs12,
                              fontFamily: DswTokens.fontFamilyCode,
                              fontFamilyFallback:
                                  DswTokens.fontFamilyCodeFallback,
                              color: canOpen
                                  ? aliases.stateBusinessPrimary
                                  : aliases.labelCaption,
                              decoration: canOpen
                                  ? TextDecoration.underline
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                    return canOpen
                        ? InkWell(
                            onTap: () => openExternal(url),
                            borderRadius: BorderRadius.circular(
                              DswTokens.radiusSm,
                            ),
                            child: urlRow,
                          )
                        : urlRow;
                  },
                ),
                if (snippet.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DswTokens.spaceSm),
                  Container(
                    padding: const EdgeInsets.all(DswTokens.spaceSm),
                    decoration: BoxDecoration(
                      color: aliases.bgOverlay,
                      borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                    ),
                    child: Text(
                      snippet,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXs13,
                        height:
                            DswTokens.lineHeightXs13 / DswTokens.fontSizeXs13,
                        color: aliases.labelSecondary,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
