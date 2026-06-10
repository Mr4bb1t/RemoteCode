/// RDC — App Principal com GoRouter
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/settings_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/projects/projects_page.dart';
import 'features/workspace/workspace_page.dart';

final _router = GoRouter(
  initialLocation: '/settings',
  redirect: (context, state) async {
    // Sem redirect dinâmico aqui — o authProvider cuida via redirect
    return null;
  },
  routes: [
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (ctx, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/dashboard',
      name: 'dashboard',
      builder: (ctx, state) => const DashboardPage(),
    ),
    GoRoute(
      path: '/projects',
      name: 'projects',
      builder: (ctx, state) => const ProjectsPage(),
    ),
    GoRoute(
      path: '/workspace/:projectId',
      name: 'workspace',
      builder: (ctx, state) {
        final id = int.parse(state.pathParameters['projectId']!);
        final name = state.uri.queryParameters['name'] ?? 'Projeto';
        return WorkspacePage(projectId: id, projectName: name);
      },
    ),
  ],
);

class RdcApp extends ConsumerWidget {
  const RdcApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return MaterialApp.router(
      title: 'Remote Dev Control',
      debugShowCheckedModeBanner: false,
      theme: RdcTheme.darkTheme,
      routerConfig: _router,
    );
  }
}
