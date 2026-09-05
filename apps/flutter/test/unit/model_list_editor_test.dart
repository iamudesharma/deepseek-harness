import 'package:dsh_flutter/src/features/settings_models/widgets/model_list_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capacity vocabulary', () {
    test('parseCapacity reads counts, blanks, and K/M spellings', () {
      expect(parseCapacity(''), isNull);
      expect(parseCapacity('   '), isNull);
      expect(parseCapacity('0'), 0);
      expect(parseCapacity('128000'), 128000);
      expect(parseCapacity('256K'), 256000);
      expect(parseCapacity('1M'), 1000000);
      expect(parseCapacity('2.5K'), 2500);
      expect(parseCapacity('abc'), isNaN);
      expect(parseCapacity('12x'), isNaN);
    });

    test('formatCapacity round-trips through parseCapacity', () {
      for (final value in [1, 999, 1000, 256000, 1000000, 1500]) {
        expect(parseCapacity(formatCapacity(value)), value);
      }
      expect(formatCapacity(128000), '128K');
      expect(formatCapacity(2000000), '2M');
    });

    test('isCapacityTextValid accepts blank and positive counts only', () {
      expect(isCapacityTextValid(''), isTrue);
      expect(isCapacityTextValid('32K'), isTrue);
      expect(isCapacityTextValid('0'), isFalse);
      expect(isCapacityTextValid('-5'), isFalse);
      expect(isCapacityTextValid('lots'), isFalse);
    });
  });

  group('validateModels', () {
    test('accepts empty and well-formed rows', () {
      expect(validateModels(const []), isNull);
      expect(
        validateModels([
          {'id': 'a', 'name': 'A', 'contextWindow': 128000},
          {'id': 'b'},
        ]),
        isNull,
      );
    });

    test('rejects blank, duplicate, and malformed rows in order', () {
      expect(
        validateModels([
          {'id': '  '},
        ])?.key,
        'modelIdRequired',
      );
      expect(
        validateModels([
          {'id': 'a'},
          {'id': 'a'},
        ])?.key,
        'modelIdDuplicate',
      );
      expect(
        validateModels([
          {'id': 'a'},
          {'id': 'a '},
        ])?.key,
        'modelIdDuplicate',
      );
      expect(
        validateModels([
          {'id': 'a', 'name': ''},
        ])?.key,
        'modelNameInvalid',
      );
      expect(
        validateModels([
          {'id': 'a', 'contextWindow': 0},
        ])?.key,
        'modelContextInvalid',
      );
      expect(
        validateModels([
          {'id': 'a', 'maxTokens': -1},
        ])?.key,
        'modelMaxTokensInvalid',
      );
      expect(
        validateModels([
          {'id': 'a', 'contextWindow': double.nan},
        ])?.key,
        'modelContextInvalid',
      );
    });
  });

  group('modelDrafts', () {
    test('keeps maps, drops non-maps to empty rows', () {
      expect(
        modelDrafts([
          {'id': 'a'},
          'nope',
          42,
        ]),
        [
          {'id': 'a'},
          <String, dynamic>{},
          <String, dynamic>{},
        ],
      );
      expect(modelDrafts('nope'), isEmpty);
    });
  });

  group('ProbeTarget.askable', () {
    test('needs a route or an endpoint', () {
      expect(
        const ProbeTarget(
          settingsNs: 'llm-pi-ai',
          provider: 'opencode',
        ).askable,
        isTrue,
      );
      expect(
        const ProbeTarget(
          settingsNs: 'llm-pi-ai',
          baseURL: 'https://x/v1',
        ).askable,
        isTrue,
      );
      expect(const ProbeTarget(settingsNs: 'llm-pi-ai').askable, isFalse);
    });
  });
}
