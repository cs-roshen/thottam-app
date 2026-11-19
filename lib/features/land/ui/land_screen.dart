import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../data/land_providers.dart';
import '../domain/land.dart';
import 'land_labels.dart';

/// Screen 4: the farm's plots with area, tenure, crops, a "mixed crop" tag
/// and the next task.
class LandScreen extends ConsumerWidget {
  const LandScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final plots = ref.watch(plotsProvider).value;
    final canWrite = ref.watch(canWriteLandProvider);
    final units = ref.watch(unitsProvider);
    final total = plots == null || units == null
        ? null
        : totalArea(plots, units.convert);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.landTitle)),
      body: plots == null
          ? const SizedBox.shrink()
          : ListView(
              padding: EdgeInsets.all(t.screenPadding),
              children: [
                if (plots.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: t.cardGap * 2),
                    child: EmptyState(
                      icon: Icons.map_outlined,
                      title: l10n.landEmptyTitle,
                      message: l10n.landEmptyHint,
                      actionLabel: canWrite ? l10n.landAddPlot : null,
                      onAction: () => context.go('/land/new'),
                    ),
                  )
                else ...[
                  Text(
                    total == null
                        ? l10n.landPlotCount(plots.length)
                        : l10n.landSummary(
                            plots.length,
                            l10n.area(total.$1, total.$2),
                          ),
                    style: text.bodySmall,
                  ),
                  for (final p in plots) ...[
                    SizedBox(height: t.cardGap),
                    _PlotCard(plot: p),
                  ],
                  if (canWrite) ...[
                    SizedBox(height: t.cardGap),
                    OutlineButton(
                      key: const Key('land.add'),
                      label: l10n.landAddPlot,
                      icon: Icons.add,
                      onPressed: () => context.go('/land/new'),
                    ),
                  ],
                ],
                if (!canWrite) ...[
                  SizedBox(height: t.cardGap),
                  LastTimeBanner(
                    text: l10n.landReadOnly,
                    icon: Icons.lock_outline,
                  ),
                ],
              ],
            ),
    );
  }
}

class _PlotCard extends ConsumerWidget {
  const _PlotCard({required this.plot});

  final PlotView plot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final task = plot.nextTask;
    return ThottamCard(
      key: Key('plot.${plot.id}'),
      onTap: () => context.go('/land/${plot.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TintIconTile(
                icon: Icons.map_outlined,
                background: t.primaryTint,
                foreground: t.primaryDark,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plot.name, style: text.titleMedium),
                    Text(l10n.plotLine(plot), style: text.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.muted),
            ],
          ),
          if (plot.cycles.isNotEmpty || plot.mixed) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in plot.cycles)
                  Pill(
                    label: l10n.cycleChip(settings, c),
                    background: t.primaryTint,
                    foreground: t.primaryDark,
                  ),
                if (plot.mixed)
                  Pill(
                    label: l10n.landMixedCropTag,
                    background: t.accentTint,
                    foreground: t.onAccentTintStrong,
                  ),
              ],
            ),
          ],
          if (task != null) ...[
            const SizedBox(height: 10),
            Text(
              task.$2 == null
                  ? l10n.landNextTask(task.$1)
                  : l10n.landNextTaskOn(
                      task.$1,
                      formatDay(task.$2!, l10n, ref.watch(clockProvider)()),
                    ),
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
