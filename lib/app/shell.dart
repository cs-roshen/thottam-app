import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../features/harvest/data/harvest_providers.dart';
import '../core/access/access.dart';
import 'router.dart';
import 'session.dart';
import 'settings.dart';
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
    // the add sheet always offers a bill to a money writer and a note to a
    // daily-work writer; a role that writes neither gets no add button
    final access = ref.watch(accessProvider).value;
    final canAdd = [
      AccessClass.money,
      AccessClass.daily,
    ].any((c) => access?.canWrite(c) ?? true);
    // a money phone works out lot costs left by a supervisor's harvests
    ref.watch(lotCostSettlerProvider);
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
          onAdd: canAdd
              ? () => showThottamSheet<void>(
                  context,
                  builder: (context) => const QuickAddSheet(),
                )
              : null,
          addLabel: l10n.actionAdd,
        ),
      ),
    );
  }
}

/// Quick add sheet (screen 3). Tiles follow the pages switched on in
/// Settings and what the role may write.
class QuickAddSheet extends ConsumerWidget {
  const QuickAddSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final hidden = ref.watch(settingsProvider.select((s) => s.hiddenPages));
    final access = ref.watch(accessProvider).value;
    bool can(AccessClass c) => access?.canWrite(c) ?? true;
    Widget tile(
      IconData icon,
      String label,
      Color bg,
      Color fg, [
      String? path,
    ]) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      // the icon and its word are one target: farmers tap either
      child: InkWell(
        key: Key('quickAdd.${path ?? label}'),
        borderRadius: BorderRadius.circular(t.tileRadius),
        onTap: () {
          // the sheet's context goes when it closes: take the router first
          final router = GoRouter.of(context);
          Navigator.of(context).pop();
          if (path != null) router.push(path);
        },
        child: SizedBox(
          width: 96,
          child: Column(
            children: [
              TintIconTile(
                icon: icon,
                background: bg,
                foreground: fg,
                size: t.tintTileLarge,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
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
            if (can(AccessClass.money))
              tile(
                Icons.payments_outlined,
                l10n.quickAddExpense,
                t.expenseTint,
                t.onExpenseTint,
                '/add/expense',
              ),
            if (can(AccessClass.daily) && !hidden.contains('labour'))
              tile(
                Icons.groups_outlined,
                l10n.labourTitle,
                t.infoTint,
                t.onInfoTint,
                '/add/labour',
              ),
            if (can(AccessClass.daily) && !hidden.contains('harvest'))
              tile(
                Icons.agriculture_outlined,
                l10n.quickAddHarvest,
                t.primaryTint,
                t.primaryDark,
                '/add/harvest',
              ),
            if (can(AccessClass.money) && !hidden.contains('sell'))
              tile(
                Icons.sell_outlined,
                l10n.quickAddSale,
                t.accentTint,
                t.onAccentTint,
                '/add/sale',
              ),
            if (can(AccessClass.daily))
              tile(
                Icons.edit_note_outlined,
                l10n.quickAddNote,
                t.primaryTint,
                t.primaryDark,
                '/add/note',
              ),
          ],
        ),
      ],
    );
  }
}
