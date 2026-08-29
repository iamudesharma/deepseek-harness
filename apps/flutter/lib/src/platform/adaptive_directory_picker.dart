import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connection/connection_client.dart';
import '../core/services/runtime_services.dart';
import '../plugins/directory_picker/directory_browser.dart';

/// Platform-agnostic directory pick contract.
///
/// Mirrors the host `shell` / filesystem capability's directory selection,
/// abstracted behind a Provider seam so the concrete file-picker can be
/// swapped per platform (web `<input type=file>` vs macOS `NSOpenPanel`).
///
/// Web's Miller browser is the *browse* capability (`host.listDirectory` /
/// `host.createDirectory`) — full Miller columns, breadcrumb, path editor,
/// hidden-file toggle, new-folder flow — not `file_picker`. The `file_picker`
/// seam remains as a local fallback for offline tests and for the generic
/// platform row when no host is reachable. macOS's native side drives
/// `host.pickDirectory` (OS chooser on the host display) via
/// [WorkspacesService], falling back to local `NSOpenPanel` only when the
/// host is offline.
abstract class PlatformDirectoryPicker {
  /// Open a platform directory picker.
  ///
  /// @param dialogTitle – window title shown on desktop (ignored on web).
  /// @param initialDirectory – seed directory for the dialog (desktop only).
  /// @returns absolute directory path on macOS, picked file name on web
  /// for parity, or `null` when cancelled / unavailable.
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  });
}

/// Web implementation using `file_picker` web as a local fallback.
///
/// `FilePickerWeb.getDirectoryPath` is not implemented (throws
/// `UnimplementedError`); we degrade gracefully to `pickFiles` so web
/// builds remain usable without a host. The Miller browser (the true web
/// contract) lives in [WebDirectoryPickerField] and drives the host
/// browse primitives; this class is only the injected fallback for tests.
class WebDirectoryPicker implements PlatformDirectoryPicker {
  /// Creates a web picker.
  const WebDirectoryPicker();

  @override
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    try {
      final String? dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
      if (dir != null) return dir;
    } catch (_) {
      // Web plugin throws UnimplementedError – fall through to pickFiles.
    }
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    return file.path ?? file.name;
  }
}

/// macOS / desktop implementation using native `NSOpenPanel` via `file_picker`.
///
/// Delegates directly to `FilePicker.platform.getDirectoryPath`, which
/// on macOS presents `NSOpenPanel`. In production the adaptive field prefers
/// the host `pickDirectory` RPC; this is the offline/local fallback.
class MacDirectoryPicker implements PlatformDirectoryPicker {
  /// Creates a macOS picker.
  const MacDirectoryPicker();

  @override
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );
  }
}

/// Riverpod provider for the platform directory picker fallback.
///
/// Inject via `ProviderScope` overrides in tests to provide a fake:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     platformDirectoryPickerProvider.overrideWithValue(FakePicker()),
///   ],
///   child: MyApp(),
/// )
/// ```
final platformDirectoryPickerProvider = Provider<PlatformDirectoryPicker>((
  ref,
) {
  if (kIsWeb) return const WebDirectoryPicker();
  return const MacDirectoryPicker();
}, name: 'platformDirectoryPickerProvider');

/// Adaptive directory picker widget.
///
/// Branches at the widget edge on `kIsWeb` (single app, no two binaries):
/// web shows the Miller-column browse dialog ([DirectoryBrowser] over host
/// browse primitives), macOS/desktop shows the native host chooser
/// (`host.pickDirectory`) with local `NSOpenPanel` fallback. The branch is
/// kept inside this widget (not two top-level widgets) so call sites remain
/// platform-agnostic.
///
/// Each inner field uses the host `WorkspacesService` over
/// `ConnectionClient`; the injected [platformDirectoryPickerProvider] stays
/// as the offline fallback.
class AdaptiveDirectoryPicker extends ConsumerWidget {
  /// Creates the adaptive directory picker.
  const AdaptiveDirectoryPicker({
    super.key,
    this.initialDirectory,
    this.dialogTitle,
    this.label,
    this.value,
    required this.onPicked,
  });

  /// Seed directory for the native dialog (macOS only).
  final String? initialDirectory;

  /// Dialog title for desktop; ignored on web.
  final String? dialogTitle;

  /// Optional field label.
  final String? label;

  /// Current value to display in the text field (read-only).
  final String? value;

  /// Called with the picked path or `null` when cancelled.
  final ValueChanged<String?> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return WebDirectoryPickerField(
        initialDirectory: initialDirectory,
        dialogTitle: dialogTitle,
        label: label,
        value: value,
        onPicked: onPicked,
      );
    }
    return MacDirectoryPickerField(
      initialDirectory: initialDirectory,
      dialogTitle: dialogTitle,
      label: label,
      value: value,
      onPicked: onPicked,
    );
  }
}

/// Web-specific directory picker field — Miller-column browse.
///
/// Opens [DirectoryBrowser] (host `listDirectory` / `createDirectory`) on
/// Browse, falling back to the injected platform picker only when the host
/// is unreachable. This reproduces React's browse backend: listing primitives
/// drive the in-app Miller view, working for remote clients without an OS
/// dialog on the host display.
class WebDirectoryPickerField extends ConsumerStatefulWidget {
  /// Creates the web picker field.
  const WebDirectoryPickerField({
    super.key,
    this.initialDirectory,
    this.dialogTitle,
    this.label,
    this.value,
    required this.onPicked,
  });

