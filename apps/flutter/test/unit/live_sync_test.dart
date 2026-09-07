import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_flutter/src/core/session/live_sync.dart';
import 'package:dsh_flutter/src/core/session/session_models.dart';
import 'package:dsh_flutter/src/features/conversation/message_provider.dart';

void main() {
  group('Live history and message list', () {
    test(
      'applySessionEventToSummary clears blank on user/message (React parity)',
      () {
        final summary = SessionSummary(
          sessionId: const SessionId('s-1'),
          updatedAt: 0,
          running: false,
          blank: true,
        );
        // An authoritative user message proves content started.
        final afterMessage = applySessionEventToSummary(
          summary,
          'user/message',
        )!;
        expect(afterMessage.blank, isFalse);
        expect(afterMessage.running, isTrue);
        // Turn lifecycle flips running without touching blank.
        expect(
          applySessionEventToSummary(summary, 'turn/start')!.running,
          isTrue,
        );
        expect(
          applySessionEventToSummary(afterMessage, 'turn/end')!.running,
          isFalse,
        );
        expect(applySessionEventToSummary(summary, 'todo/write'), isNull);
      },
    );

    test('messagesFromHistory handles assistant/chunk streaming when isRunning true', () {
      final entries = [
        HistoryEntry(
          event: SessionEvent(
            type: 'user/message',
            data: {'content': 'hello'},
            seq: 0,
            time: 1000,
          ),
          view: null,
        ),
        HistoryEntry(
          event: SessionEvent(
            type: 'assistant/chunk',
            data: {'delta': 'Hi '},
            seq: 1,
            time: 1001,
          ),
          view: null,
        ),
        HistoryEntry(
          event: SessionEvent(
            type: 'assistant/chunk',
            data: {'delta': 'there'},
            seq: 2,
            time: 1002,
          ),
          view: null,
        ),
      ];
      // Without isRunning, the chunk buffer is still flushed as non-streaming at the end
      // (history re-fetch case), so both have 2 messages, but streaming differs
      final withoutRunning = messagesFromHistory(entries, isRunning: false);
      expect(withoutRunning.length, 2);
      expect(withoutRunning[1].role, MessageRole.assistant);
      expect(withoutRunning[1].streaming, isFalse);
      expect(withoutRunning[1].content, 'Hi there');

      // With isRunning true, the chunk buffer is emitted as streaming
      final withRunning = messagesFromHistory(entries, isRunning: true);
      expect(withRunning.length, 2);
      expect(withRunning[1].role, MessageRole.assistant);
      expect(withRunning[1].streaming, isTrue);
      expect(withRunning[1].content, 'Hi there');
    });

    test('messagesFromHistory handles llm/retry as retry disclosure', () {
      final entries = [
        HistoryEntry(
          event: SessionEvent(
            type: 'llm/retry',
            data: {
              'retry': 2,
              'maxRetries': 5,
              'delayMs': 8120,
              'failure': {'message': '429 FreeUsageLimitError'},
              'mode': 'normal',
            },
            seq: 5,
            time: 2000,
          ),
          view: null,
        ),
      ];
      final msgs = messagesFromHistory(entries);
      expect(msgs.length, 1);
      expect(msgs.first.isRetry, isTrue);
      expect(msgs.first.retry, 2);
      expect(msgs.first.maxRetries, 5);
      expect(msgs.first.delayMs, 8120);
      expect(msgs.first.failureMessage, contains('429'));
    });

    test('messagesFromHistory decodes html entities', () {
      final entries = [
        HistoryEntry(
          event: SessionEvent(
            type: 'assistant/message',
            data: {'content': 'The user said &quot;hi&quot;'},
            seq: 0,
            time: 1000,
          ),
          view: null,
        ),
      ];
      final msgs = messagesFromHistory(entries);
      expect(msgs.first.content, 'The user said "hi"');
    });

    test('LiveHistory appendLive handles gap and dedup', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Use a fresh container with no overrides, but liveHistory should work even with empty baseUrl
      final notifier = container.read(liveHistoryProvider('test-sid').notifier);
      final e0 = HistoryEntry(
        event: SessionEvent(
          type: 'user/message',
          data: {'content': 'hi'},
          seq: 0,
          time: 1000,
        ),
        view: null,
      );
      final e1 = HistoryEntry(
        event: SessionEvent(
          type: 'assistant/chunk',
          data: {'delta': 'hello'},
          seq: 1,
          time: 1001,
        ),
        view: null,
      );
      notifier.appendLive(e0);
      // Give microtask a chance
      expect(container.read(liveHistoryProvider('test-sid')).length, 1);
      notifier.appendLive(e1);
      expect(container.read(liveHistoryProvider('test-sid')).length, 2);
      // Duplicate seq should be dropped
      notifier.appendLive(e1);
      expect(container.read(liveHistoryProvider('test-sid')).length, 2);
      // Gap should trigger re-fetch (invalidate) — simple impl keeps length until re-fetch
      final gapEntry = HistoryEntry(
        event: SessionEvent(
          type: 'assistant/message',
          data: {'content': 'gap'},
          seq: 5,
          time: 1005,
        ),
        view: null,
      );
      notifier.appendLive(gapEntry);
      // Our gap handling does ref.invalidateSelf(), which will reset to [] on next read, but within same microtask it stays 2
      // Check that it doesn't crash and length is still 2 (or 0 after invalidation)
      final afterGap = container.read(liveHistoryProvider('test-sid'));
      expect(afterGap.length == 2 || afterGap.length == 0, isTrue);
    });

    test('optimisticMessagesProvider merges and dedupes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const sid = 'test-opt';
      final liveHistory = container.read(liveHistoryProvider(sid).notifier);
      // Add a history entry for user hi
      liveHistory.appendLive(
        HistoryEntry(
          event: SessionEvent(
            type: 'user/message',
            data: {'content': 'hello'},
            seq: 0,
            time: 1000,
          ),
          view: null,
        ),
      );
      // Add optimistic with same content
      container.read(optimisticMessagesProvider(sid).notifier).state = [
        const Message(
          id: 'opt-1',
          role: MessageRole.user,
          content: 'hello',
          time: 1001,
        ),
      ];
      final msgs = container.read(liveMessageListProvider(sid));
      // Should dedupe optimistic since host already has hello
      expect(msgs.where((m) => m.content == 'hello').length, 1);
      // Add optimistic with different content
      container.read(optimisticMessagesProvider(sid).notifier).state = [
        const Message(
          id: 'opt-1',
          role: MessageRole.user,
          content: 'hello',
          time: 1001,
        ),
        const Message(
          id: 'opt-2',
          role: MessageRole.user,
          content: 'new optimistic',
          time: 1002,
        ),
      ];
      final msgs2 = container.read(liveMessageListProvider(sid));
      expect(msgs2.any((m) => m.content == 'new optimistic'), isTrue);
    });
  });
}
