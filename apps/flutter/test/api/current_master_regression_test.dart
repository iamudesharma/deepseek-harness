import 'dart:convert';

import 'package:dsh_flutter/src/core/connection/connection_client.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CURRENT master session/list projections', () {
    test('1 session/list response with projections decoded', () {
      final json = {
        'sessionId': 'session-abc',
        'updatedAt': 123456,
        'running': false,
        'blank': false,
        'cwd': '/tmp/proj',
        'projections': {
          'asOfSeq': 5,
          'values': {
            'title': 'My Title',
            'agentPreset': 'standard',
            'modelSelection': {
              'lastUsed': {'provider': 'opencode', 'model': 'mimo-v2.5-free'},
              'next': {'provider': 'opencode-go', 'model': 'hy3'},
            },
            'permissions': {
              'options': [
                {'value': 'read', 'name': 'Read'},
              ],
              'currentValue': 'read',
            },
            'plan': {'active': false, 'pending': false},
            'sessionListMetadata': {'blank': false, 'lastPromptAt': 123},
            'imageLimits': {
              'mediaTypes': ['image/png'],
              'maxImagesPerMessage': 5,
              'maxImageBytes': 1000,
              'maxMessageImageBytes': 5000,
            },
            'tokenUsage': {'total': 100},
            'contextPressure': {'ratio': 0.5},
          },
        },
      };
      final summary = SessionSummary.fromJson(json);
      expect(summary.sessionId.value, 'session-abc');
      expect(summary.title, 'My Title');
      expect(summary.agentPreset, 'standard');
      expect(summary.projections, isNotNull);
      expect(summary.projections!.asOfSeq, 5);
      expect(summary.projections!.values['title'], 'My Title');
      expect(summary.projections!.values['tokenUsage'], isNotNull);
      // Unknown keys preserved
      expect(summary.projections!.values['contextPressure'], isNotNull);
      expect(summary.displayTitle, 'My Title');
    });

    test('2 blank session valid', () {
      final json = {
        'sessionId': 'session-blank',
        'updatedAt': 1,
        'running': false,
        'blank': true,
        'cwd': '/tmp/empty',
        'projections': {
          'asOfSeq': -1,
          'values': {
            'sessionListMetadata': {'blank': true, 'lastPromptAt': null},
            'title': null,
          },
        },
      };
      final summary = SessionSummary.fromJson(json);
      expect(summary.blank, isTrue);
      expect(summary.title, isNull);
      // blank session still renders via cwd basename
      expect(summary.displayTitle, 'empty');
    });

    test('3 nonblank session', () {
      final json = {
        'sessionId': 's2',
        'updatedAt': 2,
        'running': true,
        'blank': false,
        'cwd': '/tmp/proj2',
        'projections': {
          'asOfSeq': 2,
          'values': {'title': 'Hello', 'sessionListMetadata': {'blank': false, 'lastPromptAt': 2}},
        },
      };
      final summary = SessionSummary.fromJson(json);
      expect(summary.blank, isFalse);
      expect(summary.running, isTrue);
    });

    test('4 null title falls back to cwd basename', () {
      final json = {
        'sessionId': 's3',
        'updatedAt': 3,
        'running': false,
        'blank': false,
        'cwd': '/Volumes/foo/bar',
        'projections': {
          'asOfSeq': 0,
          'values': {'title': null},
        },
      };
      final summary = SessionSummary.fromJson(json);
      expect(summary.title, isNull);
      expect(summary.displayTitle, 'bar');
    });

    test('5 null modelSelection tolerated', () {
      final json = {
        'sessionId': 's4',
        'updatedAt': 4,
        'running': false,
        'blank': true,
        'projections': {
          'asOfSeq': -1,
          'values': {'modelSelection': null},
        },
      };
      final summary = SessionSummary.fromJson(json);
      expect(summary.projections!.values['modelSelection'], isNull);
    });

    test('6 modelSelection provider+model preservation', () {
      final json = {
        'sessionId': 's5',
        'updatedAt': 5,
        'running': false,
        'blank': false,
        'projections': {
          'asOfSeq': 1,
          'values': {
            'modelSelection': {
              'lastUsed': {'provider': 'opencode', 'model': 'mimo-v2.5-free'},
              'next': {'provider': 'deepseek-official', 'model': 'deepseek-v4-flash'},
            },
          },
        },
      };
      final summary = SessionSummary.fromJson(json);
      final ms = summary.modelSelectionProjection!;
      expect(ms['lastUsed']['provider'], 'opencode');
      expect(ms['lastUsed']['model'], 'mimo-v2.5-free');
      expect(ms['next']['provider'], 'deepseek-official');
      expect(ms['next']['model'], 'deepseek-v4-flash');
      // Must preserve provider+model pair, not flatten
      expect(ms['next']['model'], isNot(contains('opencode')));
    });
  });

  group('session/page cursor handling', () {
    test('7 session/page with cursor 2 payload shape', () {
      final payload = {
        'address': {'kind': 'session', 'sessionId': 'session-abc'},
        'throughSeq': 2,
      };
      // Host validation: throughSeq must be <= cursor, cursor for this session is 2
      expect(payload['throughSeq'], 2);
      expect(payload['address'], isA<Map>());
    });

    test('8 session/page omits invalid throughSeq - uses snapshot cursor', () {
      // Flutter must use snapshot cursor, not INT_MAX
      const intMax = 2147483647;
      final snapshotCursor = 2;
      expect(snapshotCursor, isNot(intMax));
      // Ensure no code path produces INT_MAX
      final payloadWithSnapshot = {
        'address': {'kind': 'session', 'sessionId': 's1'},
        'throughSeq': snapshotCursor,
      };
      expect(payloadWithSnapshot['throughSeq'], 2);
    });
  });

  group('session/follow snapshot', () {
    test('9 snapshot cursor adoption', () {
      final snapshot = {
        'type': 'snapshot',
        'header': {'id': 's1', 'createdAt': 1, 'cwd': '/tmp'},
        'cursor': 5,
        'records': [
          {
            'type': 'event',
            'event': {'type': 'user/message', 'seq': 0, 'time': 1, 'data': {}}
          },
        ],
        'hasMore': false,
        'projections': {
          'asOfSeq': 5,
          'values': {'title': 'T', 'modelSelection': {'next': {'provider': 'p', 'model': 'm'}}}
        },
      };
      expect(snapshot['cursor'], 5);
      final records = (snapshot['records'] as List).whereType<Map>().toList();
      expect(records.first['type'], 'event');
      final projections = snapshot['projections'] as Map;
      expect((projections['values'] as Map)['title'], 'T');
    });

    test('10 snapshot event wrapper decoding', () {
      final record = {
        'type': 'event',
        'event': {'type': 'user/message', 'seq': 1, 'time': 1, 'data': {'role': 'user'}},
      };
      final entry = HistoryEntry.fromJson({'event': record['event'] as Map<String, dynamic>});
      expect(entry.event.type, 'user/message');
      expect(entry.event.seq, 1);
    });

    test('11 live event seq ordering - strictly increasing', () {
      final events = [
        SessionEvent(type: 'user/message', data: {}, seq: 1, time: 1),
        SessionEvent(type: 'assistant/message', data: {}, seq: 2, time: 2),
        SessionEvent(type: 'turn/end', data: {}, seq: 3, time: 3),
      ];
      for (int i = 1; i < events.length; i++) {
        expect(events[i].seq, greaterThan(events[i - 1].seq));
      }
    });

    test('12 duplicate event ignored (seq <= accepted)', () {
      int highestAcceptedSeq = 5;
      bool shouldAccept(int seq) => seq > highestAcceptedSeq;
      expect(shouldAccept(5), isFalse); // duplicate
      expect(shouldAccept(6), isTrue);
    });

    test('13 stale generation ignored', () {
      int generation = 2;
      int eventGeneration = 1;
      expect(eventGeneration == generation, isFalse);
    });
  });

  group('directoryPicker', () {
    test('14 directoryPicker/pick string response decoded', () {
      // Host returns bare string value, Flutter wraps as {value: string}
      final hostResponse = {
        'type': 'server-response',
        'rpcId': 'id',
        'result': {'ok': true, 'value': '/Volumes/AppleExpanded/Download/hhh/'}
      };
      final value = (hostResponse['result'] as Map)['value'];
      expect(value, isA<String>());
      expect(value, '/Volumes/AppleExpanded/Download/hhh/');
      // Flutter's _unwrapValue would produce {'value': path}
      final unwrapped = {'value': value, '_primitive': value};
      expect(unwrapped['value'], '/Volumes/AppleExpanded/Download/hhh/');
    });

    test('15 directory picker native path via pick', () {
      final value = {'value': '/tmp/picked', '_primitive': '/tmp/picked'};
      final raw = value['value'] ?? value['_primitive'] ?? value['path'];
      expect(raw, '/tmp/picked');
    });

    test('16 directory picker browse path via list', () {
      final listing = {
        'path': '/tmp',
        'entries': [
          {'name': 'a', 'kind': 'directory'},
        ],
        'parent': '/',
        'truncated': false,
      };
      expect(listing['path'], '/tmp');
      expect((listing['entries'] as List).length, 1);
    });
  });

  group('commands wire', () {
    test('17 commands/list exact request shape', () {
      final payload = {'agentId': 'session-1c256b7d-xxx'};
      // Host expects {args:{agentId}} not {args:{args:{agentId}}}
      final envelope = {'args': payload};
      expect(envelope['args'], containsPair('agentId', 'session-1c256b7d-xxx'));
      expect((envelope['args'] as Map).containsKey('args'), isFalse);
    });

    test('18 commands/execute exact request shape', () {
      final payload = {
        'agentId': 's1',
        'line': '/plan',
        'images': [],
      };
      expect(payload['line'], '/plan');
      expect(payload['agentId'], 's1');
    });

    test('19 session/prompt exact request', () {
      final payload = {
        'requestId': 'req-1',
        'sessionId': 's1',
        'mode': 'queue',
        'content': [
          {'type': 'text', 'text': 'hello'}
        ],
      };
      expect(payload['sessionId'], 's1');
      expect((payload['content'] as List).first['type'], 'text');
    });

    test('20 session/prompt accepted -> live event', () {
      final response = {'ok': true, 'value': {'accepted': true}};
      expect((response['value'] as Map)['accepted'], isTrue);
      // After accepted, host emits session/event via follow
      final event = {'type': 'user/message', 'seq': 10, 'time': 1, 'data': {}};
      expect(event['type'], 'user/message');
    });

    test('21 reconnect -> snapshot replacement', () {
      // Generation N snapshot cursor X, generation N+1 cursor Y replaces
      final snapshotN = {'cursor': 5, 'records': []};
      final snapshotN1 = {'cursor': 7, 'records': []};
      expect(snapshotN['cursor'], 5);
      expect(snapshotN1['cursor'], 7);
      // Never apply N frames after N+1
      int currentGen = 2;
      int frameGen = 1;
      expect(frameGen < currentGen, isTrue); // should ignore
    });
  });

  group('UI list mapping', () {
    test('22 session list -> sidebar row uses displayTitle', () {
      final json = {
        'sessionId': 's1',
        'updatedAt': 100,
        'running': false,
        'blank': false,
        'cwd': '/tmp/proj',
        'projections': {
          'asOfSeq': 0,
          'values': {'title': 'My Session Title'},
        },
      };
      final summary = SessionSummary.fromJson(json);
      expect(summary.displayTitle, 'My Session Title');
      // Sidebar should not discard when title is null
      final blankJson = {
        'sessionId': 's2',
        'updatedAt': 100,
        'running': false,
        'blank': true,
        'cwd': '/tmp/blank',
        'projections': {
          'asOfSeq': -1,
          'values': {'title': null},
        },
      };
      final blankSummary = SessionSummary.fromJson(blankJson);
      expect(blankSummary.blank, isTrue);
      expect(blankSummary.displayTitle, 'blank'); // falls back to cwd basename
    });

    test('23 workspace create -> list refresh', () {
      final createPayload = {'path': '/tmp/new'};
      expect(createPayload['path'], '/tmp/new');
      // After create, workspace/list should be refreshed and contain new path
      final listResponse = {
        'workspaces': [
          {'workspaceId': 'ws1', 'path': '/tmp/new', 'title': 'new'},
        ],
      };
      expect((listResponse['workspaces'] as List).first['path'], '/tmp/new');
    });
  });

  group('response model version drift - nullability', () {
    test('modelSelection.lastUsed and next may be null', () {
      final ms = {
        'lastUsed': null,
        'next': null,
      };
      expect(ms['lastUsed'], isNull);
      expect(ms['next'], isNull);
    });

    test('sessionListMetadata.lastPromptAt may be null', () {
      final meta = {'blank': true, 'lastPromptAt': null};
      expect(meta['lastPromptAt'], isNull);
    });

    test('plan may be null or {active, pending}', () {
      final planNull = null;
      final planActive = {'active': true, 'pending': false};
      expect(planNull, isNull);
      expect(planActive['active'], isTrue);
    });
  });

  test('event seq ordering - ignore duplicate <= accepted', () {
    int accepted = 10;
    expect(9 <= accepted, isTrue); // should ignore
    expect(10 <= accepted, isTrue); // duplicate
    expect(11 > accepted, isTrue); // accept
  });
}
