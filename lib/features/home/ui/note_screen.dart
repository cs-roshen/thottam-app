import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/date_format.dart';
import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/access/access.dart';
import '../../../l10n/app_localizations.dart';
import '../../land/data/land_providers.dart';
import '../../land/domain/split_targets.dart';
import '../../land/ui/land_labels.dart';
import '../data/home_providers.dart';
import '../data/home_repository.dart';

/// Quick add's note (screen 3): text, the day (today), and a plot and crop
/// if the farmer picks them. It shows in History under its day.
class NoteScreen extends ConsumerStatefulWidget {
  const NoteScreen({super.key, this.plotId});

  final String? plotId;

  @override
  ConsumerState<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends ConsumerState<NoteScreen> {
  final _text = TextEditingController();
  late String _day;
  String? _plotId;
  String? _cycleId;
  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _day = isoDay(ref.read(clockProvider)());
    _plotId = widget.plotId;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_day),
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = isoDay(picked));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_text.text.trim().isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final plots = ref.read(plotsProvider).value ?? const [];
    final plot = plots.where((p) => p.id == _plotId).firstOrNull;
    final cycle = plot?.cycles.where((c) => c.id == _cycleId).firstOrNull;
    final repo = ref.read(homeRepositoryProvider);
    final events = await repo.saveNote(
      NoteInput(
        day: _day,
        text: _text.text,
        plotId: plot?.id,
        plot: plot?.name,
        cycleId: cycle?.id,
        cropMl: cycle?.nameMl,
        cropEn: cycle?.nameEn,
      ),
    );
    if (!mounted) return;
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final canWrite =
        ref.watch(accessProvider).value?.canWrite(AccessClass.daily) ?? false;
    final plots = ref.watch(plotsProvider).value ?? const [];
    final plot = plots.where((p) => p.id == _plotId).firstOrNull;
    final cycles = openCycles(plot);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.quickAddNote)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          TextField(
            key: const Key('note.text'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.noteText,
              errorText: _showErrors && _text.text.trim().isEmpty
                  ? l10n.noteTextRequired
                  : null,
            ),
            onChanged: (_) {
              if (_showErrors) setState(() {});
            },
          ),
          SizedBox(height: t.cardGap),
          Row(
            children: [
              Expanded(child: Text(l10n.expenseDate, style: text.bodySmall)),
              TextButton.icon(
                key: const Key('note.day'),
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(formatDay(_day, l10n, ref.watch(clockProvider)())),
              ),
            ],
          ),
          if (plots.isNotEmpty) ...[
            Text(l10n.fieldOptional(l10n.labourPlot), style: text.bodySmall),
            Wrap(
              spacing: 8,
              children: [
                for (final p in plots)
                  ChoiceChipX(
                    key: Key('note.plot.${p.id}'),
                    label: p.name,
                    selected: p.id == _plotId,
                    // a second tap takes the plot off again
                    onSelected: (_) => setState(() {
                      _plotId = p.id == _plotId ? null : p.id;
                      _cycleId = null;
                    }),
                  ),
              ],
            ),
          ],
          if (cycles.isNotEmpty) ...[
            SizedBox(height: t.cardGap),
            Text(l10n.fieldOptional(l10n.harvestCrop), style: text.bodySmall),
            Wrap(
              spacing: 8,
              children: [
                for (final c in cycles)
                  ChoiceChipX(
                    key: Key('note.crop.${c.id}'),
                    label: l10n.cropName(settings, c),
                    selected: c.id == _cycleId,
                    onSelected: (_) => setState(
                      () => _cycleId = c.id == _cycleId ? null : c.id,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(t.screenPadding),
          child: PrimaryButton(
            key: const Key('note.save'),
            label: l10n.actionSave,
            onPressed: !canWrite || _saving ? null : _save,
          ),
        ),
      ),
    );
  }
}
