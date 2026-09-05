/// Native application menu bar for desktop hosts.
///
/// macOS renders [PlatformMenuBar] as the real app menu; on other platforms
/// it is inert. The menus expose navigation and panel actions that already
/// exist as routes or providers — the bar invents no capability, it only
/// surfaces it where Mac users look for it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_provider.dart';
import '../../features/layout/layout_controller.dart';
import '../../routing/app_router.dart';

/// Wraps the app frame with the native menu bar on desktop.
class DshMenuBar extends ConsumerWidget {
  /// Creates the menu bar wrapper.
  const DshMenuBar({super.key, required this.child});

  /// The app content under the menus.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No current session, no session-scoped destinations.
    final String? sessionId = ref.watch(currentSessionIdProvider)?.value;

    void goSession(String leaf) {
      final String? sid = sessionId;
      if (sid == null) return;
      ref.read(appRouterProvider).go('/sessions/$sid/$leaf');
    }

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: 'Toggle Sidebar',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                alt: true,
              ),
              onSelected: () =>
                  ref.read(layoutProvider.notifier).toggleSidebar(),
            ),
            PlatformMenuItem(
              label: 'Command Palette',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyK,
                meta: true,
              ),
              onSelected: sessionId == null ? null : () => goSession('commands'),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Terminal',
          menus: [
            PlatformMenuItem(
              label: 'Open Console Terminal',
              onSelected: sessionId == null ? null : () => goSession('terminal'),
            ),
            PlatformMenuItem(
              label: 'Background Jobs',
              onSelected: sessionId == null ? null : () => goSession('jobs'),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
