import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/desktop/window_controller.dart';
import 'data/prefs/settings_store.dart';
import 'domain/models.dart';
import 'theme/qingya_theme.dart';
import 'ui/desktop/desktop_host.dart';
import 'ui/pages/devices_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/providers_page.dart';
import 'ui/pages/session_detail_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/usage_page.dart';
import 'ui/pages/welcome_page.dart';
import 'ui/shell/main_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final configured = ref.watch(settingsProvider.select((s) => s.isConfigured));

  return GoRouter(
    navigatorKey: rootNavigatorKey,
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
                        parentNavigatorKey: rootNavigatorKey,
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

  void _openSession(WidgetRef ref, Session session) {
    unawaited(QingyaWindowController.instance.showMain());
    final router = ref.read(routerProvider);
    final path =
        '/sessions/${session.machineId}/${session.agent}/${Uri.encodeComponent(session.sessionId)}';
    // 先落到首页再 push，保证返回键有栈可退（go 会清栈导致卡在详情）。
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      router.go('/home');
      Future<void>.delayed(const Duration(milliseconds: 16), () {
        router.push(path);
      });
    });
  }

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
      builder: (context, child) {
        // Windows：避免异常 text scale 把字形栅格拉糊；仍尊重 1.0 附近系统缩放。
        final mq = MediaQuery.of(context);
        final scale = mq.textScaler.scale(14) / 14.0;
        final clamped = scale.clamp(0.9, 1.25);
        final content = DesktopHost(
          onOpenSession: (session) => _openSession(ref, session),
          child: child ?? const SizedBox.shrink(),
        );
        if (clamped == scale) return content;
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(clamped)),
          child: content,
        );
      },
    );
  }
}
