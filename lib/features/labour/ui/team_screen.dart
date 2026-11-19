import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_parse.dart';
import '../../../core/overrides/overrides.dart';
import '../../../l10n/app_localizations.dart';
import '../data/labour_providers.dart';
import '../data/labour_repository.dart';
import '../domain/wages.dart';
import 'worker_form.dart';

extension LabourLabels on AppLocalizations {
  String balanceLine(int paise) => paise > 0
      ? labourBalanceDue(formatPaise(paise))
      : paise < 0
      ? labourBalanceAhead(formatPaise(-paise))
      : labourBalanceClear;

  String groupName(GroupView g) =>
      g.label.isEmpty ? labourUnnamedGroup : g.label;

  String attendanceName(Attendance a) => switch (a) {
    Attendance.full => attendanceFull,
    Attendance.half => attendanceHalf,
    Attendance.absent => attendanceAbsent,
    Attendance.overtime => attendanceOvertime,
  };
}

/// Workers and groups, each with what they are owed (for roles that can
/// see money).
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final workers = ref.watch(workersProvider).value ?? const <WorkerView>[];
    final groups = ref.watch(groupsProvider).value ?? const <GroupView>[];
    final money = ref.watch(canSeeLabourMoneyProvider);
    final canWrite = ref.watch(canWriteTeamProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.labourTeam)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          Text(l10n.labourWorkers, style: text.titleLarge),
          if (workers.isEmpty)
            Text(l10n.labourNoWorkers, style: text.bodyMedium),
          for (final w in workers)
            _TeamRow(
              key: Key('team.worker.${w.id}'),
              title: w.name,
              subtitle: [
                l10n.labourRatePerDay(formatPaise(w.defaultRatePaise)),
                if (w.isFamily) l10n.labourFamily,
              ].join(' · '),
              balance: money ? l10n.balanceLine(w.balancePaise) : null,
              onTap: () => context.push('/labour/worker/${w.id}'),
            ),
          if (canWrite)
            Padding(
              padding: EdgeInsets.only(top: t.cardGap),
              child: OutlineButton(
                key: const Key('team.addWorker'),
                label: l10n.labourAddWorker,
                icon: Icons.person_add_alt,
                onPressed: () => showWorkerForm(context, ref),
              ),
            ),
          SizedBox(height: t.cardGap * 2),
          Text(l10n.labourGroups, style: text.titleLarge),
          if (groups.isEmpty) Text(l10n.labourNoGroups, style: text.bodyMedium),
          for (final g in groups)
            _TeamRow(
              key: Key('team.group.${g.id}'),
              title: l10n.groupName(g),
              subtitle: g.usualSize == null
                  ? null
                  : l10n.labourPeople(g.usualSize!),
              balance: money ? l10n.balanceLine(g.balancePaise) : null,
              onTap: () => context.push('/labour/group/${g.id}'),
            ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.balance,
  });

  final String title;
  final String? subtitle;
  final String? balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ThottamCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  if (subtitle != null) Text(subtitle!, style: text.bodySmall),
                  if (balance != null) Text(balance!, style: text.bodyLarge),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.muted),
          ],
        ),
      ),
    );
  }
}

