// Brand-official primitive contract — OfficialBrandMark via FishLogo.
//
// React `ui-brand-official` fills `sidebar.brand.mark` (FishLogo) and
// `sidebar.brand.name` (BrandWordmark without mark) only in the official
// profile; the conversation hero stays on ui-conversation's animated fish
// fallback. Flutter ships only the official brand and the sidebar shell has
// no slot declaration yet, so `BrandOfficialPlugin` fills
// `conversation.hero.brand.mark` with DsFishLogo(size 20) via wait-and-follow.
// The fish artwork via DsFishLogo is already golden-proven
// (brand_goldens_test light/dark at 34px and geometry at viewBox 23.16x17.04);
// this suite proves the slot wiring and that the occupied widget is exactly
// DsFishLogo at size 20, not a re-drawn approximation.
library;

import 'package:dsh_flutter/src/core/renderer/slot_outlet.dart'
    show SlotComponentProps;
import 'package:dsh_flutter/src/plugins/brand_official/brand_official_plugin.dart';
import 'package:dsh_flutter/src/widgets/primitives/fish_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../plugins/ws_surfaces/host_fixture.dart';

void main() {
  test('BrandOfficialPlugin waits for hero hole (no winners before declaration)', () async {
    final host = wsSurfacesHost();
    addTearDown(host.deactivateAll);
    host.register(const BrandOfficialPlugin());
    await host.activateAll();
    expect(host.slots.isDeclared('conversation.hero.brand.mark'), isFalse);
    expect(host.slots.winnersOfSlot('conversation.hero.brand.mark'), isEmpty);
    declareSurfaceHoles(host);
    expect(host.slots.winnersOfSlot('conversation.hero.brand.mark'), hasLength(1));
  });

  testWidgets('hero mark renders DsFishLogo size 20', (tester) async {
    final host = wsSurfacesHost();
    addTearDown(host.deactivateAll);
    host.register(const BrandOfficialPlugin());
    await host.activateAll();
    declareSurfaceHoles(host);
    final entry = host.slots.winnersOfSlot('conversation.hero.brand.mark').single;
    Widget mark(BuildContext context) =>
        (entry.component as Widget Function(BuildContext, SlotComponentProps))(
          context,
          const SlotComponentProps(slotKey: kHeroBrandMarkSlot, priority: 0),
        );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: mark)));
    await tester.pumpAndSettle();
    final fish = tester.widget<DsFishLogo>(find.byType(DsFishLogo));
    expect(fish.size, 20);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('BrandOfficial chrome unregisters when plugin deactivates', (tester) async {
    final host = wsSurfacesHost();
    addTearDown(host.deactivateAll);
    host.register(const BrandOfficialPlugin());
    await host.activateAll();
    declareSurfaceHoles(host);
    expect(host.slots.winnersOfSlot('conversation.hero.brand.mark'), hasLength(1));
    host.deactivate(kBrandOfficialPluginId);
    expect(host.slots.winnersOfSlot('conversation.hero.brand.mark'), isEmpty);
  });
}
