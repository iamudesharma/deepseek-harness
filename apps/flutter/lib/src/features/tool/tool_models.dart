/// Compatibility re-export: the tool models moved to the `ui-tool` plugin
/// (plugins/tool/tool_models.dart). The only importer left on this path is
/// test/conversation/chat_ui_adapter_test.dart (WIP-owned, repointed by its
/// owner); delete this shim together with that import.
library;

export '../../plugins/tool/tool_models.dart';
