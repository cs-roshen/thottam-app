import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme/tokens.dart';
import 'widgets/widgets.dart';

/// Bottom bar around the tab branches. Back on a tab's root goes to Home;
/// back on Home leaves the app.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canSeeMoney = ref.watch(canSeeMoneyProvider);
    final branches = [
      ShellTab.home,
      ShellTab.land,
      if (canSeeMoney) ShellTab.money,
      ShellTab.more,
    ];
    NavTab tab(ShellTab t) => switch (t) {
      ShellTab.home => NavTab(Icons.home_outlined, l10n.navHome),
      ShellTab.land => NavTab(Icons.landscape_outlined, l10n.navLand),
      ShellTab.money => NavTab(
        Icons.account_balance_wallet_outlined,
        l10n.navMoney,
      ),
      ShellTab.more => NavTab(Icons.more_horiz, l10n.navMore),
    };
    final onHome = shell.currentIndex == ShellTab.home.index;
    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(ShellTab.home.index);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: ThottamBottomNav(
          key: const Key('shell.nav'),
          tabs: [for (final b in branches) tab(b)],
          current: branches.indexWhere((b) => b.index == shell.currentIndex),
          onTab: (i) => shell.goBranch(
            branches[i].index,
            // Tapping the open tab again returns to its first screen.
            initialLocation: branches[i].index == shell.currentIndex,
          ),
          onAdd: () => showThottamSheet<void>(
            context,
            builder: (context) => const QuickAddSheet(),
          ),
          addLabel: l10n.actionAdd,
        ),
      ),
    );
  }
}

/// Placeholder quick add sheet; tiles open their entry screens from C9.
class QuickAddSheet extends StatelessWidget {
  const QuickAddSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    Widget tile(IconData icon, String label, Color bg, Color fg) => SizedBox(
      width: 96,
      child: Column(
        children: [
          TintIconTile(
            icon: icon,
            background: bg,
            foreground: fg,
            size: t.tintTileLarge,
            label: label,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.quickAddTitle, style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: t.cardGap),
        Wrap(
          spacing: t.cardGap,
          runSpacing: t.cardGap,
          children: [
            tile(
              Icons.payments_outlined,
              l10n.quickAddExpense,
              t.expenseTint,
              t.onExpenseTint,
            ),
            tile(
              Icons.groups_outlined,
              l10n.labourTitle,
              t.infoTint,
              t.onInfoTint,
            ),
            tile(
              Icons.agriculture_outlined,
              l10n.quickAddHarvest,
              t.primaryTint,
              t.primaryDark,
            ),
            tile(
              Icons.sell_outlined,
              l10n.quickAddSale,
              t.accentTint,
              t.onAccentTint,
            ),
            tile(
              Icons.edit_note_outlined,
              l10n.quickAddNote,
              t.primaryTint,
              t.primaryDark,
            ),
          ],
        ),
      ],
    );
  }
}
