/// Runtime services consumed by the conversation hub and later workstreams —
/// real slices of the React contracts, carried by the existing P0 client.
///
/// - [LocaleService]     registry/bind face of the locale plugin (form.locale)
/// - [SessionsService], [WorkspacesService], [DirectoryListSignal] — the
///   sessions/workspaces slices in session_workspace_services.dart (state.runtime)
/// - [RemoteEventBus]    `$on` / `$dispatch` over forwarded host cordis events
library;

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'remote_event_bus.dart';
export 'session_workspace_services.dart';

/// Bound translate face: `LocaleService.bind(ns)`'s stable per-namespace
/// lookup function.
typedef Translate = String Function(String key);

/// Shared cross-feature vocabulary — verbatim port of the `common`
/// namespace in `packages/client/locale/src/locales/zh.ts` / `en.ts`.
const Map<String, String> kCommonZh = {
  'ok': '确定',
  'cancel': '取消',
  'close': '关闭',
  'copy': '复制',
  'copied': '复制成功',
  'retry': '重试',
  'loading': '加载中…',
  'load.failed': '加载失败',
  'submit': '提交',
  'submitting': '正在提交…',
  'next': '下一步',
  'previous': '上一步',
  'skip': '跳过',
  'delete': '删除',
  'edit': '编辑',
  'save': '保存',
  'search': '搜索',
  'more': '更多',
  'select': '请选择',
  'collapse': '收起',
  'expand': '展开',
  'back': '返回',
  'unknown': '未知',
  'none': '无',
  'truncated': '已截断',
};

/// English shared vocabulary (same key set).
const Map<String, String> kCommonEn = {
  'ok': 'OK',
  'cancel': 'Cancel',
  'close': 'Close',
  'copy': 'Copy',
  'copied': 'Copied',
  'retry': 'Retry',
  'loading': 'Loading…',
  'load.failed': 'Failed to load',
  'submit': 'Submit',
  'submitting': 'Submitting…',
  'next': 'Next',
  'previous': 'Previous',
  'skip': 'Skip',
  'delete': 'Delete',
  'edit': 'Edit',
  'save': 'Save',
  'search': 'Search',
  'more': 'More',
  'select': 'Select',
  'collapse': 'Show less',
  'expand': 'Expand',
  'back': 'Back',
  'unknown': 'Unknown',
  'none': 'None',
  'truncated': 'Truncated',
};

/// Locale namespace carrying [kCommonZh] / [kCommonEn] (React `COMMON_NS`).
const String kCommonNamespace = 'common';

/// The Language row's own copy — verbatim port of the `settings.locale`
/// namespace in `packages/client/locale/src/locales/settings.ts`.
const Map<String, String> kSettingsLocaleZh = {'language.title': '语言'};

/// English copy (same key set).
const Map<String, String> kSettingsLocaleEn = {'language.title': 'Language'};

/// Locale namespace carrying the Language row dictionaries (React
/// `SETTINGS_NS` in `packages/client/locale/src/client/index.ts`).
const String kSettingsLocaleNamespace = 'settings.locale';

/// Locale registry: namespaces hold per-locale dictionaries; bind returns a
/// stable translate function with fallback chain entry-namespace (bound
/// locale → any registered locale carrying the key) → shared `common`
/// vocabulary → key itself.
class LocaleService {
  final Map<String, Map<String, Map<String, String>>> _namespaces = {};
  final List<VoidCallback> _listeners = [];
  String _locale = 'zh';
  int _revision = 0;

  LocaleService() {
    // Seed the two namespaces this runtime owns (React registers both in the
    // same package that ships the service): the shared vocabulary consulted
    // by every bind fallback, and the Language row's copy. Never removed —
    // the service lives as long as its provider container.
    _namespaces[kCommonNamespace] = {'zh': Map.of(kCommonZh), 'en': Map.of(kCommonEn)};
    _namespaces[kSettingsLocaleNamespace] = {
      'zh': Map.of(kSettingsLocaleZh),
      'en': Map.of(kSettingsLocaleEn),
    };
  }

  /// Current active locale id.
  String get locale => _locale;

  /// Monotonic change counter.
  int get revision => _revision;

