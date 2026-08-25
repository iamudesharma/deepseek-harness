import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Conversation chat UI stub — native Flutter architecture now owns the
/// conversation presentation (ConversationNodeFolder → ChatView → ToolCallTree).
/// This file remains as a thin compatibility shim so legacy imports do not
/// break; the real chat surface is [ChatView] via [ConversationColumn].
class HarnessAiChat extends ConsumerWidget {
  const HarnessAiChat({super.key, required this.sessionId});
  final String sessionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(child: Text('Chat stub — use ConversationColumn/ChatView'));
  }
}
