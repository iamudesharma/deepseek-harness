/// Keyed tool-presentation registry — the Dart face of the React
/// `tool.call.toolview` keyed slot (`ui-tool/src/client/contract/slots.ts`).
/// Tools contribute one card builder per wire tool name without a central
/// switch; the key domain is open, an unclaimed name falls back to the generic
/// card at the call site, and a claimed shipped key is replaced only by
/// registering at a different priority once priorities exist (today a second
/// registration for the same key throws, mirroring
/// [ChatNodeRendererRegistry.register]).
library;

import 'package:flutter/widgets.dart';

import 'tool_models.dart';

/// Builds one tool's card from its folded call state.
typedef ToolCardBuilder = Widget Function(BuildContext context, ToolCall call);

/// Keyed card-builder table dispatched by wire tool name.
class ToolPresentationRegistry {
  final Map<String, ToolCardBuilder> _builders = {};

  /// Claims [toolName] for [builder]; a second claim for the same name throws.
  void register(String toolName, ToolCardBuilder builder) {
    if (_builders.containsKey(toolName)) {
      throw StateError('tool presentation "$toolName" already registered');
    }
    _builders[toolName] = builder;
  }

  /// The builder owning [toolName], or null when the generic fallback applies.
  ToolCardBuilder? resolve(String toolName) => _builders[toolName];

  /// Every claimed wire tool name.
  Iterable<String> get keys => _builders.keys;
}