/// A worker's or group's ledger: balance, days worked and payments, with
/// Pay for roles that write money and Edit for those that write the team.
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key, this.workerId, this.groupId});

  final String? workerId;
  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final today = ref.watch(clockProvider)();
    final money = ref.watch(canSeeLabourMoneyProvider);
    final worker = workerId == null
        ? null
        : (ref.watch(workersProvider).value ?? const <WorkerView>[])
              .where((w) => w.id == workerId)
              .firstOrNull;
    final group = groupId == null
        ? null
        : (ref.watch(groupsProvider).value ?? const <GroupView>[])
              .where((g) => g.id == groupId)
              .firstOrNull;
    if (worker == null && group == null) return Scaffold(appBar: AppBar());
    final name = worker?.name ?? l10n.groupName(group!);
    final lines =
        ref
            .watch(
              workerId != null
                  ? workerLedgerProvider(workerId!)
                  : groupLedgerProvider(groupId!),
            )
            .value ??
        const <LedgerLine>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (ref.watch(canWriteTeamProvider))
            IconButton(
              key: const Key('ledger.edit'),
              tooltip: l10n.actionEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => worker != null
                  ? showWorkerForm(context, ref, worker: worker)
                  : showThottamSheet<void>(
                      context,
                      builder: (_) => _GroupForm(group: group!),
                    ),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          if (money) ...[
            Text(
              l10n.balanceLine(worker?.balancePaise ?? group!.balancePaise),
              key: const Key('ledger.balance'),
              style: text.headlineMedium,
            ),
            if (ref.watch(canPayProvider)) ...[
              SizedBox(height: t.cardGap),
              PrimaryButton(
                key: const Key('ledger.pay'),
                label: l10n.actionPay,
                icon: Icons.payments_outlined,
                onPressed: () => showThottamSheet<void>(
                  context,
                  builder: (_) => _PaymentForm(
                    workerId: workerId,
                    groupId: groupId,
                    name: name,
                    owed: worker?.balancePaise ?? group!.balancePaise,
                  ),
                ),
              ),
            ],
            SizedBox(height: t.cardGap),
          ],
          ThottamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in lines)
                  if (money || line.kind == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.kind != null
                                      ? l10n.paymentKind(line.kind!.name)
                                      : worker != null
                                      ? l10n.attendanceName(
                                          Attendance.of(
                                            line.attendance ?? 1000,
                                            line.overtimeHours,
                                          ),
                                        )
                                      : l10n.labourPeople(line.heads ?? 1),
                                  style: text.bodyLarge,
                                ),
                                Text(
                                  formatDay(line.day, l10n, today),
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (money)
                            Text(
                              line.kind == null
                                  ? formatPaise(line.paise)
                                  : '− ${formatPaise(line.paise)}',
                              style: text.bodyLarge,
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({
    this.workerId,
    this.groupId,
    required this.name,
    required this.owed,
  });

  final String? workerId;
  final String? groupId;
  final String name;
  final int owed;

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  late PaymentKind _kind = widget.owed > 0
      ? PaymentKind.settlement
      : PaymentKind.advance;
  late final _amount = TextEditingController(
    text: widget.owed > 0
        ? formatPaise(widget.owed).replaceAll('₹', '').replaceAll(',', '')
        : '',
  );
  String _mode = 'cash';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount.text);
    if (paise == null || paise == 0) return;
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(labourRepositoryProvider);
    final now = ref.read(clockProvider)();
    final events = await repo.addPayment(
      workerId: widget.workerId,
      groupId: widget.groupId,
      kind: _kind,
      amountPaise: paise,
      day:
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}',
      mode: _mode,
      name: widget.name,
    );
    if (!mounted) return;
    Navigator.pop(context);
    showUndoToast(context, l10n.labourPaid, () => repo.undo(events));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.labourPaymentTitle(widget.name),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final k in PaymentKind.values)
                ChoiceChipX(
                  key: Key('pay.kind.${k.name}'),
                  label: l10n.paymentKind(k.name),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          AmountInput(
            key: const Key('pay.amount'),
            label: l10n.fieldAmount,
            hint: l10n.amountInputHint,
            controller: _amount,
            onChanged: (_) {},
          ),
          SizedBox(height: t.cardGap),
          Text(
            l10n.fieldPaymentMode,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final (code, label) in [
                ('cash', l10n.paymentCash),
                ('upi', l10n.paymentUpi),
                ('bank', l10n.paymentBank),
              ])
                ChoiceChipX(
                  key: Key('pay.mode.$code'),
                  label: label,
                  selected: _mode == code,
                  onSelected: (_) => setState(() => _mode = code),
                ),
            ],
          ),
          SizedBox(height: t.cardGap),
          PrimaryButton(
            key: const Key('pay.save'),
            label: l10n.actionSave,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Names a group and sets its leader, usual size, usual rates and members.
/// An unnamed group named here keeps every day it already has.
class _GroupForm extends ConsumerStatefulWidget {
  const _GroupForm({required this.group});

  final GroupView group;

  @override
  ConsumerState<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends ConsumerState<_GroupForm> {
  late final _label = TextEditingController(text: widget.group.label);
  late final _size = TextEditingController(
    text: widget.group.usualSize?.toString(),
  );
  late String? _leader = widget.group.leaderWorkerId;
  late final _members = {...widget.group.memberIds};
  late final _rates = {...widget.group.defaultRates};

  @override
  void dispose() {
    _label.dispose();
    _size.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(labourRepositoryProvider);
    final events = await repo.updateGroup(
      widget.group,
      label: _label.text,
      leaderWorkerId: _leader,
      usualSize: int.tryParse(_size.text.trim()),
      defaultRates: _rates,
      memberIds: _members.toList(),
    );
    if (!mounted) return;
    Navigator.pop(context);
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final workers = ref.watch(workersProvider).value ?? const <WorkerView>[];
    final classes =
        ref.watch(overridesProvider).value?.list('rate_class', const Scope()) ??
        const <ListItem>[];
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('groupForm.name'),
            controller: _label,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.labourGroupName),
          ),
          TextField(
            key: const Key('groupForm.size'),
            controller: _size,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.fieldOptional(l10n.labourGroupUsualSize),
            ),
          ),
          for (final c in classes)
            TextFormField(
              key: Key('groupForm.rate.${c.code}'),
              initialValue: _rates[c.code] == null
                  ? ''
                  : formatPaise(_rates[c.code]!)
                        .replaceAll('₹', '')
                        .replaceAll(',', ''),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.fieldOptional(
                  localName(
                    settings,
                    c.nameMl.value,
                    c.nameEn.value,
                    l10n.nameMixed,
                  ),
                ),
                prefixText: '₹ ',
              ),
              onChanged: (v) {
                final p = parseRupeesToPaise(v);
                p == null ? _rates.remove(c.code) : _rates[c.code] = p;
              },
            ),
          if (workers.isNotEmpty) ...[
            SizedBox(height: t.cardGap),
            Text(l10n.labourGroupLeader, style: text.bodySmall),
            Wrap(
              spacing: 8,
              children: [
                for (final w in workers)
                  ChoiceChipX(
                    label: w.name,
                    selected: _leader == w.id,
                    onSelected: (_) =>
                        setState(() => _leader = _leader == w.id ? null : w.id),
                  ),
              ],
            ),
            SizedBox(height: t.cardGap),
            Text(l10n.labourGroupMembers, style: text.bodySmall),
            Wrap(
              spacing: 8,
              children: [
                for (final w in workers)
                  ChoiceChipX(
                    key: Key('groupForm.member.${w.id}'),
                    label: w.name,
                    selected: _members.contains(w.id),
                    onSelected: (on) => setState(
                      () => on ? _members.add(w.id) : _members.remove(w.id),
                    ),
                  ),
              ],
            ),
          ],
          SizedBox(height: t.cardGap),
          PrimaryButton(
            key: const Key('groupForm.save'),
            label: l10n.actionSave,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
