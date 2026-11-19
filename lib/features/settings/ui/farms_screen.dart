import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../onboarding/ui/invites_screen.dart';
import '../data/settings_providers.dart';

/// Settings → Farms: the account's farms with its role on each, switch,
/// add a farm, and open invites with Join and Decline.
class FarmsScreen extends ConsumerWidget {
  const FarmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final farms = ref.watch(farmsProvider).value ?? const [];
    final invites = ref.watch(openInvitesProvider).value ?? const [];
    final open = ref.watch(farmIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsFarms)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          if (invites.isNotEmpty) ...[
            Text(l10n.farmsInvites, style: text.titleMedium),
            Text(l10n.invitesHint, style: text.bodySmall),
            for (final invite in invites) ...[
              SizedBox(height: t.cardGap),
              InviteCard(
                invite: invite,
                onAnswered: () => ref.invalidate(openInvitesProvider),
              ),
            ],
            SizedBox(height: t.cardGap * 2),
          ],
          for (final f in farms) ...[
            ThottamCard(
              key: Key('farm.${f.id}'),
              onTap: f.id == open
                  ? null
                  : () async {
                      await ref.read(sessionProvider.notifier).openFarm(f.id);
                      if (!context.mounted) return;
                      showToast(context, l10n.farmsOpened(f.name));
                      context.go('/home');
                    },
              child: Row(
                children: [
                  TintIconTile(
                    icon: Icons.home_work_outlined,
                    background: t.primaryTint,
                    foreground: t.primaryDark,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name, style: text.titleMedium),
                        Text(l10n.roleName(f.role), style: text.bodySmall),
                      ],
                    ),
                  ),
                  if (f.id == open)
                    Pill(
                      label: l10n.farmsOpenNow,
                      background: t.primaryPill,
                      foreground: t.primaryDark,
                    )
                  else
                    Icon(Icons.chevron_right, color: t.muted),
                ],
              ),
            ),
            SizedBox(height: t.cardGap),
          ],
          OutlineButton(
            key: const Key('farms.add'),
            label: l10n.farmsAdd,
            icon: Icons.add,
            onPressed: () => context.go('/more/settings/farms/new'),
          ),
        ],
      ),
    );
  }
}
