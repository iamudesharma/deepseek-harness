/// The two directory-picker backend plugins — Flutter ports of
/// `ui-directory-picker-browse` and `ui-directory-picker-native`
/// `apply()`, sliced to the Dart runtime.
///
/// Each plugin publishes its pick face as a service (`directoryPicker.browse`
/// / `directoryPicker.native`) and binds the activated bridge the workspace
/// hero picker resolves. The two directory-flow holes
/// (`conversation.hero.workspace.directoryFlow` /
/// `sidebar.workspaces.directoryFlow`) are declared by the workspace owner
/// entries; these plugins fill both holes with their render occupants via
/// `slots.inject` — browse renders the Miller dialog, native is renderless
/// and drives `host.pickDirectory`. Locale `directory-browser` dictionaries
/// are registered here so the Miller copy follows the host locale.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/plugin/plugin_contract.dart';
import '../../core/services/runtime_services.dart';
import '../../core/slots/slot_registry.dart';
import 'directory_picker_flows.dart';
import 'directory_picker_service.dart';

/// Activated pick-face bridge — slot-occupant widgets resolve through this
/// instead of reaching into a bootstrap module.
DirectoryPickFace? _activatedPicker;

/// Currently bound default picker (null before first activation).
DirectoryPickFace? get activatedPickDirectory => _activatedPicker;

/// Binds (or clears) the activated default picker.
void bindActivatedPickDirectory(DirectoryPickFace? picker) {
  _activatedPicker = picker;
}

/// Plugin identity for the browse backend.
const String kBrowsePickerPluginId = 'ui-directory-picker-browse';

/// Plugin identity for the native backend.
const String kNativePickerPluginId = 'ui-directory-picker-native';

/// Namespace owning the Miller dialog copy.
const String kDirectoryBrowserLocaleNs = 'directory-browser';

/// The `ui-directory-picker-browse` plugin: web dialog face over the
/// platform seam.
class BrowseDirectoryPickerPlugin extends DshPlugin {
  /// Creates the plugin.
  const BrowseDirectoryPickerPlugin();

  @override
  String get id => kBrowsePickerPluginId;

  @override
  List<String> get inject => ['slots', 'workspaces', 'locale'];

  @override
  Future<void> apply(DshContext ctx) async {
    final WorkspacesService workspaces = ctx.require<WorkspacesService>('workspaces');
    final LocaleService locale = ctx.require<LocaleService>('locale');
    final BrowseDirectoryPicker picker = BrowseDirectoryPicker(workspaces);
    ctx.provide(kBrowsePickerServiceName, picker);
    bindActivatedPickDirectory(picker);
    ctx.onDispose(() => bindActivatedPickDirectory(null));

    // Locale dictionaries — mirrors React browse `apply` transactional pair:
    // both `zh` and `en` land as a unit; if the second hits a rival owner,
    // the first rolls back before the throw so a failed activation never
    // squats the namespace's other locale.
    final List<void Function()> localeDisposers = [];
    try {
      localeDisposers.add(locale.register(kDirectoryBrowserLocaleNs, {'zh': kDirectoryBrowserZh, 'en': kDirectoryBrowserEn}));
    } catch (e) {
      for (final d in localeDisposers.reversed) {
        d();
      }
      rethrow;
    }
    ctx.onDispose(() {
      for (final d in localeDisposers) {
        d();
      }
    });

    // Injected browse face — closed over workspaces + locale bind, so the
    // occupant's `t` follows locale changes via the stable bind function.
    BrowseFlowInjected injected() => browseInjectedFrom(workspaces, locale.bind(kDirectoryBrowserLocaleNs));

    // Only the web composition mounts the browse occupant — the native
    // composition owns the same single holes on desktop. Registering both at
    // the same priority would throw (single kind). Mirrors the React
    // single-hole enforcement while keeping the adaptive seam: one binary,
    // kIsWeb at the edge branches WebDirectoryPickerField vs
    // MacDirectoryPickerField and defaultDirectoryPicker, so the ledger's
    // winning occupant always matches the platform's picker.
    if (!kIsWeb) {
      // Native wins on desktop — browse leaves the holes for native.
      return;
    }

    final stopHero = ctx.slots.inject('conversation.hero.workspace.directoryFlow', () {
      final inj = injected();
      return [
        ctx.slots.register(
          RegistrationOptions(
            name: 'conversation.hero.workspace.directoryFlow',
            registrant: kBrowsePickerPluginId,
          ),
          (context, props) => BrowseDirectoryFlow(
            owner: DirectoryFlowOwnerProps(open: false, busy: false, onPicked: (_) {}, onCancel: () {}, onError: (_) {}),
            injected: inj,
          ),
        ),
      ];
    });
    final stopSidebar = ctx.slots.inject('sidebar.workspaces.directoryFlow', () {
      final inj = injected();
      return [
        ctx.slots.register(
          RegistrationOptions(
            name: 'sidebar.workspaces.directoryFlow',
            registrant: kBrowsePickerPluginId,
          ),
          (context, props) => BrowseDirectoryFlow(
            owner: DirectoryFlowOwnerProps(open: false, busy: false, onPicked: (_) {}, onCancel: () {}, onError: (_) {}),
            injected: inj,
          ),
        ),
      ];
    });
    ctx.onDispose(() {
      stopHero();
      stopSidebar();
    });
  }
}

/// The `ui-directory-picker-native` plugin: host-channel chooser face.
class NativeDirectoryPickerPlugin extends DshPlugin {
  /// Creates the plugin.
  const NativeDirectoryPickerPlugin();

  @override
  String get id => kNativePickerPluginId;

  @override
  List<String> get inject => ['slots', 'workspaces'];

  @override
  Future<void> apply(DshContext ctx) async {
    final WorkspacesService workspaces = ctx.require<WorkspacesService>('workspaces');
    final NativeDirectoryPicker picker = NativeDirectoryPicker(workspaces);
    ctx.provide(kNativePickerServiceName, picker);
    bindActivatedPickDirectory(picker);
    ctx.onDispose(() => bindActivatedPickDirectory(null));

    NativeFlowInjected injected() => NativeFlowInjected(pick: () => workspaces.pickDirectory());

    if (kIsWeb) {
      // Browse owns the holes on web — native leaves them.
      return;
    }

    final stopHero = ctx.slots.inject('conversation.hero.workspace.directoryFlow', () {
      final inj = injected();
      return [
        ctx.slots.register(
          RegistrationOptions(
            name: 'conversation.hero.workspace.directoryFlow',
            registrant: kNativePickerPluginId,
          ),
          (context, props) => NativeDirectoryFlow(
            owner: DirectoryFlowOwnerProps(open: false, busy: false, onPicked: (_) {}, onCancel: () {}, onError: (_) {}),
            injected: inj,
          ),
        ),
      ];
    });
    final stopSidebar = ctx.slots.inject('sidebar.workspaces.directoryFlow', () {
      final inj = injected();
      return [
        ctx.slots.register(
          RegistrationOptions(
            name: 'sidebar.workspaces.directoryFlow',
            registrant: kNativePickerPluginId,
          ),
          (context, props) => NativeDirectoryFlow(
            owner: DirectoryFlowOwnerProps(open: false, busy: false, onPicked: (_) {}, onCancel: () {}, onError: (_) {}),
            injected: inj,
          ),
        ),
      ];
    });
    ctx.onDispose(() {
      stopHero();
      stopSidebar();
    });
  }
}
