import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/access/access.dart';
import '../features/land/ui/cycle_form_screen.dart';
import '../features/land/ui/land_screen.dart';
import '../features/land/ui/plot_detail_screen.dart';
import '../features/land/ui/plot_form_screen.dart';
import '../features/onboarding/ui/invites_screen.dart';
import '../features/onboarding/ui/setup_screen.dart';
import '../features/onboarding/ui/sign_in_screen.dart';
import '../features/onboarding/ui/welcome_screen.dart';
import '../l10n/app_localizations.dart';
import 'session.dart';
import 'shell.dart';
import 'widgets/widgets.dart';

/// Whether the signed-in person's role opens money screens; true until their
/// membership has loaded, so the bar does not jump at start.
final canSeeMoneyProvider = Provider<bool>(
  (ref) => ref.watch(accessProvider).value?.canRead(AccessClass.money) ?? true,
);

/// Branch order in the shell; the bar hides Money when the role cannot open
/// it, so tab positions are mapped through [AppShell].
enum ShellTab { home, land, money, more }

/// Where each sign-in step lives; the app goes there until the step is done.
const _gatePaths = {
  Gate.signedOut: '/welcome',
  Gate.firstSync: '/signin',
  Gate.invites: '/invites',
  Gate.setup: '/setup',
};

/// The path the app must show instead of [location], or null to stay.
String? gateRedirect(Gate gate, String location, {required bool canSeeMoney}) {
  if (gate == Gate.ready) {
    if (_gatePaths.values.contains(location)) return '/home';
    return !canSeeMoney && location.startsWith('/money') ? '/home' : null;
  }
  // before sign-in the welcome screen leads to the sign-in step
  if (gate == Gate.signedOut && location == '/signin') return null;
  final path = _gatePaths[gate]!;
  return location == path ? null : path;
}

final routerProvider = Provider<GoRouter>((ref) {
  // the router stays; a change of gate or role only asks it to look again
  final refresh = ValueNotifier(0);
  ref.listen(gateProvider, (_, _) => refresh.value++);
  ref.listen(canSeeMoneyProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) => gateRedirect(
      ref.read(gateProvider),
      state.matchedLocation,
      canSeeMoney: ref.read(canSeeMoneyProvider),
    ),
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/invites', builder: (_, _) => const InvitesScreen()),
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      // stand-ins until their tasks: History (C7), expense (C4), harvest (C5)
      for (final (path, title, icon)
          in <(String, String Function(AppLocalizations), IconData)>[
            ('/history', (l) => l.historyTitle, Icons.history),
            ('/add/expense', (l) => l.expenseTitle, Icons.payments_outlined),
            ('/add/harvest', (l) => l.harvestTitle, Icons.agriculture_outlined),
          ])
        GoRoute(
          path: path,
          builder: (_, _) => PlaceholderScreen(title: title, icon: icon),
        ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          _branch('/home', (l) => l.navHome, Icons.home_outlined),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/land',
                builder: (_, _) => const LandScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, _) => const PlotFormScreen(),
                  ),
                  GoRoute(
                    path: ':plot',
                    builder: (_, s) =>
                        PlotDetailScreen(plotId: s.pathParameters['plot']!),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (_, s) =>
                            PlotFormScreen(plotId: s.pathParameters['plot']),
                      ),
                      GoRoute(
                        path: 'crop/new',
                        builder: (_, s) =>
                            CycleFormScreen(plotId: s.pathParameters['plot']!),
                      ),
                      GoRoute(
                        path: 'crop/:cycle',
                        builder: (_, s) => CycleFormScreen(
                          plotId: s.pathParameters['plot']!,
                          cycleId: s.pathParameters['cycle'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _branch(
            '/money',
            (l) => l.moneyTitle,
            Icons.account_balance_wallet_outlined,
          ),
          _branch(
            '/more',
            (l) => l.navMore,
            Icons.more_horiz,
            routes: [
              if (kDebugMode)
                GoRoute(
                  path: 'gallery',
                  builder: (context, state) => const WidgetGalleryScreen(),
                ),
            ],
            extra: (context, l) => [
              if (kDebugMode)
                ListTile(
                  key: const Key('more.gallery'),
                  leading: const Icon(Icons.widgets_outlined),
                  title: Text(l.debugWidgetGallery),
                  onTap: () => context.go('/more/gallery'),
                ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

StatefulShellBranch _branch(
  String path,
  String Function(AppLocalizations) title,
  IconData icon, {
  List<RouteBase> routes = const [],
  List<Widget> Function(BuildContext, AppLocalizations)? extra,
}) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        builder: (context, state) =>
            PlaceholderScreen(title: title, icon: icon, extra: extra),
        routes: routes,
      ),
    ],
  );
}

/// Stands in for each tab's real screen until its feature task.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    this.extra,
  });

  final String Function(AppLocalizations) title;
  final IconData icon;
  final List<Widget> Function(BuildContext, AppLocalizations)? extra;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title(l10n))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          EmptyState(
            icon: icon,
            title: title(l10n),
            message: l10n.morePageComingSoon,
          ),
          ...?extra?.call(context, l10n),
        ],
      ),
    );
  }
}
