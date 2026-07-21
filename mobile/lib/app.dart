import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/prefs/settings_store.dart';
import 'domain/models.dart';
import 'theme/qingya_theme.dart';
import 'ui/pages/devices_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/providers_page.dart';
import 'ui/pages/session_detail_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/usage_page.dart';
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
      GoRoute(
        path: '/sessions/:machineId/:agent/:sessionId',
        builder: (_, state) => SessionDetailPage(
          machineId: state.pathParameters['machineId']!,
          agent: state.pathParameters['agent']!,
          sessionId: state.pathParameters['sessionId']!,
        ),
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
                    routes: [
                      // Nested under device so back returns to session list;
                      // root navigator keeps full-screen (no tab bar).
                      GoRoute(
                        path: 'sessions/:agent/:sessionId',
                        parentNavigatorKey: _rootKey,
                        builder: (_, state) => SessionDetailPage(
                          machineId: state.pathParameters['machineId']!,
                          agent: state.pathParameters['agent']!,
                          sessionId: state.pathParameters['sessionId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'providers',
                        // Stay on the devices branch stack so back returns to
                        // DeviceDetail (not the device list). Avoid root-navigator
                        // push which drops intermediate pages and leaves fade ghosts.
                        pageBuilder: (context, state) {
                          return CustomTransitionPage<void>(
                            key: state.pageKey,
                            opaque: true,
                            transitionDuration: const Duration(milliseconds: 160),
                            reverseTransitionDuration:
                                const Duration(milliseconds: 140),
                            child: ProvidersPage(
                              machineId: state.pathParameters['machineId']!,
                            ),
                            transitionsBuilder:
                                (context, animation, secondaryAnimation, child) {
                              // Ignore secondaryAnimation to avoid residual ghosting
                              // of the previous route during pop.
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                                reverseCurve: Curves.easeInCubic,
                              );
                              return FadeTransition(
                                opacity: curved,
                                child: child,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/usage',
                builder: (_, __) => const UsagePage(),
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
  const QingyaApp({super.key, this.theme, this.darkTheme});

  /// Optional overrides (e.g. golden tests with real CJK fonts).
  final ThemeData? theme;
  final ThemeData? darkTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(
      settingsProvider.select((s) => s.themeMode),
    );
    return MaterialApp.router(
      title: '轻芽',
      debugShowCheckedModeBanner: false,
      theme: theme ?? QingyaTheme.light(),
      darkTheme: darkTheme ?? QingyaTheme.dark(),
      themeMode: switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      routerConfig: router,
    );
  }
}
