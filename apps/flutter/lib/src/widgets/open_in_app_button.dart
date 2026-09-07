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
import '../theme/app_theme.dart';

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

final openInAppChoiceProvider = StateProvider<String>((ref) => '');

/// Split button for "open workspace in app" — mirrors
/// `packages/client/ui-open-in-app/src/client/OpenInAppAction.tsx`.
///
/// Renders nothing until the host reports at least one nameable app and the
/// workspace has a known `cwd`, like React's `if (currentEntry === undefined || cwd === '') return null`.
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
    final appsAsync = ref.watch(openInAppAppsProvider);
    final choice = ref.watch(openInAppChoiceProvider);
    return appsAsync.when(
      data: (apps) {
        if (apps.isEmpty || widget.path.isEmpty) return const SizedBox.shrink();
        final currentEntry = apps.firstWhere((e) => e.id == choice, orElse: () => apps.first);
        final current = currentEntry.id;
        // Find label via locale — fallback to id.
        // React uses t('app.*') — here we just use the id capitalized for now;
        // a full locale pass would use ref.bindLocale('open-in-app').
        String labelFor(String id) => id[0].toUpperCase() + id.substring(1);
        final svc = ref.read(openInAppServiceProvider);
        final items = apps
            .map((e) => PopupMenuItem<String>(
                  value: e.id,
                  child: Row(
                    children: [
                      _AppIcon(appId: e.id, url: svc.iconUrl(e.id), size: 18),
                      const SizedBox(width: 8),
                      Text(labelFor(e.id)),
                    ],
                  ),
                ))
            .toList();
        final isBusy = _phase == 'busy';
        final isError = _phase == 'error';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: isError ? 'Open failed' : 'Open in ${labelFor(current)}',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isError ? aliases.stateErrorPrimary : aliases.buttonPrimaryFill,
                  foregroundColor: aliases.labelPrimaryForeground,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  minimumSize: const Size(32, 28),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: isBusy ? null : () => _launch(current),
                child: isBusy
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: aliases.labelPrimaryForeground,
                        ),
                      )
                    : _AppIcon(appId: current, url: svc.iconUrl(current), size: 15),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Choose app',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: 16,
              icon: const Icon(Icons.arrow_drop_down, size: 16),
              onSelected: (id) {
                if (_inFlight) return;
                ref.read(openInAppChoiceProvider.notifier).state = id;
                unawaited(ref.read(openInAppServiceProvider).setChoice(id));
                _launch(id);
              },
              itemBuilder: (context) => items,
            ),
          ],
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
    try {
      final uri = Uri.parse(widget.url);
      final client = http_client_factory.createHttpClient();
      final resp = await client.get(uri);
      client.close();
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes.isNotEmpty) {
        if (mounted) setState(() => _bytes = resp.bodyBytes);
      } else {
        if (mounted) setState(() => _failed = true);
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
