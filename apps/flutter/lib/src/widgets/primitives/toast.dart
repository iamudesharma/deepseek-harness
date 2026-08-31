import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';

/// Position of the toast stack — mirrors web fixed placement with
/// optional anchor-centering.
enum DsToastPosition { topCenter, topRight, bottomCenter }

/// Severity — controls leading icon tint.
enum DsToastKind { info, success, warning, error }

/// One toast entry in the queue.
class DsToastData {
  const DsToastData({
    required this.id,
    required this.message,
    this.icon,
    this.kind = DsToastKind.info,
    this.duration = const Duration(milliseconds: 4000),
    this.fading = false,
  });

  final String id;
  final String message;
  final Widget? icon;
  final DsToastKind kind;
  final Duration duration;

  /// True once the full-opacity hold ended and the fade-out is running
  /// (React `HOLD_MS` → `FADE_MS` phases).
  final bool fading;

  /// Copy with the fade phase started.
  DsToastData startFading() => DsToastData(
    id: id,
    message: message,
    icon: icon,
    kind: kind,
    duration: duration,
    fading: true,
  );
}

/// Full-opacity hold before the fade starts — mirrors `HOLD_MS` in Toast.tsx.
const Duration kToastHold = Duration(milliseconds: 3000);

/// Fade duration — mirrors `FADE_MS` in Toast.tsx.
const Duration kToastFade = Duration(milliseconds: 1000);

/// Queue controller — holds toasts at full opacity for [kToastHold], fades
/// over [kToastFade], then removes them (total = [DsToastData.duration]).
///
/// Use [toastProvider] to show/dismiss from any [WidgetRef].
class ToastController extends StateNotifier<List<DsToastData>> {
  ToastController() : super(<DsToastData>[]);

  final Map<String, Timer> _timers = <String, Timer>{};
  int _seq = 0;

  String _nextId() =>
      'toast_${_seq++}_${DateTime.now().microsecondsSinceEpoch}';

  /// Show a toast. Returns its id for manual dismissal.
  String show(
    String message, {
    Widget? icon,
    DsToastKind kind = DsToastKind.info,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    final String id = _nextId();
    final DsToastData entry = DsToastData(
      id: id,
      message: message,
      icon: icon,
      kind: kind,
      duration: duration,
    );
    state = <DsToastData>[...state, entry];
    // Hold at full opacity until (total - fade), then start the fade phase;
    // the fade timer removes the entry when the fade completes.
    _timers[id] = Timer(duration - kToastFade, () => _startFade(id));
    return id;
  }

  void _startFade(String id) {
    state = [
      for (final DsToastData e in state)
        if (e.id == id) e.startFading() else e,
    ];
    _timers[id] = Timer(kToastFade, () => dismiss(id));
  }

  /// Convenience for success toasts.
  String showSuccess(String message, {Duration? duration}) => show(
    message,
    kind: DsToastKind.success,
    duration: duration ?? const Duration(milliseconds: 4000),
  );

  /// Convenience for error toasts.
  String showError(String message, {Duration? duration}) => show(
    message,
    kind: DsToastKind.error,
    duration: duration ?? const Duration(milliseconds: 5000),
  );

  /// Dismiss a toast by id.
  void dismiss(String id) {
    _timers.remove(id)?.cancel();
    state = state.where((DsToastData e) => e.id != id).toList();
  }

  /// Clear all toasts.
  void clear() {
    for (final Timer t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    state = <DsToastData>[];
  }

  @override
  void dispose() {
    for (final Timer t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// Riverpod provider for the toast queue.
///
/// Usage: `ref.read(toastProvider.notifier).show('Saved')`
final StateNotifierProvider<ToastController, List<DsToastData>> toastProvider =
    StateNotifierProvider<ToastController, List<DsToastData>>(
      (Ref ref) => ToastController(),
    );

/// Single toast bubble — mirrors `Toast.module.css`.
///
/// Fixed appearance: contrast fill, inverted label, 14/22, radius 14,
/// shadowLv3, slide-in + hold + fade.
class DsToast extends ConsumerWidget {
  const DsToast({super.key, required this.data, this.onDismiss});

  final DsToastData data;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);

    final Color bg = aliases.buttonContrastFill;
    final Color fg = aliases.labelPrimaryInverted;

    final Widget leading =
        data.icon ??
        switch (data.kind) {
          DsToastKind.info => Icon(
            Icons.info_outline,
            size: 18,
            color: aliases.stateWarnLabel,
          ),
          DsToastKind.success => Icon(
            Icons.check_circle_outline,
            size: 18,
            color: aliases.stateSuccessPrimary,
          ),
          DsToastKind.warning => Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: aliases.stateWarnPrimary,
          ),
          DsToastKind.error => Icon(
            Icons.error_outline,
            size: 18,
            color: aliases.stateErrorPrimary,
          ),
        };

    return Semantics(
      // React renders role="alert" so assistive tech announces the banner.
      liveRegion: true,
      child: AnimatedOpacity(
        // React Toast: full-opacity hold, then fade over FADE_MS before unmount.
        duration: kToastFade,
        opacity: data.fading ? 0 : 1,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: DswTokens.shadowLv3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(width: 18, height: 18, child: Center(child: leading)),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  data.message,
                  style: TextStyle(
                    color: fg,
                    fontSize: DswTokens.fontSizeS14,
                    height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                    fontFamily: 'SF Pro',
                    fontFamilyFallback: DswTokens.fontFamilyFallback,
                  ),
                ),
              ),
              if (onDismiss != null) ...<Widget>[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(DswTokens.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: fg.withValues(alpha: 0.7),
                    ),
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

/// Overlay host that renders the toast queue at [position].
///
/// Place once near the root (e.g. above [MaterialApp] or in the shell).
class DsToastHost extends ConsumerWidget {
  const DsToastHost({
    super.key,
    this.position = DsToastPosition.topCenter,
    this.child,
  });

  final DsToastPosition position;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DsToastData> toasts = ref.watch(toastProvider);
    final bool reduced = prefersReducedMotion(context);

    Widget toastItem(DsToastData t) {
      final Widget padded = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DsToast(
          data: t,
          onDismiss: () => ref.read(toastProvider.notifier).dismiss(t.id),
        ),
      );
      if (reduced) return padded;
      // Slide + fade in — mirrors `Toast.module.css dsh-toast-in 160ms ease-out` with reduced dropping the slide.
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        builder: (BuildContext ctx, double v, Widget? c) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * -6), child: c),
        ),
        child: padded,
      );
    }

    final Widget host = Stack(
      children: <Widget>[
        if (child case final Widget c) c,
        if (toasts.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: Align(
                alignment: _alignment,
                child: Padding(
                  padding: _padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final DsToastData t in toasts) toastItem(t),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return host;
  }

  Alignment get _alignment {
    switch (position) {
      case DsToastPosition.topCenter:
        return Alignment.topCenter;
      case DsToastPosition.topRight:
        return Alignment.topRight;
      case DsToastPosition.bottomCenter:
        return Alignment.bottomCenter;
    }
  }

  EdgeInsets get _padding {
    switch (position) {
      case DsToastPosition.topCenter:
        return const EdgeInsets.only(top: 120, left: 24, right: 24);
      case DsToastPosition.topRight:
        return const EdgeInsets.only(top: 24, right: 24);
      case DsToastPosition.bottomCenter:
        return const EdgeInsets.only(bottom: 24, left: 24, right: 24);
    }
  }
}
