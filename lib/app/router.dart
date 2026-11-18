import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'shell.dart';
import 'widgets/widgets.dart';

// shortcut: everyone sees Money until roles exist (B6, D3); then read the
// signed-in member's role here.
final canSeeMoneyProvider = Provider<bool>((ref) => true);

/// Branch order in the shell; the bar hides Money when the role cannot open
/// it, so tab positions are mapped through [AppShell].
enum ShellTab { home, land, money, more }

final routerProvider = Provider<GoRouter>((ref) {
  final canSeeMoney = ref.watch(canSeeMoneyProvider);
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) =>
        !canSeeMoney && state.matchedLocation.startsWith('/money')
        ? '/home'
        : null,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          _branch('/home', (l) => l.navHome, Icons.home_outlined),
          _branch('/land', (l) => l.landTitle, Icons.landscape_outlined),
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
