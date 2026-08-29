import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/attachment_rail.dart';
import '../../../core/renderer/slot_outlet.dart' show SlotVersionBuilder;
import '../../../core/session/session_models.dart';
import '../../../core/session/session_provider.dart';
import '../../../core/slots/slot_registry.dart' show SlotRegistry;
import '../../../features/model_selection/model_directory.dart';
import '../../../features/conversation/composer_controller.dart';
import '../../../platform/layout.dart' show isMobileLayout;
import '../../../widgets/primitives/dsh_menu_scaffold.dart';
import '../../../core/services/runtime_services.dart' show localeServiceProvider;
import '../../attachment/attachment_limits.dart';
import '../locales.dart' show kConversationNamespace;
import '../../input_trigger/input_trigger_controller.dart'
    show InputTriggerController;
import '../../input_trigger/input_trigger_service.dart';
import '../../input_trigger/trigger_source.dart' show PickOutcome, TokenSpan;
import '../../input_trigger/ui/composer_trigger_binding.dart';
import '../../input_trigger/ui/input_keyboard_producer.dart';
import '../../input_trigger/ui/input_trigger_shortcuts.dart';
import '../hub.dart' show activatedHub, composerSubmitHookProvider;
import '../../../core/api/frames.dart' show QueuedInboxItem;
import '../../permission_presets/ui/permission_seat.dart' show PermissionSeat;
import '../queue_state.dart';
import 'slots/hole_outlet.dart';

/// Attachment source chosen in the mobile sheet. Every source funnels into
/// the same drop intake — no second attachment model.
enum MobileAttachmentSource {
  /// Camera shot (native mobile only; image_picker requests CAMERA at pick
  /// time when the platform manifest declares it).
  camera,

  /// System photo library picker.
  library,

  /// System document picker (the images-only gate stays in the shared
  /// intake, so non-image documents surface the standard rejection).
  document,
}

/// Per-session whole-queue steer hook — fired by the empty-draft accelerated
/// Enter gesture, the `InputBar.tsx` `keyboard.steerQueue()` port (steer every
/// still-pending queued message into the running turn). Registered by the
/// surface that owns queue delivery; until one registers, the gesture stays
/// inert, mirroring the pre-RPC posture of this slice.
final composerQueueSteerHookProvider =
    StateProvider.family<void Function()?, String>((ref, sessionId) => null);

/// Composer — multiline TextField with attachments rail, access/plan/model
/// seats and send button. Styled with [DswTokens] and [DswAliases] only (no
/// literal [Color] values).
///
/// Submit on Cmd+Enter (macOS) / Ctrl+Enter (other) via [Shortcuts] +
/// [Actions] plus the send button. Uses Riverpod [composerControllerProvider]
/// family keyed by session id string.
///
/// Tool row mirrors React `InputBar.tsx` DOM order: the access seat renders
/// inline exactly like React's InputBar-owned `PermissionSelect`
/// (`ui-permission-presets` ships only the projection-fed presentation), the
/// plan chip rides `conversation.input.plan`, and the model seat sits
/// immediately before send.
class ConversationComposer extends ConsumerStatefulWidget {
  /// Creates the composer.
  const ConversationComposer({
    super.key,
    required this.sessionId,
    this.hintText = 'Ask anything…',
    this.enabled = true,
    this.controller,
  });

  /// Session id (raw string value of [SessionId]).
  final String sessionId;

  /// Placeholder for the TextField.
  final String hintText;

  /// Whether the composer is enabled externally (e.g. session running).
  final bool enabled;

  /// Externally owned field controller (host-supplied draft store). When
  /// null the composer creates and owns one seeded from composer state.
  final TextEditingController? controller;

  @override
  ConsumerState<ConversationComposer> createState() =>
      _ConversationComposerState();
}

class _ConversationComposerState extends ConsumerState<ConversationComposer> {
  late TextEditingController _controller;
  TextEditingController? _ownedFieldController;
  late final FocusNode _focusNode;
  ComposerTriggerBinding? _triggerBinding;
  bool _ownsTriggerController = false;

  /// Seeds a fresh owned controller from composer state (the externally
  /// supplied one, when given, is adopted as-is).
  TextEditingController _createFieldController() {
    final external = widget.controller;
    if (external != null) return external;
    final initial = ref.read(composerControllerProvider(widget.sessionId));
    return TextEditingController(text: initial.text);
  }

