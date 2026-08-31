import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';

/// Agent session state indicator — Flutter port of `StateDot.tsx` +
/// `StateDot.module.css`.
///
/// Four states: done/warning/error are 10×10 halo (0.10 opacity) around a
/// 6×6 solid core. Ongoing is an 8-cell pixel chase on a 3×3 grid
/// (2px cells on a 10px canvas) animating clockwise.
enum StateDotState { done, warning, ongoing, error }

/// Outer 3×3 matrix cells (2px pixels on a 10px grid), clockwise from top-left.
/// Mirrors `MATRIX_CELLS` in StateDot.tsx.
const List<Offset> _kMatrixCells = <Offset>[
  Offset(0, 0),
  Offset(4, 0),
  Offset(8, 0),
  Offset(8, 4),
  Offset(8, 8),
  Offset(4, 8),
  Offset(0, 8),
  Offset(0, 4),
];

class StateDot extends ConsumerStatefulWidget {
  const StateDot({
    super.key,
    required this.state,
    this.size = 10,
    this.semanticLabel,
  });

  /// Which of the four states to show.
  final StateDotState state;

  /// Outer diameter in logical px. Defaults to 10 matching figma.
  final double size;

  /// Accessibility label for the dot. Dot is otherwise `aria-hidden`.
  final String? semanticLabel;

  @override
  ConsumerState<StateDot> createState() => _StateDotState();
}

class _StateDotState extends ConsumerState<StateDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.state == StateDotState.ongoing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant StateDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == StateDotState.ongoing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.state != StateDotState.ongoing &&
        _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final bool reduced = prefersReducedMotion(context);
    // Under reduced-motion the chase collapses to a static cell; stop the
    // repeating ticker so it no longer schedules frames.
    if (reduced && _controller.isAnimating) {
      _controller.stop();
    }

    final Widget dot = widget.state == StateDotState.ongoing
        ? _buildOngoing(theme, reduced: reduced)
        : _buildSolid(aliases);

    if (widget.semanticLabel != null) {
      return Semantics(label: widget.semanticLabel, child: dot);
    }
    return ExcludeSemantics(child: dot);
  }

  Widget _buildSolid(DswAliases aliases) {
    late final Color color;
    switch (widget.state) {
      case StateDotState.done:
        color = aliases.stateSuccessPrimary;
        break;
      case StateDotState.warning:
        color = aliases.stateWarnPrimary;
        break;
      case StateDotState.error:
        color = aliases.stateErrorPrimary;
        break;
      case StateDotState.ongoing:
        // Unreachable — handled above.
        color = DswTokens.deepseek450;
        break;
    }

    // halo via outer container opacity 0.1, core 6/10 = 60% inset 20%.
    // Mirrors .dot::before / ::after.
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: widget.size * 0.6,
            height: widget.size * 0.6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }

  Widget _buildOngoing(ThemeData theme, {required bool reduced}) {
    // Ongoing blue has no alias — component-level var pinned to static scale.
    const Color ongoingColor = DswTokens.deepseek450;

    if (reduced) {
      // Reduced-motion: the chase collapses to a static centered cell
      // (mirrors the React `prefers-reduced-motion` media-query override).
      final Widget staticDot = Container(
        width: widget.size * 0.6,
        height: widget.size * 0.6,
        decoration: BoxDecoration(color: ongoingColor, shape: BoxShape.circle),
      );
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(child: staticDot),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _MatrixPainter(
              progress: _controller.value,
              color: ongoingColor,
            ),
          );
        },
      ),
    );
  }
}

/// Paints the 8 outer 2×2 cells of a 10×10 grid, with stepped opacity chase.
///
/// Keyframe holds (no tweening) matching `dsh-state-dot-chase`:
/// 0–12.4% → 1.0, 12.5–24.9% → 0.6, 25–37.4% → 0.35, else → 0.15.
/// Per-cell phase offset via animationDelay index * -125ms (1s / 8).
class _MatrixPainter extends CustomPainter {
  _MatrixPainter({required this.progress, required this.color});

  final double progress; // 0..1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 10;
    for (int i = 0; i < _kMatrixCells.length; i++) {
      // Phase offset: (index - length) * 125ms / 1000ms.
      // Equivalent to progress shifted by i/8 backwards so each cell peaks in order.
      final double phase = (progress - i / _kMatrixCells.length) % 1.0;
      // Normalize to 0..1 where 0 is peak for this cell.
      // Hold buckets matching keyframes.
      double opacity;
      if (phase < 0.125) {
        opacity = 1.0;
      } else if (phase < 0.25) {
        opacity = 0.6;
      } else if (phase < 0.375) {
        opacity = 0.35;
      } else {
        opacity = 0.15;
      }

      final Offset cell = _kMatrixCells[i];
      final Rect rect = Rect.fromLTWH(
        cell.dx * scale,
        cell.dy * scale,
        2 * scale,
        2 * scale,
      );
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: opacity));
    }
  }

  @override
  bool shouldRepaint(covariant _MatrixPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
