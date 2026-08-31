import 'package:flutter/material.dart';

/// Icon set for dsh Flutter primitives — Flutter port of `ui-primitives/src/icons`.
///
/// Every glyph uses `currentColor` via [Icon] color inheritance. Sizes default
/// to the glyph's drawn size. Pure build, no `ctx`.
class DsIcons {
  const DsIcons._();

  static Widget check({double size = 16, Color? color}) =>
      Icon(Icons.check, size: size, color: color);

  static Widget close({double size = 16, Color? color}) =>
      Icon(Icons.close, size: size, color: color);

  static Widget warning({double size = 16, Color? color}) =>
      Icon(Icons.warning_amber_rounded, size: size, color: color);

  static Widget chevronRight({double size = 14, Color? color}) =>
      Icon(Icons.chevron_right, size: size, color: color);

  static Widget chevronDown({double size = 14, Color? color}) =>
      Icon(Icons.expand_more, size: size, color: color);

  static Widget chevronUp({double size = 14, Color? color}) =>
      Icon(Icons.expand_less, size: size, color: color);

  static Widget plus({double size = 16, Color? color}) =>
      Icon(Icons.add, size: size, color: color);

  static Widget search({double size = 16, Color? color}) =>
      Icon(Icons.search, size: size, color: color);

  static Widget settings({double size = 14, Color? color}) =>
      Icon(Icons.settings_outlined, size: size, color: color);

  static Widget copy({double size = 16, Color? color}) =>
      Icon(Icons.copy_outlined, size: size, color: color);

  static Widget share({double size = 16, Color? color}) =>
      Icon(Icons.share_outlined, size: size, color: color);

  static Widget ellipsis({double size = 16, Color? color}) =>
      Icon(Icons.more_horiz, size: size, color: color);

  static Widget globe({double size = 14, Color? color}) =>
      Icon(Icons.language, size: size, color: color);

  static Widget branch({double size = 16, Color? color}) =>
      Icon(Icons.account_tree_outlined, size: size, color: color);

  static Widget refresh({double size = 16, Color? color}) =>
      Icon(Icons.refresh, size: size, color: color);

  static Widget info({double size = 16, Color? color}) =>
      Icon(Icons.info_outline, size: size, color: color);

  static Widget error({double size = 16, Color? color}) =>
      Icon(Icons.error_outline, size: size, color: color);

  static Widget success({double size = 16, Color? color}) =>
      Icon(Icons.check_circle_outline, size: size, color: color);
}

/// Convenience extension to wrap an [IconData] as a 16px [Icon] widget.
extension DsIconDataExtension on IconData {
  Widget toDsIcon({double size = 16, Color? color}) =>
      Icon(this, size: size, color: color);
}