  /// Subscribes to registry/locale changes; returns an unsubscriber.
  VoidCallback onChanged(VoidCallback listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Switches the active locale; unknown ids throw when any namespace has
  /// registrations (mirrors React's registered-id check).
  void setLocale(String id) {
    final known = _namespaces.values.any((dicts) => dicts.containsKey(id));
    if (_namespaces.isNotEmpty && !known) {
      throw ArgumentError.value(id, 'id', 'locale is not registered');
    }
    if (_locale == id) return;
    _locale = id;
    _bump();
  }

  /// Registers dictionaries for a namespace; returns an unsubscriber that
  /// removes exactly this call's entries.
  VoidCallback register(String ns, Map<String, Map<String, String>> dicts) {
    final existing = _namespaces.putIfAbsent(ns, () => {});
    dicts.forEach((locale, dict) {
      existing.update(locale, (d) => {...d, ...dict},
          ifAbsent: () => Map.of(dict));
    });
    _bump();
    return () {
      final dictsForNs = _namespaces[ns];
      if (dictsForNs == null) return;
      for (final locale in dicts.keys) {
        dictsForNs.remove(locale);
      }
      _bump();
    };
  }

  /// Stable translate function for [ns]: current locale first, then any other
  /// registered locale carrying the key, then the shared `common`
  /// vocabulary, else the key itself.
  String Function(String key) bind(String ns) {
    return (key) {
      final dicts = _namespaces[ns];
      if (dicts != null) {
        final primary = dicts[_locale]?[key];
        if (primary != null) return primary;
        for (final dict in dicts.values) {
          final value = dict[key];
          if (value != null) return value;
        }
      }
      final common = _namespaces[kCommonNamespace];
      if (common != null && !identical(dicts, common)) {
        final value = common[_locale]?[key] ?? common['en']?[key];
        if (value != null) return value;
      }
      return key;
    };
  }

  void _bump() {
    _revision++;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

/// Riverpod seat of the single [LocaleService] — the instance provided as the
/// `'locale'` service and shared by every consumer, so the Language row
/// controller, boot adoption, and plugin consumers see one registry (the
/// `themeRuntimeProvider` analog). Override in `ProviderScope` for tests.
final localeServiceProvider = Provider<LocaleService>((ref) => LocaleService());

/// Rebuild trigger mirroring React's LocaleFace subscribe/getSnapshot pair:
/// publishes [LocaleService.revision], which advances on every service
/// publish (active-locale switch or dictionary registration), so consumers
/// re-invoke their bound translate functions when either moves.
final localeRevisionProvider =
    NotifierProvider<LocaleRevisionController, int>(LocaleRevisionController.new);

/// Publishes [LocaleService.revision] as provider state.
class LocaleRevisionController extends Notifier<int> {
  @override
  int build() {
    final LocaleService service = ref.watch(localeServiceProvider);
    ref.onDispose(service.onChanged(() {
      if (state != service.revision) state = service.revision;
    }));
    return service.revision;
  }
}

/// MaterialApp `locale:` binding: maps the active [LocaleService] id onto
/// Flutter's Locale ('zh' → `Locale('zh')`, 'en' → `Locale('en')`) so a
/// single switch rebuilds both the bound-dictionary consumers and the
/// `Localizations.localeOf` consumers under one Localizations scope.
final materialLocaleProvider = Provider<Locale>((ref) {
  ref.watch(localeRevisionProvider);
  return Locale(ref.read(localeServiceProvider).locale);
});

extension LocaleBindOnRef on Ref {
  /// Bound translate face for [ns] — the one sanctioned way product copy
  /// reaches strings. Call from a provider's body: watching
  /// [localeRevisionProvider] here re-runs the caller on every registry or
  /// active-locale publish, so the returned function's results are fresh.
  Translate bindLocale(String ns) {
    watch(localeRevisionProvider);
    return read(localeServiceProvider).bind(ns);
  }
}

extension LocaleBindOnWidgetRef on WidgetRef {
  /// Widget-side [bindLocale]: call inside `build`, render the returned
  /// function's results directly.
  Translate bindLocale(String ns) {
    watch(localeRevisionProvider);
    return read(localeServiceProvider).bind(ns);
  }
}
