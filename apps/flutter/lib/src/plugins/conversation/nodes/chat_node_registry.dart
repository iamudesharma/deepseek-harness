/// Chat-node renderer registry — the `conversation.chat.node` keyed seam
/// dependent packages plug into (tracker: route.conversation.chat.node).
library;

import 'package:flutter/widgets.dart';

class ChatNodeData {
  const ChatNodeData({
    required this.key,
    required this.lines,
    this.toolName,
    this.raw,
  });
  final String key;
  final List<String> lines;
  final String? toolName;
  final Object? raw;
}

typedef ChatNodeRenderer = Widget Function(
  BuildContext context,
  ChatNodeData data,
);

class ChatNodeRendererRegistry {
  final Map<String, ChatNodeRenderer> _renderers = {};
  void register(String key, ChatNodeRenderer renderer) {
    if (_renderers.containsKey(key)) {
      throw StateError('chat-node renderer "$key" already registered');
    }
    _renderers[key] = renderer;
  }

  ChatNodeRenderer? resolve(String key) => _renderers[key] ?? _renderers['*'];
  Iterable<String> get keys => _renderers.keys;
}
