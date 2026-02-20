import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers/locale_provider.dart';
import 'features/camera/camera_screen.dart';
import 'features/import/import_screen.dart';
import 'features/import_binary/import_binary_screen.dart';
import 'features/settings/settings_screen.dart';
import 'l10n/generated/app_localizations.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/import',
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/import',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ImportScreen(),
            ),
          ),
          GoRoute(
            path: '/binary',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ImportBinaryScreen(),
            ),
          ),
          GoRoute(
            path: '/camera',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CameraScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});

class CimBarApp extends ConsumerWidget {
  const CimBarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'CimBar Scanner',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
