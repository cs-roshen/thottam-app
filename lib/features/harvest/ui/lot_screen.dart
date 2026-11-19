import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../labour/data/labour_providers.dart';
import '../data/harvest_providers.dart';
import '../data/harvest_repository.dart';
import '../domain/harvest_math.dart';

/// A saved harvest: its teams, and its lot with the lot's cost (rule 9):
/// worked out, not yet worked out, or changed by hand and resettable.
class LotScreen extends ConsumerWidget {
  const LotScreen({super.key, required this.harvestId});

  final String harvestId;

  Future<void> _editCost(
    BuildContext context,
    WidgetRef ref,
    HarvestView h,
  ) async {
    final l10n = AppLocalizations.of(context);
    final paise = await showAmountDialog(
      context,
      title: l10n.lotEditCost,
      paise: h.costPaise,
      fieldKey: const Key('lot.costField'),
      saveKey: const Key('lot.costSave'),
    );
    if (paise == null) return;
    final repo = ref.read(harvestRepositoryProvider);
    final events = await repo.setCost(h.lotId, paise);
    if (context.mounted) {
      showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final h = ref.watch(harvestProvider(harvestId)).value;
    if (h == null) return Scaffold(appBar: AppBar());
    final seeCost = ref.watch(canSeeLotCostProvider);
    final writeCost = ref.watch(canWriteLotCostProvider);
    final summary = summarise(h.teams, perTeam: h.perTeam, total: h.quantity);
    final perUnit = h.costPaise == null
        ? null
        : costPerUnit(h.costPaise!, h.quantity);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.lotTitle(formatDay(h.day, l10n, ref.watch(clockProvider)())),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          Text(
            l10n.quantityWithUnit(formatQuantity(h.quantity), h.unit),
            key: const Key('lot.quantity'),
            style: text.displayLarge,
          ),
          SizedBox(height: t.cardGap),
          ThottamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final team in h.teams)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            team.label.isEmpty
                                ? l10n.labourPeople(team.heads)
                                : l10n.nameWithDetail(
                                    team.label,
                                    l10n.labourPeople(team.heads),
                                  ),
                            style: text.bodyMedium,
                          ),
                        ),
                        Text(
                          formatPaise(team.wagePaise),
                          style: text.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(l10n.harvestPaidWages, style: text.bodyLarge),
                    ),
                    Text(
                      formatPaise(summary.paidWagesPaise),
                      style: text.bodyLarge,
                    ),
                  ],
                ),
                if (summary.familyWagesPaise > 0)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.harvestFamilyLine,
                          style: text.bodySmall,
                        ),
                      ),
                      Text(
                        formatPaise(summary.familyWagesPaise),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (ref.watch(canWriteDailyProvider)) ...[
            SizedBox(height: t.cardGap),
            OutlineButton(
              key: const Key('lot.editTeams'),
              label: l10n.lotEditTeams,
              icon: Icons.edit_outlined,
              onPressed: () => context.push('/add/harvest?edit=$harvestId'),
            ),
          ],
          if (seeCost) ...[
            SizedBox(height: t.cardGap),
            ThottamCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.lotCost, style: text.bodySmall),
                  Text(
                    h.costPaise == null
                        ? l10n.lotCostPending
                        : formatPaise(h.costPaise!),
                    key: const Key('lot.cost'),
                    style: text.headlineMedium,
                  ),
                  if (perUnit != null)
                    Text(
                      l10n.lotCostPerUnit(formatPaise(perUnit), h.unit),
                      key: const Key('lot.costPerUnit'),
                      style: text.bodyLarge,
                    ),
                  if (h.costOverridden)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Pill(
                        label: l10n.lotCostEdited,
                        background: t.accentTint,
                        foreground: t.onAccentTintStrong,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(l10n.lotCostHint, style: text.bodySmall),
                  if (writeCost) ...[
                    SizedBox(height: t.cardGap),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          key: const Key('lot.edit'),
                          onPressed: () => _editCost(context, ref, h),
                          child: Text(l10n.lotEditCost),
                        ),
                        OutlinedButton(
                          key: const Key('lot.recalculate'),
                          onPressed: () async {
                            final repo = ref.read(harvestRepositoryProvider);
                            final events = await repo.recalculate(harvestId);
                            if (context.mounted) {
                              showUndoToast(
                                context,
                                l10n.toastSaved,
                                () => repo.undo(events),
                              );
                            }
                          },
                          child: Text(
                            h.costOverridden
                                ? l10n.lotReset
                                : l10n.lotRecalculate,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(t.screenPadding),
          child: PrimaryButton(
            key: const Key('lot.sell'),
            label: l10n.harvestSellNow,
            icon: Icons.sell_outlined,
            onPressed: () => context.push('/add/sale?lot=${h.lotId}'),
          ),
        ),
      ),
    );
  }
}