  /// Seed directory hint (unused, kept for interface parity).
  final String? initialDirectory;

  /// Dialog title hint.
  final String? dialogTitle;

  /// Optional label.
  final String? label;

  /// Current value.
  final String? value;

  /// Callback with picked path.
  final ValueChanged<String?> onPicked;

  @override
  ConsumerState<WebDirectoryPickerField> createState() =>
      _WebDirectoryPickerFieldState();
}

class _WebDirectoryPickerFieldState
    extends ConsumerState<WebDirectoryPickerField> {
  bool _open = false;
  bool _busy = false;

  Future<DirectoryListing> _listDirectory({
    String? path,
    DirectoryListSignal? signal,
  }) async {
    final client = ref.read(connectionClientProvider);
    final svc = WorkspacesService(client);
    final map = await svc.listDirectory(path: path, signal: signal);
    return DirectoryListing.fromJson(map.cast<String, dynamic>());
  }

  Future<String> _createDirectory({
    required String path,
    required String name,
  }) async {
    final client = ref.read(connectionClientProvider);
    final svc = WorkspacesService(client);
    return svc.createDirectory(path: path, name: name);
  }

  Future<void> _openBrowser() async {
    if (_open) return;
    setState(() => _open = true);
    final String? picked = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DirectoryBrowser(
        open: true,
        listDirectory: _listDirectory,
        createDirectory: _createDirectory,
        busy: _busy,
        onOpen: (String p) => Navigator.pop(ctx, p),
        onClose: () => Navigator.pop(ctx),
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) {
      setState(() => _busy = true);
      widget.onPicked(picked);
      setState(() => _busy = false);
    } else {
      widget.onPicked(null);
    }
  }

  Future<void> _fallbackPick() async {
    try {
      final picker = ref.read(platformDirectoryPickerProvider);
      final result = await picker.pickDirectory(
        dialogTitle: widget.dialogTitle,
        initialDirectory: widget.initialDirectory,
      );
      widget.onPicked(result);
    } catch (_) {
      // FilePicker not initialized in vm tests — treat as cancelled
      widget.onPicked(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DirectoryPickerRow(
      label: widget.label ?? 'Directory (web)',
      value: widget.value,
      hint: 'Miller-column browser — browse host directories (web)',
      buttonLabel: 'Browse',
      onPressed: () async {
        // Try host browse; fall back to platform picker when host is offline (e.g. file:// tests).
        try {
          final client = ref.read(connectionClientProvider);
          // Heuristic: empty baseUrl means no host (tests) — skip host probe.
          if (client.baseUrl.isEmpty) throw StateError('no host');
          await _openBrowser();
        } catch (_) {
          await _fallbackPick();
        }
      },
    );
  }
}

/// macOS / desktop-specific directory picker field — host native chooser.
///
/// Drives `host.pickDirectory` (OS chooser on the host display) via
/// [WorkspacesService]; when the host is unreachable (file:// tests) falls
/// back to the local `NSOpenPanel` via [platformDirectoryPickerProvider].
class MacDirectoryPickerField extends ConsumerWidget {
  /// Creates the macOS picker field.
  const MacDirectoryPickerField({
    super.key,
    this.initialDirectory,
    this.dialogTitle,
    this.label,
    this.value,
    required this.onPicked,
  });

  /// Seed directory for the native dialog.
  final String? initialDirectory;

  /// Window title for the native dialog.
  final String? dialogTitle;

  /// Optional label.
  final String? label;

  /// Current value.
  final String? value;

  /// Callback with picked path.
  final ValueChanged<String?> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DirectoryPickerRow(
      label: label ?? 'Workspace directory',
      value: value,
      hint: 'Uses native folder picker (host.pickDirectory / NSOpenPanel)',
      buttonLabel: 'Browse',
      onPressed: () async {
        final client = ref.read(connectionClientProvider);
        if (client.baseUrl.isNotEmpty) {
          try {
            final svc = WorkspacesService(client);
            final picked = await svc.pickDirectory();
            onPicked(picked);
            return;
          } catch (_) {
            // Fall through to local picker when host is unreachable.
          }
        }
        try {
          final picker = ref.read(platformDirectoryPickerProvider);
          final result = await picker.pickDirectory(
            dialogTitle: dialogTitle,
            initialDirectory: initialDirectory,
          );
          onPicked(result);
        } catch (_) {
          onPicked(null);
        }
      },
    );
  }
}

class _DirectoryPickerRow extends StatelessWidget {
  const _DirectoryPickerRow({
    required this.label,
    required this.value,
    required this.hint,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String label;
  final String? value;
  final String hint;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          hint,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                  color:
                      theme.inputDecorationTheme.fillColor ?? theme.cardColor,
                ),
                child: Text(
                  value == null || value!.isEmpty
                      ? 'No folder selected'
                      : value!,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ],
    );
  }
}
