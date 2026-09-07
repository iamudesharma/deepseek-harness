/// The `ui-brand-official` plugin — Flutter port of
/// `packages/client/ui-brand-official/src/client/index.ts`.
///
/// Fills the conversation hero's brand-mark hole with the official whale
/// mark. React gates the whole apply on `DSH_CLIENT_BUILD_PROFILE=official`
/// and also fills `sidebar.brand.mark` / `sidebar.brand.name`; both sidebar
/// holes belong to the sidebar shell, which no Dart plugin declares yet, so
/// those two registrations are deferred with their declarations. The Flutter
/// desktop/web app ships only the official brand, so the hero mark registers
/// unconditionally (the profile gate has no non-official build here).
library;

import 'package:flutter/widgets.dart';

import '../../core/plugin/plugin_contract.dart';
import '../../core/slots/slot_registry.dart';
import '../../widgets/primitives/fish_logo.dart' show DsFishLogo;

/// Plugin identity.
const String kBrandOfficialPluginId = 'ui-brand-official';

/// Hero hole this plugin fills (declared by the conversation anchor).
const String kHeroBrandMarkSlot = 'conversation.hero.brand.mark';

/// The `ui-brand-official` plugin.
class BrandOfficialPlugin extends DshPlugin {
  /// Creates the plugin.
  const BrandOfficialPlugin();

  @override
  String get id => kBrandOfficialPluginId;

  @override
  List<String> get inject => ['slots'];

  @override
  Future<void> apply(DshContext ctx) async {
    // The mark waits for the conversation-owned hero hole, installs
    // atomically, and leaves with this plugin (the slots.inject wait-and-follow
    // contract — activation order against ui-conversation is unconstrained).
    final stopInject = ctx.slots.inject(kHeroBrandMarkSlot, () {
      return [
        ctx.slots.register(
          const RegistrationOptions(name: kHeroBrandMarkSlot),
          _mark,
        ),
      ];
    });
    ctx.onDispose(stopInject);
  }

  static Widget _mark(BuildContext context, dynamic props) =>
      const DsFishLogo(size: 20);
}
