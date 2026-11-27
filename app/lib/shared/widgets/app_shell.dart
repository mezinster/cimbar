import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import 'wide_layout.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  static const _tabs = ['/send', '/import', '/camera', '/files', '/settings'];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final idx = _tabs.indexWhere((t) => location.startsWith(t));
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final index = _currentIndex(context);

    final items = [
      (Icons.send_outlined, Icons.send, l10n.tabSend),
      (Icons.gif_box_outlined, Icons.gif_box, l10n.tabImport),
      (Icons.camera_alt_outlined, Icons.camera_alt, l10n.tabCamera),
      (Icons.folder_outlined, Icons.folder, l10n.tabFiles),
      (Icons.settings_outlined, Icons.settings, l10n.tabSettings),
    ];
    void go(int i) => context.go(_tabs[i]);

    if (isWide(context)) {
      return Scaffold(
        body: Row(children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: index,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.6,
              destinations: [
                for (final (icon, sel, label) in items)
                  NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: Text(label)),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: go,
        destinations: [
          for (final (icon, sel, label) in items)
            NavigationDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: label),
        ],
      ),
    );
  }
}
