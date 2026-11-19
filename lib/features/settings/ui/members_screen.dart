import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/access/access.dart';
import '../../../l10n/app_localizations.dart';
import '../data/settings_providers.dart';
import '../data/settings_repository.dart';

/// Roles an owner gives; owner first only in the list of members.
const _roles = ['manager', 'supervisor', 'accountant', 'viewer'];

/// Areas a per-person permission covers in phase 1; members stay the
/// owner's alone.
const _areas = [
  AccessClass.setup,
  AccessClass.team,
  AccessClass.daily,
  AccessClass.stock,
  AccessClass.money,
  AccessClass.prices,
];

const _levels = ['none', 'read', 'write'];

/// Settings → Members (owner only): the farm's people and their roles,
/// per-person permissions, removing someone, and inviting by Google email.
/// The server applies each change once it syncs; a removed person loses
/// access there at once.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final owner =
        ref.watch(accessProvider).value?.canWrite(AccessClass.members) ?? false;
    final members = ref.watch(membersProvider).value ?? const [];
    final invites = ref.watch(farmInvitesProvider).value ?? const [];
    final me = ref.watch(userIdProvider);
    final repo = ref.watch(settingsRepositoryProvider);
    final myName = ref.watch(sessionProvider).account?.name.trim() ?? '';
    String name(MemberView m) {
      // my own profile may not be on the phone before the first sync
      final own = m.name.trim().isEmpty && m.userId == me ? myName : m.name;
      final n = own.trim().isEmpty ? l10n.membersUnknown : own.trim();
      return m.userId == me ? l10n.membersYou(n) : n;
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsMembers)),
      body: !owner
          ? const SizedBox.shrink()
          : ListView(
              padding: EdgeInsets.all(t.screenPadding),
              children: [
                for (final m in members) ...[
                  ThottamCard(
                    key: Key('member.${m.id}'),
                    onTap: m.userId == me || m.role == 'owner'
                        ? null
                        : () => showThottamSheet<void>(
                            context,
                            builder: (_) =>
                                _MemberSheet(memberId: m.id, name: name(m)),
                          ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name(m), style: text.titleMedium),
                              Text(
                                l10n.roleName(m.role),
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (m.userId != me && m.role != 'owner')
                          Icon(Icons.chevron_right, color: t.muted),
                      ],
                    ),
                  ),
                  SizedBox(height: t.cardGap),
                ],
                for (final i in invites) ...[
                  ThottamCard(
                    key: Key('invite.out.${i.id}'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i.email, style: text.titleMedium),
                              Text(
                                l10n.membersInvited(l10n.roleName(i.role)),
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: Key('invite.out.${i.id}.cancel'),
                          tooltip: l10n.membersCancelInvite,
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            final events = await repo.cancelInvite(i);
                            if (context.mounted) {
                              showUndoToast(
                                context,
                                l10n.toastSaved,
                                () => repo.undo(events),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: t.cardGap),
                ],
                OutlineButton(
                  key: const Key('members.add'),
                  label: l10n.membersAdd,
                  icon: Icons.person_add_alt,
                  onPressed: () => showThottamSheet<void>(
                    context,
                    builder: (_) => const _InviteSheet(),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet();

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _email = TextEditingController();
  String _role = 'supervisor';
  bool _showErrors = false;

  // the server checks the address again when the invite syncs
  bool get _emailOk =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_emailOk) {
      setState(() => _showErrors = true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(settingsRepositoryProvider);
    final events = await repo.invite(_email.text, _role);
    if (!mounted) return;
    // the toast first: the sheet's context goes when it closes
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.membersAdd, style: text.titleLarge),
        TextField(
          key: const Key('invite.email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.membersEmail,
            errorText: _showErrors && !_emailOk
                ? l10n.membersEmailInvalid
                : null,
          ),
          onChanged: (_) {
            if (_showErrors) setState(() {});
          },
        ),
        SizedBox(height: t.cardGap),
        Text(l10n.membersRole, style: text.bodySmall),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _roles)
              ChoiceChipX(
                key: Key('invite.role.$r'),
                label: l10n.roleName(r),
                selected: _role == r,
                onSelected: (_) => setState(() => _role = r),
              ),
          ],
        ),
        SizedBox(height: t.cardGap),
        Text(l10n.membersJoinHint, style: text.bodySmall),
        SizedBox(height: t.cardGap),
        PrimaryButton(
          key: const Key('invite.save'),
          label: l10n.actionSave,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// One member: role, each area's permission, and remove.
class _MemberSheet extends ConsumerWidget {
  const _MemberSheet({required this.memberId, required this.name});

  final String memberId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final repo = ref.watch(settingsRepositoryProvider);
    final m = (ref.watch(membersProvider).value ?? const [])
        .where((m) => m.id == memberId)
        .firstOrNull;
    if (m == null) return const SizedBox.shrink();
    return ListView(
      shrinkWrap: true,
      children: [
        Text(name, style: text.titleLarge),
        SizedBox(height: t.cardGap),
        Text(l10n.membersRole, style: text.bodySmall),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _roles)
              ChoiceChipX(
                key: Key('member.role.$r'),
                label: l10n.roleName(r),
                selected: m.role == r,
                onSelected: (_) => repo.setRole(m, r, name),
              ),
          ],
        ),
        SizedBox(height: t.cardGap),
        Text(l10n.membersPermissions, style: text.titleMedium),
        Text(l10n.membersPermissionsHint, style: text.bodySmall),
        for (final area in _areas) ...[
          const SizedBox(height: 8),
          Text(l10n.accessClassName(area.name), style: text.bodyLarge),
          SegmentedControl(
            key: Key('member.area.${area.name}'),
            labels: [for (final v in _levels) l10n.permissionLevel(v)],
            selected: accessLevel(m.role, m.permissions, area),
            onChanged: (i) => repo.setPermission(
              m,
              area.name,
              // back to the role's own level clears the person's change
              i == accessLevel(m.role, const {}, area) ? null : _levels[i],
              name,
            ),
          ),
        ],
        SizedBox(height: t.cardGap),
        OutlineButton(
          key: const Key('member.remove'),
          label: l10n.membersRemove,
          icon: Icons.person_remove_outlined,
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                content: Text(l10n.membersRemoveConfirm(name)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.actionCancel),
                  ),
                  TextButton(
                    key: const Key('member.remove.confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l10n.actionRemove),
                  ),
                ],
              ),
            );
            if (ok != true) return;
            final events = await repo.remove(m, name);
            if (!context.mounted) return;
            showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
