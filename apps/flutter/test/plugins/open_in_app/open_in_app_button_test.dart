import 'package:dsh_flutter/src/core/services/runtime_services.dart'
    show LocaleService, localeServiceProvider;
import 'package:dsh_flutter/src/core/services/open_in_app_service.dart'
    show OpenInAppApp;
import 'package:dsh_flutter/src/plugins/open_in_app/locales.dart';
import 'package:dsh_flutter/src/widgets/open_in_app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apps = [
  OpenInAppApp(id: 'finder', labelKey: 'app.finder'),
  OpenInAppApp(id: 'vscode', labelKey: 'app.vscode'),
];

LocaleService _locales(String id) {
  final service = LocaleService();
  service.register(kOpenInAppNamespace, {
    'zh': kOpenInAppZh,
    'en': kOpenInAppEn,
  });
  service.setLocale(id);
  return service;
}

ProviderScope _harness({required String locale, String? savedChoice}) {
  if (savedChoice != null) {
    SharedPreferences.setMockInitialValues({
      'dsh.open-in-app.choice': savedChoice,
    });
  } else {
    SharedPreferences.setMockInitialValues({});
  }
  return ProviderScope(
    overrides: [
      localeServiceProvider.overrideWithValue(_locales(locale)),
      openInAppAppsProvider.overrideWith((ref) async => _apps),
    ],
    child: const MaterialApp(
      home: Scaffold(body: Center(child: OpenInAppButton(path: '/w'))),
    ),
  );
}

void main() {
  test('dictionaries stay key-identical', () {
    expect(Set.of(kOpenInAppEn.keys), Set.of(kOpenInAppZh.keys));
  });

  testWidgets('hydrated choice selects the saved app with English copy', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(locale: 'en', savedChoice: 'vscode'));
    await tester.pumpAndSettle();

    expect(find.text('VS Code'), findsOneWidget);
    expect(
      find.byTooltip('Open workspace in VS Code'),
      findsOneWidget,
    );
    expect(find.byTooltip('Choose an app to open in'), findsOneWidget);
  });

  testWidgets('Chinese copy renders through the namespace', (tester) async {
    await tester.pumpWidget(_harness(locale: 'zh'));
    await tester.pumpAndSettle();

    expect(find.text('访达'), findsOneWidget);
    expect(find.byTooltip('在 访达 中打开工作目录'), findsOneWidget);
  });

  test('choose() persists the pick for the next launch', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        localeServiceProvider.overrideWithValue(_locales('en')),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(openInAppChoiceProvider), '');
    container.read(openInAppChoiceProvider.notifier).choose('finder');
    expect(container.read(openInAppChoiceProvider), 'finder');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dsh.open-in-app.choice'), 'finder');
  });
}
