import '../../../core/overrides/overrides.dart';
import '../../../core/split/split.dart';
import 'land.dart';

/// The crops a cost on [plot] can go to: the ones growing now.
List<CycleView> openCycles(PlotView? plot) => [
  for (final c in plot?.cycles ?? const <CycleView>[])
    if (!c.closed) c,
];

/// [cycles] as split targets, each with its crop's default cost share as
/// the override model resolves it for that crop cycle.
List<SplitTarget> splitTargets(List<CycleView> cycles, Overrides? overrides) =>
    [
      for (final c in cycles)
        SplitTarget(
          c.id,
          templateWeight:
              overrides
                      ?.value(
                        'setting',
                        'split_weight',
                        'value',
                        Scope(
                          cropId: c.cropId,
                          plotId: c.plotId,
                          cropCycleId: c.id,
                        ),
                      )
                      ?.value
                  as num?,
          areaShare: c.areaShare,
          plantCount: c.plantCount,
        ),
    ];

/// Whether labour on a mixed plot splits across its crops or goes to one
/// (the `labour_split` setting; app default: like an expense).
bool labourSplits(Overrides? overrides, String? plotId) =>
    overrides
        ?.value('setting', 'labour_split', 'value', Scope(plotId: plotId))
        ?.value !=
    'one';
