import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection/connection_client.dart';
import '../core/connection/http_client.dart'
    if (dart.library.io) '../core/connection/http_client_io.dart'
    if (dart.library.js_interop) '../core/connection/http_client_web.dart'
    as http_client_factory;
import '../core/services/open_in_app_service.dart';
import '../core/services/runtime_services.dart' show LocaleBindOnWidgetRef;
import '../theme/app_theme.dart';
import '../plugins/open_in_app/locales.dart' show kOpenInAppNamespace;

/// Provider for the open-in-app service — one per app, like React's
/// `OpenInAppController` singleton.
final openInAppServiceProvider = Provider<OpenInAppService>((ref) {
  final client = ref.watch(connectionClientProvider);
  return OpenInAppService(client);
});

/// Available apps + last choice — mirrors React's `apps` + `choice` SnapshotStores.
final openInAppAppsProvider = FutureProvider<List<OpenInAppApp>>((ref) async {
  final svc = ref.watch(openInAppServiceProvider);
  final ids = await svc.listApps();
  return svc.filterNameable(ids);
});

final openInAppChoiceProvider =
    NotifierProvider<OpenInAppChoiceController, String>(
      OpenInAppChoiceController.new,
    );

/// Last chosen app id, hydrated from `SharedPreferences`
/// (`dsh.open-in-app.choice`) and shared across sessions and restarts —
/// mirrors React's persisted `choice` snapshot store. Hydration is async, so
/// the first frame may show the catalog head until the saved choice lands.
class OpenInAppChoiceController extends Notifier<String> {
  @override
  String build() {
    ref.read(openInAppServiceProvider).getChoice().then((saved) {
      if (saved != null && saved.isNotEmpty && state != saved) state = saved;
    });
    return '';
  }

  /// Remembers one picked app id in state and on disk.
  void choose(String appId) {
    state = appId;
    unawaited(ref.read(openInAppServiceProvider).setChoice(appId));
  }
}

/// Split button for "open workspace in app" — mirrors
/// `packages/client/ui-open-in-app/src/client/OpenInAppAction.tsx`.
///
/// Session-header only (React `conversation.session.header.utilities`,
/// `order: -10`). Renders nothing until the host reports at least one
/// nameable app and the session has a known `cwd`, like React's
/// `if (currentEntry === undefined || cwd === '') return null`.
class OpenInAppButton extends ConsumerStatefulWidget {
  const OpenInAppButton({super.key, required this.path, this.compact = false});
  final String path;
  final bool compact;
  @override
  ConsumerState<OpenInAppButton> createState() => _OpenInAppButtonState();
}

class _OpenInAppButtonState extends ConsumerState<OpenInAppButton> {
  String _phase = 'idle'; // idle | busy | error
  bool _inFlight = false;
  Timer? _busyTimer;
  Timer? _errorTimer;

  @override
  void dispose() {
    _busyTimer?.cancel();
    _errorTimer?.cancel();
    super.dispose();
  }

