import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/access/access.dart';
import '../features/expenses/ui/expense_screen.dart';
import '../features/harvest/ui/harvest_screen.dart';
import '../features/harvest/ui/lot_screen.dart';
import '../features/history/ui/history_screen.dart';
import '../features/home/ui/home_screen.dart';
import '../features/home/ui/note_screen.dart';
import '../features/labour/ui/labour_screen.dart';
import '../features/money/ui/money_screen.dart';
import '../features/sales/ui/buyers_screen.dart';
import '../features/sales/ui/sell_screen.dart';
import '../features/labour/ui/team_screen.dart';
import '../features/land/ui/cycle_form_screen.dart';
import '../features/land/ui/land_screen.dart';
import '../features/land/ui/plot_detail_screen.dart';
import '../features/land/ui/plot_form_screen.dart';
import '../features/onboarding/ui/invites_screen.dart';
import '../features/prices/ui/prices_screen.dart';
import '../features/settings/ui/farms_screen.dart';
import '../features/settings/ui/members_screen.dart';
import '../features/settings/ui/more_screen.dart';
import '../features/settings/ui/my_lists_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/onboarding/ui/setup_screen.dart';
import '../features/onboarding/ui/sign_in_screen.dart';
import '../features/onboarding/ui/welcome_screen.dart';
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
      GoRoute(
        path: '/add/expense',
        builder: (_, s) => ExpenseScreen(plotId: s.uri.queryParameters['plot']),
      ),
      GoRoute(
        path: '/add/harvest',
        builder: (_, s) => HarvestScreen(
          plotId: s.uri.queryParameters['plot'],
          editId: s.uri.queryParameters['edit'],
        ),
      ),
      GoRoute(
        path: '/harvest/:id',
        builder: (_, s) => LotScreen(harvestId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/add/sale',
        builder: (_, s) => SellScreen(lotId: s.uri.queryParameters['lot']),
      ),
      GoRoute(path: '/sales/buyers', builder: (_, _) => const BuyersScreen()),
      GoRoute(
        path: '/sales/buyer/:id',
        builder: (_, s) => BuyerScreen(buyerId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/history',
        builder: (_, s) => HistoryScreen(plotId: s.uri.queryParameters['plot']),
      ),
      GoRoute(
        path: '/history/:entity/:id',
        builder: (_, s) => HistoryScreen(
          entity: s.pathParameters['entity'],
          entityId: s.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/add/labour',
        builder: (_, s) => LabourScreen(plotId: s.uri.queryParameters['plot']),
      ),
      GoRoute(path: '/labour/team', builder: (_, _) => const TeamScreen()),
      GoRoute(
        path: '/add/note',
        builder: (_, s) => NoteScreen(plotId: s.uri.queryParameters['plot']),
      ),
      GoRoute(
        path: '/labour/worker/:id',
        builder: (_, s) => LedgerScreen(workerId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/labour/group/:id',
        builder: (_, s) => LedgerScreen(groupId: s.pathParameters['id']),
      ),
      GoRoute(path: '/prices', builder: (_, _) => const PricesScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
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
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/money', builder: (_, _) => const MoneyScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (_, _) => const MoreScreen(),
                routes: [
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) => const SettingsScreen(),
                    routes: [
                      GoRoute(
                        path: 'farms',
                        builder: (_, _) => const FarmsScreen(),
                        routes: [
                          GoRoute(
                            path: 'new',
                            builder: (_, _) => const SetupScreen(addFarm: true),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'members',
                        builder: (_, _) => const MembersScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'lists',
                    builder: (_, _) => const MyListsScreen(),
                  ),
                  if (kDebugMode)
                    GoRoute(
                      path: 'gallery',
                      builder: (context, state) => const WidgetGalleryScreen(),
                    ),
                ],
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