  @override
  void initState() {
    super.initState();
    // Platform seam: register submit hook for ConversationShortcuts (Enter).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
        ref
            .read(composerSubmitHookProvider(widget.sessionId).notifier)
            .state = () =>
            _handleSubmit();
      }
    });
    _controller = _createFieldController();
    if (widget.controller == null) _ownedFieldController = _controller;
    _focusNode = FocusNode();
    _ensureTriggerBinding();
    // Mount-time reconciliation between the field and composer state: a
    // host-seeded external controller (restored draft) feeds state; a
    // non-empty state (restored draft) seeds a fresh field. Deferred out of
    // initState because a provider write is illegal mid-build; runs before
    // any build-scheduled sync (registration order) so the two never race.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.mounted) return;
      final ComposerState initialState = ref.read(
        composerControllerProvider(widget.sessionId),
      );
      final String fieldText = _controller.text;
      if (initialState.text.isEmpty && fieldText.isNotEmpty) {
        ref
            .read(composerControllerProvider(widget.sessionId).notifier)
            .setText(fieldText);
      } else if (initialState.text.isNotEmpty &&
          fieldText != initialState.text) {
        _controller.value = TextEditingValue(
          text: initialState.text,
          selection: TextSelection.collapsed(offset: initialState.text.length),
        );
      }
    });
  }

  @override
  void didUpdateWidget(ConversationComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      // Adopt the new controller identity: rebind the trigger pipeline so
      // chip outcomes splice into the live instance.
      _teardownTriggerBinding(sessionId: oldWidget.sessionId);
      _ownedFieldController?.dispose();
      _ownedFieldController = null;
      _controller = _createFieldController();
      if (widget.controller == null) _ownedFieldController = _controller;
      _ensureTriggerBinding();
    }
    if (oldWidget.sessionId != widget.sessionId) {
      _teardownTriggerBinding(sessionId: oldWidget.sessionId);
      _ensureTriggerBinding();
      final next = ref.read(composerControllerProvider(widget.sessionId));
      _controller.value = TextEditingValue(
        text: next.text,
        selection: TextSelection.collapsed(offset: next.text.length),
      );
    }
  }

  @override
  void dispose() {
    _teardownTriggerBinding();
    _ownedFieldController?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Mount the trigger pipeline onto this composer's field: the per-session
  /// controller feeds chip transactions and the menu from live edits, pick
  /// outcomes splice into the field, and undo/redo restore through
  /// [ComposerTriggerBinding]. Inert before plugin activation (registry
  /// unbound) — exactly the pre-mount posture.
  void _ensureTriggerBinding() {
    if (_triggerBinding != null) return;
    final TriggerSourceRegistry? registry = activatedRegistry;
    if (registry == null) return;
    // First mount owns the lazily-created controller; a controller another
    // surface created first keeps its original sink.
    _ownsTriggerController = !registry.controllers.containsKey(
      widget.sessionId,
    );
    final InputTriggerController controller = registry.controllerFor(
      widget.sessionId,
      sink: _outcomeSink,
    );
    _triggerBinding = ComposerTriggerBinding(
      _controller,
      controller,
      (String text) => ref
          .read(composerControllerProvider(widget.sessionId).notifier)
          .setText(text),
    );
  }

  void _teardownTriggerBinding({String? sessionId}) {
    _triggerBinding?.dispose();
    _triggerBinding = null;
    if (_ownsTriggerController) {
      final String id = sessionId ?? widget.sessionId;
      // Defer the registry-side dispose until the next frame so the
      // `InputMenuAnchor`'s `ValueListenableBuilder` listening to the old
      // controller's `menu` can remove its listener before the `ValueNotifier`
      // is disposed — otherwise `didUpdateWidget` disposing synchronously while
      // the anchor still holds a listener throws "used after being disposed".
      final TriggerSourceRegistry? registry = activatedRegistry;
      if (registry != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          registry.disposeController(id);
        });
      }
      _ownsTriggerController = false;
    }
  }

  bool _outcomeSink(PickOutcome outcome, TokenSpan span) =>
      _triggerBinding?.apply(outcome, span) ?? false;

  /// Chip-occurrence deletion — InputBar.tsx keydown branch port: with a
  /// collapsed selection, Backspace removes the occurrence ending at the
  /// caret, Delete the one starting at it; any other Backspace/Delete falls
  /// through to native editing. Runs on an ancestor Focus because Flutter's
  /// field deletes via intents dispatched above this point in the bubble.
  KeyEventResult _interceptChipDelete(FocusNode node, KeyEvent event) {
    final binding = _triggerBinding;
    if (binding == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key != LogicalKeyboardKey.backspace &&
        key != LogicalKeyboardKey.delete) {
      return KeyEventResult.ignored;
    }
    final bool composing =
        _controller.value.composing.isValid &&
        !_controller.value.composing.isCollapsed;
    if (composing || !widget.enabled) return KeyEventResult.ignored;
    if (ref.read(composerControllerProvider(widget.sessionId)).isSending) {
      return KeyEventResult.ignored; // submitting spans are read-only
    }
    final TextSelection selection = _controller.selection;
    if (!selection.isValid || selection.start != selection.end) {
      return KeyEventResult.ignored; // range deletions stay native
    }
    final bool deleted = binding.deleteOccurrenceAt(
      selection.start,
      backward: key == LogicalKeyboardKey.backspace,
    );
    return deleted ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _commitComposerText(String value) {
    ref
        .read(composerControllerProvider(widget.sessionId).notifier)
        .setText(value);
  }

  /// The composer text field, extracted so both the bound and pre-activation
  /// mount paths share one construction.
  Widget _buildField(bool isSending) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled && !isSending,
      maxLines: 6,
      minLines: 1,
      textInputAction: TextInputAction.newline,
      onChanged: _commitComposerText,
      style: TextStyle(
        fontSize: DswTokens.fontSizeS14,
        height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
        color: aliases.labelPrimary,
        fontFamily: 'SF Pro',
        fontFamilyFallback: DswTokens.fontFamilyFallback,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(
          fontSize: DswTokens.fontSizeS14,
          color: aliases.labelCaption,
        ),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DswTokens.spaceSm,
          vertical: DswTokens.spaceSm,
        ),
        isDense: true,
      ),
    );
  }

  /// Batch image intake — Dart port of `InputBar.intakeImages`; delegates to
  /// the shared [intakeComposerImages] helper so document drops and the
  /// picker button take one path.
  String? intakeImages(List<DroppedFile> files) {
    final String? rejected = intakeComposerImages(
      staged: ref
          .read(composerControllerProvider(widget.sessionId))
          .attachments,
      limits: ref.read(imageLimitsProvider),
      add: (items) => ref
          .read(composerControllerProvider(widget.sessionId).notifier)
          .addAttachments(items),
      files: files,
    );
    return rejected;
  }

  void _showRejection(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Platform image picker → the same [intakeImages] path as drops.
  ///
  /// Native mobile first presents the source sheet (camera / photo library /
  /// document picker); every source feeds the same intake + limits as drops.
  /// Desktop/Web keep the direct system picker.
  Future<void> _pickImages() async {
    final bool isMountedAtEntry = mounted;
    final String sid = widget.sessionId;
    // Capture notifier/limits before the async sheet gap — State may be considered
    // unmounted after showModalBottomSheet on some Xiaomi/MIUI routes, but the
    // provider container itself remains alive. Using the captured notifier avoids
    // "Bad state: Cannot use ref after dispose" when _intakeXFiles later calls
    // ref.read(composerControllerProvider).
    final notifier = ref.read(composerControllerProvider(sid).notifier);
    final limits = ref.read(imageLimitsProvider);
    debugPrint('[composer] _pickImages entry isMobileLayout=$isMobileLayout enabled=${widget.enabled} isSending=${ref.read(composerControllerProvider(sid)).isSending} mounted=$isMountedAtEntry sid=$sid');
    if (isMobileLayout) {
      final MobileAttachmentSource? source = await _showMobileAttachmentSheet();
      final bool isMountedAfterSheet = mounted;
      debugPrint('[composer] sheet returned source=$source mounted=$isMountedAfterSheet sid=$sid');
      if (source == null) return;
      // Do not early-return on !mounted — the container-held notifier is still valid;
      // the sheet's route temporarily makes State.mounted false on MIUI.
      if (!isMountedAfterSheet) {
        debugPrint('[composer] sheet returned but State.mounted false, still proceeding (container notifier captured)');
      }
      final ImagePicker picker = ImagePicker();
      try {
        switch (source) {
          case MobileAttachmentSource.camera:
            final XFile? shot = await picker.pickImage(source: ImageSource.camera);
            debugPrint('[composer] camera result=${shot?.path}');
            if (shot != null) await _intakeXFilesWithNotifier(<XFile>[shot], notifier, limits);
          case MobileAttachmentSource.library:
            final List<XFile> picked = await picker.pickMultiImage();
            debugPrint('[composer] library picked ${picked.length}');
            await _intakeXFilesWithNotifier(picked, notifier, limits);
          case MobileAttachmentSource.document:
            await _pickImagesViaFilePickerWithNotifier(notifier, limits);
        }
      } catch (e, st) {
        debugPrint('[composer] picker error: $e\n$st');
        if (mounted) _showRejection('Image picker failed: $e');
      }
      return;
    }
    await _pickImagesViaFilePickerWithNotifier(notifier, limits);
  }


  /// Direct system image picker (desktop/Web path, mobile document entry).
  Future<void> _pickImagesViaFilePicker() async {
    try {
      debugPrint('[composer] file_picker pickFiles start');
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      debugPrint('[composer] file_picker result=${result?.files.length} cancelled=${result==null}');
      if (result == null || result.files.isEmpty) return;
      for (final f in result.files) {
        debugPrint('[composer] file_picker file name=${f.name} mime=${_mimeTypeFor(f.name)} size=${f.size} bytes=${f.bytes?.length} path=${f.path}');
      }
      final String? rejected = intakeImages(
        result.files
            .map(
              (file) => DroppedFile(
                name: file.name,
                mimeType: _mimeTypeFor(file.name),
                size: file.size,
                path: file.path,
                bytes: file.bytes,
              ),
            )
            .toList(growable: false),
      );
      if (rejected != null) _showRejection(rejected);
    } catch (e, st) {
      debugPrint('[composer] file_picker error: $e\n$st');
      _showRejection('File picker failed: $e');
    }
  }

  /// Map picker results onto the shared drop intake (lazy byte read via the
  /// platform seam; limits decide rejection).
  Future<void> _intakeXFiles(List<XFile> files) async {
    if (files.isEmpty) {
      debugPrint('[composer] _intakeXFiles empty, cancelled');
      return;
    }
    try {
      final List<DroppedFile> dropped = <DroppedFile>[];
      for (final XFile file in files) {
        final int len = await file.length().catchError((_) => 0);
        debugPrint('[composer] _intakeXFiles file name=${file.name} path=${file.path} len=$len mime=${_mimeTypeFor(file.name)}');
        dropped.add(
          DroppedFile(
            name: file.name,
            mimeType: _mimeTypeFor(file.name),
            size: len,
            path: file.path,
            bytes: null,
          ),
        );
      }
      final String? rejected = intakeImages(dropped);
      if (rejected != null) {
        debugPrint('[composer] _intakeXFiles rejected=$rejected');
        _showRejection(rejected);
      } else {
        debugPrint('[composer] _intakeXFiles staged ${dropped.length} ok');
      }
    } catch (e, st) {
      debugPrint('[composer] _intakeXFiles error: $e\n$st');
      _showRejection('Failed to stage images: $e');
    }
  }

  Future<void> _intakeXFilesWithNotifier(
      List<XFile> files, ComposerController notifier, ImageLimits? limits) async {
    if (files.isEmpty) {
      debugPrint('[composer] _intakeXFilesWithNotifier empty, cancelled');
      return;
    }
    try {
      final List<DroppedFile> dropped = <DroppedFile>[];
      for (final XFile file in files) {
        final int len = await file.length().catchError((_) => 0);
        debugPrint('[composer] _intakeXFilesWithNotifier file name=${file.name} path=${file.path} len=$len mime=${_mimeTypeFor(file.name)}');
        dropped.add(DroppedFile(
          name: file.name,
          mimeType: _mimeTypeFor(file.name),
          size: len,
          path: file.path,
          bytes: null,
        ));
      }
      final String? rejected = intakeComposerImages(
        staged: notifier.state.attachments,
        limits: limits,
        add: (items) => notifier.addAttachments(items),
        files: dropped,
      );
      if (rejected != null) {
        debugPrint('[composer] _intakeXFilesWithNotifier rejected=$rejected');
        // Use mounted check for SnackBar, but not for staging which already succeeded via notifier
        if (mounted) _showRejection(rejected);
      } else {
        debugPrint('[composer] _intakeXFilesWithNotifier staged ${dropped.length} ok total=${notifier.state.attachments.length}');
      }
    } catch (e, st) {
      debugPrint('[composer] _intakeXFilesWithNotifier error: $e\n$st');
      if (mounted) _showRejection('Failed to stage images: $e');
    }
  }

  Future<void> _pickImagesViaFilePickerWithNotifier(
      ComposerController notifier, ImageLimits? limits) async {
    try {
      debugPrint('[composer] file_picker with notifier pickFiles start');
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      debugPrint('[composer] file_picker with notifier result=${result?.files.length} cancelled=${result==null}');
      if (result == null || result.files.isEmpty) return;
      for (final f in result.files) {
        debugPrint('[composer] file_picker with notifier file name=${f.name} mime=${_mimeTypeFor(f.name)} size=${f.size} bytes=${f.bytes?.length} path=${f.path}');
      }
      final String? rejected = intakeComposerImages(
        staged: notifier.state.attachments,
        limits: limits,
        add: (items) => notifier.addAttachments(items),
        files: result.files
            .map((file) => DroppedFile(
                  name: file.name,
                  mimeType: _mimeTypeFor(file.name),
                  size: file.size,
                  path: file.path,
                  bytes: file.bytes,
                ))
            .toList(growable: false),
      );
      if (rejected != null && mounted) _showRejection(rejected);
    } catch (e, st) {
      debugPrint('[composer] file_picker with notifier error: $e\n$st');
      if (mounted) _showRejection('File picker failed: $e');
    }
  }

  /// Mobile attachment-source sheet. Anchored to the bottom, keyboard-safe
  /// (Scaffold inset), entries localized by the shared composer vocabulary.
  Future<MobileAttachmentSource?> _showMobileAttachmentSheet() {
    final t = ref.read(localeServiceProvider).bind(kConversationNamespace);
    return showModalBottomSheet<MobileAttachmentSource>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t('attachment.takePhoto')),
              onTap: () =>
                  Navigator.of(sheetContext).pop(MobileAttachmentSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t('attachment.photoLibrary')),
              onTap: () =>
                  Navigator.of(sheetContext)
                      .pop(MobileAttachmentSource.library),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(t('attachment.chooseDocument')),
              onTap: () =>
                  Navigator.of(sheetContext)
                      .pop(MobileAttachmentSource.document),
            ),
          ],
        ),
      ),
    );
  }

  static String _mimeTypeFor(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0) return '';
    return switch (name.substring(dot + 1).toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      _ => '',
    };
  }

  Future<void> _handleSubmit() async {
    final notifier = ref.read(
      composerControllerProvider(widget.sessionId).notifier,
    );
    // Sync controller text into state before submit (deferred onChanged may lag).
    notifier.setText(_controller.text);
    await notifier.submit();
    if (!mounted) return;
    // Clear local controller after successful submit (state text cleared by controller).
    final after = ref.read(composerControllerProvider(widget.sessionId));
    if (after.text.isEmpty && _controller.text.isNotEmpty) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final ComposerState state = ref.watch(
      composerControllerProvider(widget.sessionId),
    );
    // Composition ledger for the composer-side holes (overlay + tool-row
    // seats). Empty until ui-conversation activates — outlets render nothing.
    final SlotRegistry slotRegistry = activatedHub?.slots ?? SlotRegistry();

    // Keep controller in sync when state changes externally (e.g. clear after
    // submit). Only sync when live state differs from the field to avoid
    // cursor jumps; the live re-read also lets the mount-time adoption (an
    // earlier post-frame callback) win over this frame's captured snapshot.
    if (state.text != _controller.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ComposerState live = ref.read(
          composerControllerProvider(widget.sessionId),
        );
        if (live.text == _controller.text) return;
        final sel = _controller.selection;
        final TextSelection nextSelection;
        if (!sel.isValid) {
          nextSelection = TextSelection.collapsed(offset: live.text.length);
        } else {
          // Clamp the carried-over caret to the new text length — after a
          // submit the store clears to "" while the field still holds the old
          // offset (e.g. 2 for "hi"), which would throw
          // "Range start 2 is out of text of length 0".
          final int base = sel.baseOffset.clamp(0, live.text.length).toInt();
          final int extent = sel.extentOffset
              .clamp(0, live.text.length)
              .toInt();
          nextSelection = sel.isCollapsed
              ? TextSelection.collapsed(offset: base)
              : TextSelection(baseOffset: base, extentOffset: extent);
        }
        _controller.value = TextEditingValue(
          text: live.text,
          selection: nextSelection,
        );
      });
    }

    final bool canSend = widget.enabled && state.canSubmit;
    final bool isSending = state.isSending;

    // Empty-draft accelerated Enter steers the whole queue — InputBar.tsx
    // canSteerQueue port: a running ordinary session with still-pending queued
    // rows, empty draft, live input. (The subagent===null conjunct is not
    // representable yet: SessionSummary carries no continuable-child marker.)
    final SessionSummary? summary = ref.watch(
      sessionByIdProvider(SessionId(widget.sessionId)),
    );
    final List<QueuedInboxItem> queueRows =
        ref.watch(queueProvider)[widget.sessionId] ?? const <QueuedInboxItem>[];
    final bool draftEmpty =
        state.text.trim().isEmpty && state.attachments.isEmpty;
    final bool canSteerQueue =
        draftEmpty &&
        widget.enabled &&
        !isSending &&
        (summary?.running ?? false) &&
        queueRows.any((row) => row.placement == 'queued');

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          includeRepeats: false,
        ): const _SubmitIntent(),
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          includeRepeats: false,
        ): const _SubmitIntent(),
        // Shift+Enter inserts a native newline — the InputBar.tsx textarea
        // branch (plain Enter submits, shift-modified Enter never does).
        // Explicit here because desktop hardware-key handling only reaches
        // the field through the platform text input, which widget tests and
        // some hosts bypass.
        const SingleActivator(
          LogicalKeyboardKey.enter,
          shift: true,
          includeRepeats: false,
        ): const _NewlineIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          // Accelerated Enter over an empty draft acts on the queue
          // instead of the draft the machine would reject anyway.
          _SubmitIntent: CallbackAction<_SubmitIntent>(
            onInvoke: (_) {
              if (canSteerQueue) {
                ref
                    .read(composerQueueSteerHookProvider(widget.sessionId))
                    ?.call();
                return null;
              }
              if (canSend) _handleSubmit();
              return null;
            },
          ),
          _NewlineIntent: CallbackAction<_NewlineIntent>(
            onInvoke: (_) {
              if (!widget.enabled || isSending) return null;
              final TextSelection sel = _controller.selection;
              final TextSelection base = sel.isValid
                  ? sel
                  : TextSelection.collapsed(offset: _controller.text.length);
              final String next = _controller.text.replaceRange(
                base.start,
                base.end,
                '\n',
              );
              _controller.value = TextEditingValue(
                text: next,
                selection: TextSelection.collapsed(offset: base.start + 1),
              );
              _commitComposerText(next);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: false,
          child: Padding(
            // Mirrors InputBar.module.css: root padding 0 var(--dsh-composer-side-clearance) 8px
            // plus the centered max-width var(--dsh-composer-card-max-width).
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                // The card is the overlay positioning context (InputBar.module.css
                // `.card { position: relative }`): open entries float ABOVE the
                // card's top edge without pushing the field down.
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      decoration: BoxDecoration(
                        color: aliases.specificInputMajor,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: aliases.borderL2DarkmodeThin),
                        boxShadow: DswTokens.shadowLv2,
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // Attachments rail
                          if (state.attachments.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: DswTokens.spaceSm,
                              ),
                              child: AttachmentRail(
                                items: state.attachments,
                                onOpen: (ComposerAttachment att) {
                                  showDialog<void>(
                                    context: context,
                                    builder: (BuildContext ctx) =>
                                        AttachmentLightbox(
                                          attachment: att,
                                          aliases: aliases,
                                        ),
                                  );
                                },
                                onRemove: widget.enabled && !isSending
                                    ? (ComposerAttachment att) => ref
                                          .read(
                                            composerControllerProvider(
                                              widget.sessionId,
                                            ).notifier,
                                          )
                                          .removeAttachmentById(
                                            att.id.isNotEmpty
                                                ? att.id
                                                : att.name,
                                          )
                                    : null,
                              ),
                            ),
                          // The mounted trigger pipeline: undo/redo shortcuts
                          // drive the session controller with the restored draft
                          // pushed back into the field; the chip-delete focus
                          // intercepts Backspace/Delete adjacent to an occurrence.
                          Builder(
                            builder: (BuildContext context) {
                              final TriggerSourceRegistry? registry =
                                  activatedRegistry;
                              final binding = _triggerBinding;
                              if (registry == null || binding == null) {
                                return InputKeyboardProducer(
                                  controller: activatedRegistry
                                      ?.controllers[widget.sessionId],
                                  field: _controller,
                                  child: _buildField(isSending),
                                );
                              }
                              return Focus(
                                onKeyEvent: _interceptChipDelete,
                                child: InputTriggerShortcuts(
                                  registry: registry,
                                  sessionId: widget.sessionId,
                                  invocable: () => widget.enabled && !isSending,
                                  undo: () => binding.undo(),
                                  redo: () => binding.redo(),
                                  child: InputKeyboardProducer(
                                    controller:
                                        registry.controllers[widget.sessionId],
                                    field: _controller,
                                    child: _buildField(isSending),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: DswTokens.spaceSm),
                          // Tool row — React InputBar.tsx:695-758 DOM order:
                          // access chip (InputBar renders PermissionSelect
                          // inline in `.modes`, lines 509-511/711-714), plan
                          // seat (`conversation.input.plan`, line 713), then
                          // the left extensions (attach + `input.left`),
                          // spacer, then the trailing group: `input.right`,
                          // the model seat (line 719), send — the model seat
                          // sits immediately before send. The plan seat is a
                          // declared list hole; entries appear when an owning
                          // plugin registers.
                          Builder(builder: (BuildContext context) {
                            final bool narrowMobile = isMobileLayout &&
                                MediaQuery.sizeOf(context).width < 600;
                            Widget permissionSeat = const PermissionSeat();
                            if (narrowMobile) {
                              permissionSeat = Flexible(child: permissionSeat);
                            }
                            Widget modelSeat = _LiveModelDropdown(
                              sessionId: widget.sessionId,
                              aliases: aliases,
                              enabled: widget.enabled && !isSending,
                              compact: narrowMobile,
                            );
                            if (narrowMobile) {
                              modelSeat = Flexible(child: modelSeat);
                            }
                            final bool attachEnabled = widget.enabled && !isSending;
                            debugPrint('[composer] build attachEnabled=$attachEnabled isMobileLayout=$isMobileLayout width=${MediaQuery.sizeOf(context).width}');
                            return Row(
                              children: <Widget>[
                                permissionSeat,
                                HoleOutlet(
                                  registry: slotRegistry,
                                  slotKey: 'conversation.input.plan',
                                ),
                                IconButton(
                                  tooltip: 'Attach images',
                                  icon: Icon(
                                    Icons.attach_file,
                                    size: 18,
                                    color: aliases.labelTertiary,
                                  ),
                                  onPressed: attachEnabled
                                      ? () {
                                          debugPrint('[composer] attach button tapped');
                                          _pickImages();
                                        }
                                      : null,
                                ),
                                HoleOutlet(
                                  registry: slotRegistry,
                                  slotKey: 'conversation.input.left',
                                ),
                                const Spacer(),
                                HoleOutlet(
                                  registry: slotRegistry,
                                  slotKey: 'conversation.input.right',
                                ),
                                modelSeat,
                              const SizedBox(width: DswTokens.spaceSm),
                              // Send disc — figma IconButton 34:10465: 34px circle, info-fill pair (500→400) + white glyph.
                              // Mirrors `InputBar.module.css .primary`: `background: var(--dsw-alias-button-info-fill)`.
                              _SendDisc(
                                enabled: canSend && !isSending,
                                isSending: isSending,
                                aliases: aliases,
                                onPressed: canSend ? _handleSubmit : null,
                              ),
                            ],
                          );
                          }),
                          if (state.error != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: DswTokens.spaceSm,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.error_outline,
                                    size: 14,
                                    color: aliases.stateErrorPrimary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      state.error!,
                                      style: TextStyle(
                                        fontSize: DswTokens.fontSizeXxs12,
                                        color: aliases.stateErrorPrimary,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => ref
                                        .read(
                                          composerControllerProvider(
                                            widget.sessionId,
                                          ).notifier,
                                        )
                                        .clearError(),
                                    child: const Text('Dismiss'),
                                  ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            // Desktop submits via the shortcut; touch uses
                            // the send disc, so the hint is desktop-only.
                            child: isMobileLayout
                                ? const SizedBox.shrink()
                                : Text(
                                    'Cmd+Enter to send',
                                    style: TextStyle(
                                      fontSize: DswTokens.fontSizeXxs12,
                                      color: aliases.labelCaption,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    // The composer overlay anchor (InputBar.module.css
                    // `.overlayAnchor`: a zero-height strip spanning the
                    // card's top edge, inset 0). Entries render themselves
                    // through the root Overlay (OverlayPortal) fully above
                    // that edge — CSS `bottom: calc(100% + 4px)` — so the
                    // slash-candidate menu and popupSelect shell float over
                    // the transcript AND stay hit-testable there: painting
                    // through a negative-offset translation leaves taps
                    // outside every ancestor box. The strip is also the
                    // CompositedTransformTarget region: menu left edge ==
                    // card left edge — hence the leading Align, because the
                    // hole outlet's column would otherwise center the
                    // zero-size anchor boxes mid-card.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SlotVersionBuilder(
                          registry: slotRegistry,
                          builder: (BuildContext context, int _) => HoleOutlet(
                            registry: slotRegistry,
                            slotKey: 'conversation.input.overlay',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared batch image intake — Dart port of `InputBar.intakeImages`.
///
/// Pre-check order mirrors React exactly: format precedes limits (a batch
/// with a non-image announces the format problem, not a count or size it
/// could never pass anyway), then per-message count (existing drafts
/// count), then per-file size, then per-message total. Returns a rejection
/// message, or `null` when the batch was staged through [add].
///
/// Also mirrors `ConversationController.createDraftImages` assignment:
/// `id: crypto.randomUUID()`, `previewUrl: URL.createObjectURL(file)` (web)
/// or file path (native) — here the previewUrl is `file.path` when present
/// so the rail can show a thumbnail immediately; generation of a blob URL on
/// web will be handled when `DroppedFile` carries the bytes.
String? intakeComposerImages({
  required List<ComposerAttachment> staged,
  required ImageLimits? limits,
  required void Function(List<ComposerAttachment> items) add,
  required List<DroppedFile> files,
}) {
  if (files.isEmpty) return null;
  if (limits != null) {
    if (files.any((file) => !limits.mediaTypes.contains(file.mimeType))) {
      return 'Only image files can be attached';
    }
    if (staged.length + files.length > limits.maxImagesPerMessage) {
      return 'You can attach up to ${limits.maxImagesPerMessage} images per message';
    }
    if (files.any((file) => file.size > limits.maxImageBytes)) {
      return 'Each image must be smaller than ${imageSizeText(limits.maxImageBytes)}';
    }
    final int stagedTotal = staged.fold<int>(
      0,
      (sum, att) => sum + (att.size ?? 0),
    );
    final int incoming = files.fold<int>(0, (sum, file) => sum + file.size);
    if (stagedTotal + incoming > limits.maxMessageImageBytes) {
      return 'Images for one message must total less than ${imageSizeText(limits.maxMessageImageBytes)}';
    }
  }
  add(
    files
        .map(
          (file) => ComposerAttachment.create(
            name: file.name,
            path: file.path,
            mimeType: file.mimeType,
            size: file.size,
            previewUrl: file.path,
            bytes: file.bytes,
          ),
        )
        .toList(growable: false),
  );
  return null;
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

/// Shift+Enter — inserts one newline at the caret (never submits).
class _NewlineIntent extends Intent {
  const _NewlineIntent();
}

class _SendDisc extends StatelessWidget {
  const _SendDisc({
    required this.enabled,
    required this.isSending,
    required this.aliases,
    this.onPressed,
  });
  final bool enabled;
  final bool isSending;
  final DswAliases aliases;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool canPress = enabled && onPressed != null;
    return Opacity(
      opacity: canPress ? 1 : 0.4,
      child: Material(
        color: aliases.buttonInfoFill,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canPress ? onPressed : null,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: isSending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFFFFFF),
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: Color(0xFFFFFFFF),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which pane the model dropdown shows — `ModelSelect.tsx` `Pane`: the root
/// row pair, the drilled provider-grouped model list, or the drilled effort
/// list.
enum _ModelPane { root, model, effort }

/// Composer model control — port of `ui-model-selection`'s `ModelSelect.tsx`
/// two-level menu over the per-session directory:
///
/// * Root pane shows a Model row and (when the exact current model advertises
///   reasoning) an Effort row; each drills into its own list.
/// * The current selection resolves STRICTLY from groups containing it — no
///   provider guessing, and an empty catalog never synthesizes fallback rows
///   (`kAvailableModels` stays out of the menu).
/// * Choosing a model submits `{provider, model, reasoningEffort:
///   target.reasoning?.defaultEffort}` — a supported model starts at its
///   advertised default, an unsupported one clears any stale effort (the wire
///   omits null). Choosing an effort preserves provider/model.
/// * A rejected selection surfaces through the transient error strip anchored
///   to the composer card; load failures keep their in-menu Retry.
class _LiveModelDropdown extends ConsumerStatefulWidget {
  const _LiveModelDropdown({
    required this.sessionId,
    required this.aliases,
    required this.enabled,
    this.compact = false,
    this.compactMaxWidth = 72,
  });

  final String sessionId;
  final DswAliases aliases;
  final bool enabled;

  /// Phone-width posture: the label cap drops so the pill fits the tool row
  /// instead of overflowing it. Desktop keeps the 160 cap.
  final bool compact;

  final double compactMaxWidth;

  @override
  ConsumerState<_LiveModelDropdown> createState() => _LiveModelDropdownState();
}

class _LiveModelDropdownState extends ConsumerState<_LiveModelDropdown> {
  final GlobalKey _anchorKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();
  _ModelPane _pane = _ModelPane.root;

  /// Resolves `(group, model)` for [current] strictly from [groups]; absent →
  /// both null (no guessed provider, no synthesized row).
  (ModelProviderGroup?, ModelInfo?) _resolveCurrent(
    List<ModelProviderGroup> groups,
    ModelSelection? current,
  ) {
    if (current == null) return (null, null);
    for (final ModelProviderGroup g in groups) {
      for (final ModelInfo m in g.models) {
        if (g.id == current.provider && m.id == current.model) return (g, m);
      }
    }
    return (null, null);
  }

  void _openMenu(ModelDirectoryState state) {
    setState(() => _pane = _ModelPane.root);
    if (state.status == 'idle' || state.status == 'error') {
      ref
          .read(modelDirectoryProvider(widget.sessionId).notifier)
          .load()
          .catchError((Object _) => <String, dynamic>{});
    }
    _portal.show();
  }

  Future<void> _select(ModelSelection selection) async {
    try {
      await ref
          .read(modelDirectoryProvider(widget.sessionId).notifier)
          .select(selection);
      // Accepted selections close the menu (React settleSelection(true)).
      if (!mounted || !_portal.isShowing) return;
      _portal.hide();
    } catch (_) {
      // Rejection keeps the menu open; the in-menu error strip carries the
      // directory's failure text with its Retry (load) affordance.
    }
  }

  @override
  Widget build(BuildContext context) {
    final DswAliases aliases = widget.aliases;
    final ModelDirectoryState dirState = ref.watch(
      modelDirectoryProvider(widget.sessionId),
    );
    final (ModelProviderGroup?, ModelInfo?) resolved = _resolveCurrent(
      dirState.groups,
      dirState.current,
    );
    final ModelInfo? currentModel = resolved.$2;
    final ModelReasoning? reasoning = currentModel?.reasoning;
    final String? effectiveEffort =
        dirState.current?.reasoningEffort ?? reasoning?.defaultEffort;
    String? effortLabel;
    if (reasoning != null) {
      if (effectiveEffort == null) {
        effortLabel = 'Provider default';
      } else {
        final match = reasoning.efforts
            .where((e) => e.id == effectiveEffort)
            .firstOrNull;
        effortLabel = match?.name ?? effectiveEffort;
      }
    }
    final String modelLabel =
        currentModel?.name ?? dirState.current?.model ?? 'Select model';

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (BuildContext overlayContext) => DshMenuScaffold(
        onClose: () => _portal.hide(),
        barrierColor: Colors.black.withValues(alpha: 0.12),
        child: LayoutBuilder(
          builder: (BuildContext ctx, BoxConstraints _) {
            final RenderBox? box =
                _anchorKey.currentContext?.findRenderObject() as RenderBox?;
            final Offset anchor =
                box?.localToGlobal(Offset.zero) ?? Offset.zero;
            final Size size = box?.size ?? const Size(120, 28);
            // Directional placement (React's flip behavior): the composer chip
            // sits near the viewport bottom, so the menu opens UPWARD from the
            // chip when the space below cannot hold it; a high anchor keeps the
            // downward placement.
            final MediaQueryData media = MediaQuery.of(ctx);
            final bool openUpward =
                media.size.height - (anchor.dy + size.height) < 220;
            return Stack(
              children: [
                Positioned(
                  top: openUpward ? null : anchor.dy + size.height + 8,
                  bottom: openUpward ? media.size.height - anchor.dy + 8 : null,
                  right: (media.size.width - anchor.dx - size.width).toDouble(),
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                    color: aliases.specificMenu,
                    child: Container(
                      width: 320,
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(DswTokens.radiusMd),
                        border: Border.all(color: aliases.borderL2),
                      ),
                      child: _buildMenuBody(
                        dirState,
                        currentModel,
                        reasoning,
                        effectiveEffort,
                        modelLabel,
                        effortLabel,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      child: Container(
        key: _anchorKey,
        padding: const EdgeInsets.symmetric(horizontal: DswTokens.spaceSm),
        decoration: BoxDecoration(
          color: aliases.specificSelector,
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          border: Border.all(color: aliases.borderL2),
        ),
        child: InkWell(
          onTap: widget.enabled
              ? () => _openMenu(
                  ref.read(modelDirectoryProvider(widget.sessionId)),
                )
              : null,
          borderRadius: BorderRadius.circular(DswTokens.radiusFull),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.memory_outlined,
                size: 12,
                color: aliases.labelSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.compact ? 72 : 160,
                  ),
                  child: Text(
                    modelLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      fontWeight: FontWeight.w600,
                      color: currentModel == null
                          ? aliases.labelTertiary
                          : aliases.labelPrimary,
                    ),
                  ),
                ),
              ),
              if (effortLabel != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: aliases.bgOverlay,
                      borderRadius: BorderRadius.circular(DswTokens.radiusFull),
                    ),
                    child: Text(
                      effortLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: aliases.labelSecondary,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 14, color: aliases.labelTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuBody(
    ModelDirectoryState dirState,
    ModelInfo? currentModel,
    ModelReasoning? reasoning,
    String? effectiveEffort,
    String modelLabel,
    String? effortLabel,
  ) {
    final DswAliases aliases = widget.aliases;
    final bool busy = dirState.status == 'selecting';
    final Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Row(
        children: [
          // Long drill titles (deep model names) collapse instead of pushing
          // the close button out of the card.
          Expanded(
            child: Text(
              _paneTitle(modelLabel, effortLabel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                fontWeight: FontWeight.w600,
                color: aliases.labelPrimary,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: aliases.labelTertiary),
            onPressed: () => _portal.hide(),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        Divider(height: 1, color: aliases.borderL1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              // Load-failure strip (React lastActionRef 'load' surface): its
              // Retry re-runs the catalog load; selection rejections keep the
              // directory error visible here instead.
              if ((dirState.status == 'error' || _pane != _ModelPane.root) &&
                  dirState.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Load failed: ${dirState.error}',
                          style: TextStyle(
                            fontSize: DswTokens.fontSizeXxs12,
                            color: aliases.stateErrorPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(
                              modelDirectoryProvider(widget.sessionId).notifier,
                            )
                            .load()
                            .catchError((Object _) => <String, dynamic>{}),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              for (final failure in dirState.failures)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  child: Text(
                    '${failure is Map ? failure['name'] ?? failure['id'] : failure} — failed to load',
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeXxs12,
                      color: aliases.labelCaption,
                    ),
                  ),
                ),
              if (dirState.status == 'loading')
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: aliases.labelTertiary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Loading…',
                        style: TextStyle(
                          fontSize: DswTokens.fontSizeXxs12,
                          color: aliases.labelSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ..._paneChildren(
                  dirState,
                  reasoning,
                  effectiveEffort,
                  busy,
                  modelLabel,
                  effortLabel,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The drilled/root rows for the active pane — `ModelSelect.tsx` panes:
  ///
  /// * root: the Model / Effort drill-in cells; Effort only while the exact
  ///   current model advertises reasoning.
  /// * model: provider-grouped sections over the live catalog ONLY — groups
  ///   empty + ready renders the explicit empty row ("unavailable catalog
  ///   must not silently synthesize"); rows disable on a non-routable
  ///   directory or while a selection settles.
  /// * effort: provider-default row first when the model does not pin one,
  ///   then the advertised efforts; picks preserve provider/model
  ///   (`chooseEffort`).
  List<Widget> _paneChildren(
    ModelDirectoryState dirState,
    ModelReasoning? reasoning,
    String? effectiveEffort,
    bool busy,
    String modelLabel,
    String? effortLabel,
  ) {
    final DswAliases aliases = widget.aliases;
    switch (_pane) {
      case _ModelPane.root:
        return [
          _paneRow(
            label: 'Model',
            value: modelLabel,
            onTap: () => setState(() => _pane = _ModelPane.model),
          ),
          if (reasoning != null)
            _paneRow(
              label: 'Effort',
              value: effortLabel ?? '—',
              onTap: () => setState(() => _pane = _ModelPane.effort),
            ),
        ];
      case _ModelPane.model:
        return [
          if (dirState.groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No models available',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelSecondary,
                ),
              ),
            ),
          for (final ModelProviderGroup group in dirState.groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                group.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: aliases.labelCaption,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            for (final ModelInfo m in group.models)
              _optionRow(
                title: m.name,
                subtitle: m.description,
                selected:
                    dirState.current?.provider == group.id &&
                    dirState.current?.model == m.id,
                enabled: widget.enabled && !busy && dirState.routable != false,
                onPick: () => _select(
                  ModelSelection(
                    provider: group.id,
                    model: m.id,
                    // Supported models start at their advertised default
                    // effort; unsupported ones clear any stale effort (null
                    // is omitted on the wire).
                    reasoningEffort: m.reasoning?.defaultEffort,
                  ),
                ),
              ),
          ],
        ];
      case _ModelPane.effort:
        final ModelSelection? current = dirState.current;
        return [
          if (reasoning == null || current == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No efforts advertised',
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelSecondary,
                ),
              ),
            )
          else ...[
            if (reasoning.defaultEffort == null)
              _optionRow(
                title: 'Provider default',
                selected: effectiveEffort == null,
                enabled: !busy,
                onPick: () => _select(
                  ModelSelection(
                    provider: current.provider,
                    model: current.model,
                    reasoningEffort: null,
                  ),
                ),
              ),
            for (final e in reasoning.efforts)
              _optionRow(
                title: e.name,
                subtitle: e.description,
                selected: effectiveEffort == e.id,
                enabled: !busy,
                onPick: () => _select(
                  ModelSelection(
                    provider: current.provider,
                    model: current.model,
                    reasoningEffort: e.id,
                  ),
                ),
              ),
            if (reasoning.efforts.isEmpty && reasoning.defaultEffort != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No efforts advertised',
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.labelSecondary,
                  ),
                ),
              ),
          ],
        ];
    }
  }

  String _paneTitle(String modelLabel, String? effortLabel) => switch (_pane) {
    _ModelPane.root => 'Select model',
    _ModelPane.model => 'Model · $modelLabel',
    _ModelPane.effort => 'Effort · ${effortLabel ?? '—'}',
  };

  Widget _paneRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final DswAliases aliases = widget.aliases;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: DswTokens.fontSizeS14,
                color: aliases.labelPrimary,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DswTokens.fontSizeXxs12,
                  color: aliases.labelSecondary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: aliases.labelTertiary),
          ],
        ),
      ),
    );
  }

  Widget _optionRow({
    required String title,
    String? subtitle,
    required bool selected,
    required bool enabled,
    required VoidCallback onPick,
  }) {
    final DswAliases aliases = widget.aliases;
    return InkWell(
      onTap: enabled ? onPick : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DswTokens.fontSizeS14,
                      color: enabled
                          ? aliases.labelPrimary
                          : aliases.labelTertiary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: DswTokens.fontSizeXxs12,
                        color: aliases.labelSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 16, color: aliases.stateBusinessPrimary),
          ],
        ),
      ),
    );
  }
}