  Future<void> _launch(String appId) async {
    if (_inFlight) return;
    _inFlight = true;
    _busyTimer?.cancel();
    _errorTimer?.cancel();
    _busyTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _phase = 'busy');
    });
    try {
      final svc = ref.read(openInAppServiceProvider);
      await svc.open(appId: appId, path: widget.path);
      _busyTimer?.cancel();
      if (mounted) setState(() => _phase = 'idle');
    } catch (_) {
      _busyTimer?.cancel();
      if (mounted) setState(() => _phase = 'error');
      _errorTimer?.cancel();
      _errorTimer = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) setState(() => _phase = 'idle');
      });
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aliases = theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark ? DswTokens.darkAliases : DswTokens.lightAliases);
    final t = ref.bindLocale(kOpenInAppNamespace);
    String labelFor(OpenInAppApp app) => t(app.labelKey);
    final appsAsync = ref.watch(openInAppAppsProvider);
    final choice = ref.watch(openInAppChoiceProvider);
    return appsAsync.when(
      data: (apps) {
        if (apps.isEmpty || widget.path.isEmpty) return const SizedBox.shrink();
        final currentEntry = apps.firstWhere((e) => e.id == choice, orElse: () => apps.first);
        final current = currentEntry.id;
        final svc = ref.read(openInAppServiceProvider);
        // React `Menu align="end" dense selection="fill"`: right-aligned
        // under the split anchor, dense rows, selected app filled.
        final items = apps
            .map((e) => PopupMenuItem<String>(
                  value: e.id,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AppIcon(appId: e.id, url: svc.iconUrl(e.id), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          labelFor(e),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: e.id == current ? FontWeight.w600 : FontWeight.w400,
                            color: aliases.labelPrimary,
                          ),
                        ),
                      ),
                      if (e.id == current)
                        Icon(Icons.check, size: 14, color: aliases.labelSecondary),
                    ],
                  ),
                ))
            .toList();
        final isBusy = _phase == 'busy';
        final isError = _phase == 'error';
        final mainColor = isError ? aliases.stateErrorPrimary : aliases.labelPrimary;
        // React `.split`: 26px tall, pill radius 13, hairline l4 border,
        // transparent bg; `.main` 11px primary, `.chevron` 11px secondary
        // with left hairline. No FilledButton primary fill.
        return Tooltip(
          message: isError
              ? t('open.error')
              : t('open.title').replaceAll('{app}', labelFor(currentEntry)),
          child: Container(
            height: 26,
            decoration: BoxDecoration(
              border: Border.all(
                color: isError ? aliases.stateErrorPrimary : aliases.borderL4,
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isBusy ? null : () => _launch(current),
                    hoverColor: aliases.interactiveBgHover,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(7, 5, 6, 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isBusy)
                            SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: aliases.labelDimmed,
                              ),
                            )
                          else
                            _AppIcon(appId: current, url: svc.iconUrl(current), size: 15),
                          const SizedBox(width: 5),
                          Text(
                            labelFor(currentEntry),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              height: 16 / 11,
                              color: isBusy ? aliases.labelDimmed : mainColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 0.5,
                  color: isError ? aliases.stateErrorPrimary : aliases.borderL4,
                ),
                // Chevron owns the menu so the popup anchors to the split's
                // right edge. `useRootNavigator: true` keeps the overlay in
                // the root navigator (go_router nests session routes — a
                // local overlay misplaces the menu at the screen top-left).
                // `position: under` + `offset(0, 8)` mirrors `align="end"`.
                PopupMenuButton<String>(
                  tooltip: t('menu.toggle'),
                  padding: const EdgeInsets.fromLTRB(4, 5, 6, 5),
                  constraints: const BoxConstraints(minHeight: 26),
                  menuPadding: const EdgeInsets.symmetric(vertical: 4),
                  color: aliases.specificMenu,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  offset: const Offset(0, 8),
                  position: PopupMenuPosition.under,
                  useRootNavigator: true,
                  iconSize: 11,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 11,
                    color: aliases.labelSecondary,
                  ),
                  onSelected: (id) {
                    if (_inFlight) return;
                    ref.read(openInAppChoiceProvider.notifier).choose(id);
                    _launch(id);
                  },
                  itemBuilder: (context) => items,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      error: (e, st) => const SizedBox.shrink(),
    );
  }
}

class _AppIcon extends StatefulWidget {
  const _AppIcon({required this.appId, required this.url, required this.size});
  final String appId;
  final String url;
  final double size;
  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    // The icon route sits behind the same `requestRejection` fence as
    // `/api/*`. The mint (`GET /?token=` → `Set-Cookie`) already ran in
    // `OpenInAppService.listApps` before icons render, so the browser jar
    // carries `Cookie` here via `BrowserClient(withCredentials:true)`.
    try {
      final uri = Uri.parse(widget.url);
      final client = http_client_factory.createHttpClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes.isNotEmpty) {
          if (mounted) setState(() => _bytes = resp.bodyBytes);
        } else {
          if (mounted) setState(() => _failed = true);
        }
      } finally {
        client.close();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(_bytes!, width: widget.size, height: widget.size, fit: BoxFit.contain);
    }
    if (_failed) {
      return Icon(
        Icons.apps,
        size: widget.size,
        color: Theme.of(context).extension<DswThemeExtension>()?.aliases.labelTertiary ?? Colors.grey,
      );
    }
    // While loading, show a tiny placeholder that doesn't shift layout.
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: const CircularProgressIndicator(strokeWidth: 1),
    );
  }
}
