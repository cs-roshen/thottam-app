import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/access/access.dart';
import '../../../l10n/app_localizations.dart';
import '../data/settings_providers.dart';
import 'pages.dart';

/// Screen 7: language, text size, pages and Home cards on or off, reset,
/// farms, members (owner only), sync status and the account.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final owner =
        ref.watch(accessProvider).value?.canWrite(AccessClass.members) ?? false;
    final status = ref.watch(syncStatusProvider).value;
    final account = ref.watch(sessionProvider).account;

    Widget section(String title, List<Widget> children, {String? hint}) =>
        Padding(
          padding: EdgeInsets.only(bottom: t.cardGap),
          child: ThottamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: text.titleMedium),
                if (hint != null) Text(hint, style: text.bodySmall),
                const SizedBox(height: 4),
                ...children,
              ],
            ),
          ),
        );
    Widget link(Key key, String title, String hint, String path) => ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      minTileHeight: t.listRowMin,
      title: Text(title, style: text.bodyLarge),
      subtitle: Text(hint, style: text.bodySmall),
      trailing: Icon(Icons.chevron_right, color: t.muted),
      onTap: () => context.go(path),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          section(l10n.settingsLanguage, [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (choice, label) in [
                  (LanguageChoice.malayalam, l10n.languageMalayalam),
                  (LanguageChoice.english, l10n.languageEnglish),
                  (LanguageChoice.mixed, l10n.languageMixed),
                ])
                  ChoiceChipX(
                    key: Key('settings.language.${choice.name}'),
                    label: label,
                    selected: settings.language == choice,
                    onSelected: (_) => notifier.setLanguage(choice),
                  ),
              ],
            ),
            SwitchRow(
              key: const Key('settings.largeText'),
              title: l10n.settingsLargeText,
              subtitle: l10n.settingsLargeTextHint,
              value: settings.largeText,
              onChanged: notifier.setLargeText,
            ),
          ]),
          section(l10n.settingsPages, hint: l10n.settingsPagesHint, [
            for (final p in appPages)
              SwitchRow(
                key: Key('settings.page.${p.code}'),
                title: p.label(l10n),
                value: !settings.hiddenPages.contains(p.code),
                onChanged: (v) => notifier.setPageShown(p.code, v),
              ),
          ]),
          section(l10n.settingsHomeCards, [
            for (final (code, label) in [
              ('profit', l10n.homeCardProfit),
              ('price', l10n.homeCardPrice),
              ('tasks', l10n.homeCardTasks),
              ('dues', l10n.homeCardDues),
            ])
              SwitchRow(
                key: Key('settings.card.$code'),
                title: label,
                value: !settings.hiddenCards.contains(code),
                onChanged: (v) => notifier.setCardShown(code, v),
              ),
          ]),
          Padding(
            padding: EdgeInsets.only(bottom: t.cardGap),
            child: OutlineButton(
              key: const Key('settings.reset'),
              label: l10n.actionResetDefault,
              onPressed: () {
                notifier.resetVisibility();
                showToast(context, l10n.toastResetDone);
              },
            ),
          ),
          section(l10n.settingsFarms, [
            link(
              const Key('settings.farms'),
              l10n.settingsFarms,
              l10n.settingsFarmsHint,
              '/more/settings/farms',
            ),
            if (owner)
              link(
                const Key('settings.members'),
                l10n.settingsMembers,
                l10n.settingsMembersHint,
                '/more/settings/members',
              ),
          ]),
          section(l10n.settingsSync, [
            if (status != null) SyncStatusLine(status: status),
          ]),
          section(l10n.settingsAccount, [
            if (account != null) ...[
              if (account.name.isNotEmpty)
                Text(account.name, style: text.bodyLarge),
              if (account.email case final email?)
                Text(email, style: text.bodySmall),
            ],
            const SizedBox(height: 8),
            OutlineButton(
              key: const Key('settings.signOut'),
              label: l10n.settingsSignOut,
              icon: Icons.logout,
              onPressed: () => _signOut(context, ref, status?.waiting ?? 0),
            ),
          ]),
        ],
      ),
    );
  }

  /// Signing out with changes not yet uploaded warns first; they stay on
  /// the phone, in that user's own database, until they sync.
  Future<void> _signOut(
    BuildContext context,
    WidgetRef ref,
    int waiting,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (waiting > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.signOutWaitingTitle),
          content: Text(l10n.signOutWaitingBody(waiting)),
          actions: [
            TextButton(
              key: const Key('signOut.cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.actionCancel),
            ),
            TextButton(
              key: const Key('signOut.confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.settingsSignOut),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(sessionProvider.notifier).signOut();
  }
}
