import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/prefs/settings_store.dart';
import 'theme/qingya_theme.dart';
import 'ui/pages/devices_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/welcome_page.dart';
import 'ui/shell/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final configured = ref.watch(settingsProvider.select((s) => s.isConfigured));

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: configured ? '/home' : '/welcome',
    refreshListenable: _SettingsRefresh(ref),
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/welcome' ||
          state.matchedLocation == '/setup';
      if (!configured && !loggingIn) return '/welcome';
      if (configured && state.matchedLocation == '/welcome') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (_, __) => const WelcomePage(),
      ),
      GoRoute(
        path: '/setup',
        builder: (_, __) => const SetupPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, __) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/devices',
                builder: (_, __) => const DevicesPage(),
                routes: [
                  GoRoute(
                    path: ':machineId',
                    builder: (_, state) => DeviceDetailPage(
                      machineId: state.pathParameters['machineId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _SettingsRefresh extends ChangeNotifier {
  _SettingsRefresh(this.ref) {
    ref.listen<bool>(
      settingsProvider.select((s) => s.isConfigured),
      (_, __) => notifyListeners(),
    );
  }

  final Ref ref;
}

class QingyaApp extends ConsumerWidget {
  const QingyaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '轻芽',
      debugShowCheckedModeBanner: false,
      theme: QingyaTheme.light(),
      darkTheme: QingyaTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
