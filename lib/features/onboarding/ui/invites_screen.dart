import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/sync/sync_server.dart';
import '../../../l10n/app_localizations.dart';
import '../data/onboarding_providers.dart';

/// Open invites found at sign-in, each with Join and Decline. Nobody is
/// added to a farm until they tap Join (owner decision, 2026-11-19).
class InvitesScreen extends ConsumerStatefulWidget {
  const InvitesScreen({super.key});

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  String? _busy;

  Future<void> _answer(Invite invite, {required bool join}) async {
    final server = ref.read(syncServerProvider);
    final engine = ref.read(syncEngineProvider);
    if (server == null || engine == null) return;
    setState(() => _busy = invite.id);
    try {
      if (join) {
        final farm = await ref
            .read(onboardingRepositoryProvider)
            .join(server, engine, invite);
        if (farm != null) {
          await ref.read(sessionProvider.notifier).openFarm(farm);
        }
      } else {
        await server.declineInvite(invite.id);
      }
      // gone either way: answered now, or no longer open
      ref.read(pendingInvitesProvider.notifier).remove(invite.id);
    } on SyncUnavailable {
      if (mounted) {
        showToast(context, AppLocalizations.of(context).inviteNeedsConnection);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final invites = ref.watch(pendingInvitesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.invitesTitle)),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(t.screenPadding),
          children: [
            Text(l10n.invitesHint, style: text.bodyMedium),
            for (final invite in invites) ...[
              SizedBox(height: t.cardGap),
              ThottamCard(
                key: Key('invite.${invite.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(invite.farmName, style: text.titleMedium),
                    Text(l10n.inviteRole(invite.role), style: text.bodyMedium),
                    if (invite.invitedBy case final by?)
                      Text(l10n.inviteFrom(by), style: text.bodySmall),
                    SizedBox(height: t.cardGap),
                    Row(
                      children: [
                        Expanded(
                          child: OutlineButton(
                            key: Key('invite.${invite.id}.decline'),
                            label: l10n.inviteDecline,
                            onPressed: _busy == null
                                ? () => _answer(invite, join: false)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryButton(
                            key: Key('invite.${invite.id}.join'),
                            label: l10n.inviteJoin,
                            onPressed: _busy == null
                                ? () => _answer(invite, join: true)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
