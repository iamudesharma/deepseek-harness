import 'package:dsh_flutter/src/features/layout/layout_controller.dart';
import 'package:dsh_flutter/src/widgets/layout/columns.dart' as col;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayoutState getters', () {
    test('initial state has expected defaults', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(layoutProvider);
      expect(state.sidebar, kSidebarDefault);
      // Details boots CLOSED (0) per React stores.ts:50 init details: 0; opens on demand.
      expect(state.details, 0);
      expect(state.narrow, isFalse);
      expect(state.narrowExpanded, isFalse);
      expect(state.sidebarCollapsed, isFalse);
      expect(state.detailsCollapsed, isTrue);
      expect(state.detailsOpen, isFalse);
      expect(state.effectiveSidebar, kSidebarDefault);
      expect(state.effectiveDetails, 0);
    });

    test('sidebarCollapsed when wide and sidebar == 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // toggleSidebar in wide mode closes sidebar to 0
      container.read(layoutProvider.notifier).toggleSidebar();
      expect(container.read(layoutProvider).sidebar, 0);
      expect(container.read(layoutProvider).sidebarCollapsed, isTrue);
      expect(container.read(layoutProvider).effectiveSidebar, 0);
    });

    test('sidebarCollapsed when narrow without narrowExpanded', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(layoutProvider.notifier).setNarrow(true);
      expect(container.read(layoutProvider).sidebarCollapsed, isTrue);
      expect(container.read(layoutProvider).effectiveSidebar, 0);
    });

    test('effectiveSidebar returns default when narrowExpanded with sidebar 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(layoutProvider.notifier).toggleSidebar(); // close -> sidebar 0
      container.read(layoutProvider.notifier).setNarrow(true); // narrow true resets narrowExpanded false
      // Now collapsed
      expect(container.read(layoutProvider).sidebarCollapsed, isTrue);
      container.read(layoutProvider.notifier).toggleSidebar(); // narrow flip -> expanded
      expect(container.read(layoutProvider).narrowExpanded, isTrue);
      expect(container.read(layoutProvider).sidebarCollapsed, isFalse);
      // sidebar still 0 but effective returns default
      expect(container.read(layoutProvider).sidebar, 0);
      expect(container.read(layoutProvider).effectiveSidebar, kSidebarDefault);
    });

    test('detailsCollapsed and detailsOpen mirror details == 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(layoutProvider).detailsCollapsed, isTrue);
      expect(container.read(layoutProvider).detailsOpen, isFalse);
      expect(container.read(layoutProvider).effectiveDetails, 0);
      container.read(layoutProvider.notifier).openDetails();
      expect(container.read(layoutProvider).detailsOpen, isTrue);
      expect(container.read(layoutProvider).detailsCollapsed, isFalse);
      expect(container.read(layoutProvider).effectiveDetails, kDetailsDefault);
    });
  });

  group('LayoutController.setSidebar', () {
    test('clamps within kSidebarMin..kSidebarMax and rounds', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.setSidebar(100); // below min
      expect(container.read(layoutProvider).sidebar, kSidebarMin);
      notifier.setSidebar(10000); // above max
      expect(container.read(layoutProvider).sidebar, kSidebarMax);
      notifier.setSidebar(300.6); // rounding
      expect(container.read(layoutProvider).sidebar, 301);
      notifier.setSidebar(300.4);
      expect(container.read(layoutProvider).sidebar, 300);
    });

    test('within range sets exact rounded value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(layoutProvider.notifier).setSidebar(300);
      expect(container.read(layoutProvider).sidebar, 300);
    });

    test('does not cross open/closed line by itself', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.toggleSidebar(); // close
      expect(container.read(layoutProvider).sidebar, 0);
      notifier.setSidebar(0); // clamped to min, not 0
      expect(container.read(layoutProvider).sidebar, kSidebarMin);
    });
  });

  group('LayoutController.setDetails', () {
    test('clamps within kDetailsMin..kDetailsMax', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.setDetails(100);
      expect(container.read(layoutProvider).details, kDetailsMin);
      notifier.setDetails(10000);
      expect(container.read(layoutProvider).details, kDetailsMax);
    });

    test('within range sets exact value rounded', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(layoutProvider.notifier).setDetails(360);
      expect(container.read(layoutProvider).details, 360);
    });
  });

  group('LayoutController.setNarrow', () {
    test('sets narrow and clears narrowExpanded when crossing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      // expand in narrow mode
      notifier.setNarrow(true);
      notifier.toggleSidebar();
      expect(container.read(layoutProvider).narrowExpanded, isTrue);
      // crossing back to wide clears narrowExpanded
      notifier.setNarrow(false);
      expect(container.read(layoutProvider).narrow, isFalse);
      expect(container.read(layoutProvider).narrowExpanded, isFalse);
    });

    test('no-op when value unchanged', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      final before = container.read(layoutProvider);
      notifier.setNarrow(false);
      expect(container.read(layoutProvider), before);
    });

    test('going narrow collapses sidebar by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(layoutProvider.notifier).setNarrow(true);
      expect(container.read(layoutProvider).narrow, isTrue);
      expect(container.read(layoutProvider).sidebarCollapsed, isTrue);
    });
  });

  group('LayoutController.toggleSidebar', () {
    test('wide mode toggles sidebar 0 <-> default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      expect(container.read(layoutProvider).sidebar, kSidebarDefault);
      notifier.toggleSidebar();
      expect(container.read(layoutProvider).sidebar, 0);
      notifier.toggleSidebar();
      expect(container.read(layoutProvider).sidebar, kSidebarDefault);
    });

    test('narrow mode flips narrowExpanded without touching preference', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.setNarrow(true);
      final prefBefore = container.read(layoutProvider).sidebar;
      expect(prefBefore, kSidebarDefault);
      notifier.toggleSidebar();
      expect(container.read(layoutProvider).narrowExpanded, isTrue);
      expect(container.read(layoutProvider).sidebar, prefBefore);
      notifier.toggleSidebar();
      expect(container.read(layoutProvider).narrowExpanded, isFalse);
      expect(container.read(layoutProvider).sidebar, prefBefore);
    });

    test('narrow toggle preserves custom sidebar width', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.setSidebar(350);
      notifier.setNarrow(true);
      notifier.toggleSidebar();
      expect(container.read(layoutProvider).sidebar, 350);
      expect(container.read(layoutProvider).sidebarCollapsed, isFalse);
    });
  });

  group('LayoutController.closeDetails / openDetails', () {
    test('closeDetails sets details to 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.closeDetails();
      expect(container.read(layoutProvider).details, 0);
      expect(container.read(layoutProvider).detailsCollapsed, isTrue);
    });

    test('closeDetails no-op when already 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.closeDetails();
      final before = container.read(layoutProvider);
      notifier.closeDetails();
      expect(container.read(layoutProvider), before);
    });

    test('openDetails restores default when closed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.closeDetails();
      expect(container.read(layoutProvider).details, 0);
      notifier.openDetails();
      expect(container.read(layoutProvider).details, kDetailsDefault);
    });

    test('openDetails no-op when already open', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.openDetails();
      final before = container.read(layoutProvider);
      notifier.openDetails();
      expect(container.read(layoutProvider), before);
    });
  });

  group('computeColumns', () {
    test('everything fits at preferred widths', () {
      // wide enough: sidebar 280 + details 360 + centerMin 640 = 1280
      final cols = col.computeColumns(1400, 280, 360);
      expect(cols, const col.Columns(sidebar: 280, center: 760, details: 360));
    });

    test('exactly fits threshold', () {
      final cols = col.computeColumns(1280, 280, 360);
      expect(cols.sidebar, 280);
      expect(cols.details, 360);
      expect(cols.center, 640);
    });

    test('shrinks details toward minimum when center would be below min', () {
      // viewport 1200: 280+360+640=1280 >1200 so details shrink, but not to zero
      // details needed: viewport - sidebar - centerMin = 1200-280-640=280 -> clamp to kDetailsMin 300
      // check step 2: s+d1+centerMin <= viewport ? 280+300+640=1220 >1200 no, so auto-close? Wait compute logic.
      // Let's test actual solver: at 1200, s=280, d0=360 => s+d0+centerMin=1280>1200 => step2 tries d1 = viewport-s-centerMin=280 -> but min is 300 so d1=300 => 280+300+640=1220 >1200 => step3 -> details 0, center = viewport-s =920
      // So at 1200 details auto-closes.
      final cols = col.computeColumns(1200, 280, 360);
      expect(cols.details, 0);
      expect(cols.center, 920);
    });

    test('shrinks details partially when viewport just under threshold', () {
      // Need case where d1 shrinkage suffices: e.g. viewport 1250 -> 280+300+640=1220 <=1250 so should shrink to ~? viewport - s - centerMin =330 -> within [300,360] so d1=330
      final cols = col.computeColumns(1250, 280, 360);
      expect(cols.details, 330);
      expect(cols.center, col.kCenterMin);
    });

    test('auto-closes details when still not enough space after shrink', () {
      final cols = col.computeColumns(800, 280, 360);
      expect(cols.details, 0);
      expect(cols.center, 520); // 800-280
      expect(cols.center < col.kCenterMin, isTrue);
    });

    test('closed sidebar resolves to rail 56', () {
      final cols = col.computeColumns(1200, 0, 360);
      expect(cols.sidebar, col.kSidebarCollapsed);
    });

    test('closed details resolves to 0', () {
      final cols = col.computeColumns(1200, 280, 0);
      expect(cols.details, 0);
      expect(cols.center, 1200 - 280);
    });

    test('clamps sidebar preference that exceeds max', () {
      final cols = col.computeColumns(1400, 9999, 360);
      expect(cols.sidebar, col.kSidebarMax);
    });

    test('clamps details preference that exceeds max', () {
      final cols = col.computeColumns(1600, 280, 9999);
      expect(cols.details, col.kDetailsMax);
      // should fit: 280+520+640=1440 <=1600
      expect(cols.center, 1600 - 280 - 520);
    });

    test('viewport 0 with closed sidebar yields rail and zero center', () {
      // Rail only when preference 0 (closed). With viewport 0 and closed sidebar,
      // center clamps to 0.
      final cols = col.computeColumns(0, 0, 360);
      expect(cols.sidebar, col.kSidebarCollapsed);
      expect(cols.center, 0);
      expect(cols.details, 0);
    });

    test('viewport 0 with open sidebar keeps preference (center clamps to 0)', () {
      final cols = col.computeColumns(0, 280, 360);
      expect(cols.sidebar, 280);
      expect(cols.center, 0);
      expect(cols.details, 0);
    });

    test('mirrors web fixture: wide viewport with defaults', () {
      // from columns.ts tests convention: computeColumns(viewport, sidebarDefault, detailsDefault)
      expect(col.computeColumns(1400, col.kSidebarDefault, col.kDetailsDefault),
          equals(col.Columns(sidebar: col.kSidebarDefault, center: 760, details: col.kDetailsDefault)));
    });
  });

  group('LayoutState copyWith and equality', () {
    test('copyWith replaces selected fields', () {
      const a = LayoutState(sidebar: 280, details: 360, narrow: false, narrowExpanded: false);
      final b = a.copyWith(sidebar: 300);
      expect(b.sidebar, 300);
      expect(b.details, 360);
      expect(a == b, isFalse);
    });

    test('equality includes all fields', () {
      const a = LayoutState(sidebar: 280, details: 360, narrow: false, narrowExpanded: false);
      const b = LayoutState(sidebar: 280, details: 360, narrow: false, narrowExpanded: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
