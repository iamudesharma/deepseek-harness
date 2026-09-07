/// The `ui-attachment` plugin — Flutter port of
/// `packages/client/ui-attachment/src/client/index.ts`.
///
/// React fills two conversation holes: `conversation.input.attachments`
/// (composer draft rail + drop overlay) and `conversation.message.images`
/// (historical message image grid). Neither hole is declared in the Dart
/// conversation anchor's children table yet, so both registrations are
/// deferred with their declarations; this activation publishes the shared
/// staging service (`attachments`) the seat and send path will read.
library;

import '../../core/plugin/plugin_contract.dart';
import 'attachment_service.dart';

/// Plugin identity.
const String kAttachmentPluginId = 'ui-attachment';

/// The `ui-attachment` plugin.
class AttachmentPlugin extends DshPlugin {
  /// Creates the plugin.
  const AttachmentPlugin();

  @override
  String get id => kAttachmentPluginId;

  @override
  List<String> get inject => [];

  @override
  Future<void> apply(DshContext ctx) async {
    final staging = AttachmentStagingService();
    ctx.provide(kAttachmentsServiceName, staging);
    // ChangeNotifier teardown: staged drafts leave with the plugin.
    ctx.onDispose(staging.dispose);
  }
}
