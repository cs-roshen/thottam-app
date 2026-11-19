import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../labour/ui/team_screen.dart' show LabourLabels;
import '../data/sales_providers.dart';
import '../data/sales_repository.dart';

/// The buyer book: each buyer with what they still owe.
class BuyersScreen extends ConsumerWidget {
  const BuyersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final buyers = ref.watch(buyersProvider).value ?? const <Buyer>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.buyersTitle)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          if (buyers.isEmpty)
            EmptyState(
              icon: Icons.storefront_outlined,
              title: l10n.buyersTitle,
              message: l10n.buyersNone,
            ),
          for (final b in buyers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ThottamCard(
                key: Key('buyer.${b.id}'),
                onTap: () => context.push('/sales/buyer/${b.id}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name, style: text.titleMedium),
                          Text(
                            l10n.balanceLine(b.duePaise),
                            style: text.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: t.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One buyer's sales, each with what is still owed, and money received.
class BuyerScreen extends ConsumerWidget {
  const BuyerScreen({super.key, required this.buyerId});

  final String buyerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final buyer = (ref.watch(buyersProvider).value ?? const <Buyer>[])
        .where((b) => b.id == buyerId)
        .firstOrNull;
    final sales = ref.watch(buyerSalesProvider(buyerId)).value ?? const [];
    final today = ref.watch(clockProvider)();
    if (buyer == null) return Scaffold(appBar: AppBar());
    return Scaffold(
      appBar: AppBar(title: Text(buyer.name)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          Text(
            l10n.balanceLine(buyer.duePaise),
            key: const Key('buyer.due'),
            style: text.headlineMedium,
          ),
          SizedBox(height: t.cardGap),
          for (final s in sales)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ThottamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(formatDay(s.day, l10n, today), style: text.bodySmall),
                    Text(
                      l10n.buyerSaleLine(
                        l10n.quantityWithUnit(
                          formatQuantity(s.quantity),
                          s.unit,
                        ),
                        formatPaise(s.net),
                      ),
                      style: text.bodyLarge,
                    ),
                    if (s.due > 0) ...[
                      Text(l10n.balanceLine(s.due), style: text.bodyMedium),
                      if (ref.watch(canSellProvider))
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: Key('buyer.receive.${s.id}'),
                            onPressed: () async {
                              final paise = await showAmountDialog(
                                context,
                                title: l10n.buyerReceive,
                                paise: s.due,
                                fieldKey: const Key('buyer.amount'),
                                saveKey: const Key('buyer.amountSave'),
                              );
                              if (paise == null || paise <= 0) return;
                              final repo = ref.read(salesRepositoryProvider);
                              final d = ref.read(clockProvider)();
                              final events = await repo.receive(
                                s.id,
                                paise,
                                '${d.year}-${d.month.toString().padLeft(2, '0')}-'
                                '${d.day.toString().padLeft(2, '0')}',
                              );
                              if (context.mounted) {
                                showUndoToast(
                                  context,
                                  l10n.labourPaid,
                                  () => repo.undo(events),
                                );
                              }
                            },
                            child: Text(l10n.buyerReceive),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
