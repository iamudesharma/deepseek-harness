import 'package:dsh_flutter/src/core/api/host_description.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes the host.describe payload field-exact', () {
    final description = HostDescription.fromJson({
      'version': '1.2.3',
      'cwd': '/home/u/proj',
      'provider': 'deepseek',
      'model': 'deepseek-chat',
      'attachedSessions': 2,
      'home': '/home/u',
      'canOpenPath': true,
    });
    expect(description.version, '1.2.3');
    expect(description.cwd, '/home/u/proj');
    expect(description.provider, 'deepseek');
    expect(description.model, 'deepseek-chat');
    expect(description.attachedSessions, 2);
    expect(description.canOpenPath, isTrue);
  });

  test('optional provider/model stay nullable when the host sets no default', () {
    final description = HostDescription.fromJson({
      'version': '1.0.0',
      'cwd': '/',
      'attachedSessions': 0,
      'home': '/',
      'canOpenPath': false,
    });
    expect(description.provider, isNull);
    expect(description.model, isNull);
  });

  test('throws on a missing required numeric field', () {
    expect(
      () => HostDescription.fromJson({
        'version': '1.0.0',
        'cwd': '/',
        'home': '/',
        'canOpenPath': false,
      }),
      throwsArgumentError,
    );
  });
}
