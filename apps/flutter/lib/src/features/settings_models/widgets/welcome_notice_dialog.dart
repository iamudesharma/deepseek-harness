import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/connection_client.dart';
import '../../../core/services/runtime_services.dart'
    show LocaleBindOnWidgetRef;
import '../../../plugins/settings/children/models/models_settings_plugin.dart'
    show kModelsNamespace;
import '../../../plugins/settings/children/models/models_settings_service.dart'
    show WelcomeNoticeScope;
import '../../../theme/app_theme.dart';
import '../../../widgets/primitives/ds_button.dart';
import '../../../widgets/primitives/ds_modal.dart';

/// Product-wide, versioned internal-testing notice — mirrors
/// `WelcomeNotice.tsx` + `OnboardingModal.tsx`.
///
/// Renders the blocking welcome modal until the shipped copy version is
/// acknowledged (`ui-onboarding.welcomeNoticeVersion`, loopback-persisted on
/// the Host with a process-local remote fallback inside the scope face —
/// see `welcome-store.ts`). Renders nothing while the step is undecided or
/// acknowledged. Dismissal is acknowledgement-only: the mask/Escape handler
/// is a no-op, mirroring `OnboardingModal`'s lack of implicit dismiss.
class WelcomeNoticeDialog extends ConsumerStatefulWidget {
  const WelcomeNoticeDialog({super.key});

  @override
  ConsumerState<WelcomeNoticeDialog> createState() =>
      _WelcomeNoticeDialogState();
}

class _WelcomeNoticeDialogState extends ConsumerState<WelcomeNoticeDialog> {
  late final WelcomeNoticeScope _welcome;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _welcome = WelcomeNoticeScope(ref.read(connectionClientProvider));
    _welcome.addListener(_onChange);
    _welcome.load();
  }

  @override
  void dispose() {
    _welcome.removeListener(_onChange);
    _welcome.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _acknowledge() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await _welcome.acknowledge();
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_welcome.settled || !_welcome.needsShow) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final DswAliases aliases =
        theme.extension<DswThemeExtension>()?.aliases ??
        (theme.brightness == Brightness.dark
            ? DswTokens.darkAliases
            : DswTokens.lightAliases);
    final t = ref.bindLocale(kModelsNamespace);
    final paragraphs = t('welcomeBody').split('\n\n');
    // Onboarding sheet chrome (OnboardingModal.module.css): width
    // min(600,100%), content max-height 100vh-48 with in-place scroll,
    // padding 28 (24 below 560px), title 20/28 w500, body margin-top 20.
    final media = MediaQuery.of(context);
    final maxContentHeight = (media.size.height - 48).clamp(
      0.0,
      double.infinity,
    );
    final narrow = media.size.width < 560;

    return DsModalOverlay(
      open: true,
      title: t('welcomeTitle'),
      // Blocking step: no implicit dismiss (React `OnboardingModal`).
      onClose: () {},
      headless: true,
      width: 600,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxContentHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(narrow ? 24 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('welcomeTitle'),
                style: TextStyle(
                  fontSize: 20,
                  height: 28 / 20,
                  fontWeight: FontWeight.w500,
                  color: aliases.labelPrimary,
                ),
              ),
              const SizedBox(height: 20),
              for (final paragraph in paragraphs) ...[
                Text(
                  paragraph,
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeS14,
                    height: DswTokens.lineHeightS14 / DswTokens.fontSizeS14,
                    color: aliases.labelPrimary,
                  ),
                ),
                const SizedBox(height: DswTokens.spaceSm),
              ],
              if (_failed)
                Text(
                  t('welcomeError'),
                  style: TextStyle(
                    fontSize: DswTokens.fontSizeXxs12,
                    color: aliases.stateErrorPrimary,
                  ),
                ),
              if (_failed) const SizedBox(height: DswTokens.spaceSm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DsButton(
                    variant: DsButtonVariant.primary,
                    label: t('welcomeContinue'),
                    loading: _saving,
                    onPressed: _saving ? null : _acknowledge,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
