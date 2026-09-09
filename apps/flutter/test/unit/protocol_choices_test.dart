import 'package:dsh_flutter/src/features/settings_models/models_store.dart';
import 'package:flutter_test/flutter_test.dart';

SettingsNamespaceView _view(Map<String, Object?> schema) =>
    SettingsNamespaceView(
      ns: 'llm-pi-ai',
      schema: schema,
      revision: 1,
    );

void main() {
  test('protocolChoicesOf reads the probe-route api union', () {
    final view = _view({
      'type': 'object',
      'dict': {
        'providers': {
          'type': 'object',
          'dict': {
            '\u0000probe': {
              'type': 'object',
              'dict': {
                'api': {
                  'type': 'union',
                  'list': [
                    {'type': 'const', 'value': 'openai'},
                    {'type': 'const', 'value': 'anthropic'},
                    {'type': 'const', 'value': 7},
                  ],
                },
              },
            },
          },
        },
      },
    });
    expect(protocolChoicesOf(view), ['openai', 'anthropic']);
  });

  test('protocolChoicesOf is empty without a union', () {
    expect(protocolChoicesOf(null), isEmpty);
    expect(
      protocolChoicesOf(_view(const {'type': 'object', 'dict': {}})),
      isEmpty,
    );
    expect(
      protocolChoicesOf(
        _view(const {
          'type': 'object',
          'dict': {
            'providers': {
              'type': 'object',
              'dict': {
                '\u0000probe': {
                  'type': 'object',
                  'dict': {
                    'api': {'type': 'string'},
                  },
                },
              },
            },
          },
        }),
      ),
      isEmpty,
    );
  });
}
