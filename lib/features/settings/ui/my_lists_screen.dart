import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/access/access.dart';
import '../../../core/overrides/overrides.dart';
import '../../../l10n/app_localizations.dart';
import '../../land/data/land_providers.dart';
import '../../land/domain/land.dart';
import '../data/settings_providers.dart';

const _list = 'activity';

/// Screen 16: a crop's activities with on/off switches, the farmer's own
/// items, "new items available" after an admin update, and reset. A change
/// here is the farmer's: an admin update never overrides it.
class MyListsScreen extends ConsumerStatefulWidget {
  const MyListsScreen({super.key});

  @override
  ConsumerState<MyListsScreen> createState() => _MyListsScreenState();
}

class _MyListsScreenState extends ConsumerState<MyListsScreen> {
  /// Null for the items used for every crop.
  String? _crop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final overrides = ref.watch(overridesProvider).value;
    final canWrite =
        ref.watch(accessProvider).value?.canWrite(AccessClass.setup) ?? false;
    final repo = ref.watch(settingsRepositoryProvider);
    final crops = {
      for (final p in ref.watch(plotsProvider).value ?? const <PlotView>[])
        for (final c in p.cycles) c.cropId: c,
    };
    final items = overrides?.list(_list, Scope(cropId: _crop)) ?? const [];
    String name(ListItem i) =>
        localName(settings, i.nameMl.value, i.nameEn.value, l10n.nameMixed);
    Future<void> undoable(Future<List<String>> write) async {
      final events = await write;
      if (events.isNotEmpty && context.mounted) {
        showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myListsTitle)),
      body: ListView(
        padding: EdgeInsets.all(t.screenPadding),
        children: [
          Text(l10n.myListsSubtitle, style: text.bodySmall),
          SizedBox(height: t.cardGap),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (id, label) in [
                (null, l10n.myListsCrop),
                for (final c in crops.values)
                  (
                    c.cropId,
                    localName(settings, c.nameMl, c.nameEn, l10n.nameMixed),
                  ),
              ])
                ChoiceChipX(
                  key: Key('lists.crop.${id ?? 'all'}'),
                  label: label,
                  selected: _crop == id,
                  onSelected: (_) => setState(() => _crop = id),
                ),
            ],
          ),
          if (overrides != null &&
              overrides.latestVersion > overrides.acceptedVersion) ...[
            SizedBox(height: t.cardGap),
            Container(
              key: const Key('lists.update'),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              decoration: BoxDecoration(
                color: t.noticeBg,
                border: Border.all(color: t.noticeLine),
                borderRadius: BorderRadius.circular(t.tileRadius),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.myListsUpdateAvailable,
                      style: text.bodyMedium,
                    ),
                  ),
                  if (canWrite)
                    TextButton(
                      key: const Key('lists.update.accept'),
                      onPressed: () =>
                          repo.acceptTemplates(overrides.latestVersion),
                      child: Text(l10n.myListsAcceptUpdate),
                    ),
                ],
              ),
            ),
          ],
          if (!canWrite) ...[
            SizedBox(height: t.cardGap),
            LastTimeBanner(
              text: l10n.myListsReadOnly,
              icon: Icons.lock_outline,
            ),
          ],
          SizedBox(height: t.cardGap),
          ThottamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.myListsActivities, style: text.titleMedium),
                Text(l10n.myListsActivitiesHint, style: text.bodySmall),
                for (final i in items)
                  ConstrainedBox(
                    key: Key('lists.item.${i.code}'),
                    constraints: BoxConstraints(minHeight: t.listRowMin),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name(i), style: text.bodyLarge),
                              if (i.isOwn)
                                Text(l10n.myListsOwn, style: text.bodySmall)
                              else if (i.hidden)
                                Text(
                                  l10n.myListsChanged,
                                  style: text.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        if (i.isOwn && canWrite)
                          IconButton(
                            key: Key('lists.remove.${i.code}'),
                            tooltip: l10n.actionRemove,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                undoable(repo.removeOwn(_list, i.code, _crop)),
                          ),
                        Switch(
                          key: Key('lists.switch.${i.code}'),
                          value: !i.hidden,
                          onChanged: canWrite
                              ? (on) => undoable(
                                  repo.setShown(
                                    _list,
                                    i.code,
                                    _crop,
                                    shown: on,
                                    own: i.isOwn,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (canWrite) ...[
            SizedBox(height: t.cardGap),
            OutlineButton(
              key: const Key('lists.add'),
              label: l10n.myListsAddOwn,
              icon: Icons.add,
              onPressed: () async {
                final names = await showDialog<(String?, String?)>(
                  context: context,
                  builder: (_) => const _OwnItemDialog(),
                );
                if (names != null) {
                  await undoable(repo.addOwn(_list, _crop, names.$1, names.$2));
                }
              },
            ),
            SizedBox(height: t.cardGap),
            Text(l10n.myListsResetHint, style: text.bodySmall),
            OutlineButton(
              key: const Key('lists.reset'),
              label: l10n.actionResetDefault,
              onPressed: () => undoable(repo.resetShown(_list, _crop)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The names of an own item; one language is enough.
class _OwnItemDialog extends StatefulWidget {
  const _OwnItemDialog();

  @override
  State<_OwnItemDialog> createState() => _OwnItemDialogState();
}

class _OwnItemDialogState extends State<_OwnItemDialog> {
  final _ml = TextEditingController();
  final _en = TextEditingController();
  bool _showErrors = false;

  @override
  void dispose() {
    _ml.dispose();
    _en.dispose();
    super.dispose();
  }

  String? _value(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    bool empty() => _value(_ml) == null && _value(_en) == null;
    return AlertDialog(
      title: Text(l10n.myListsAddOwn),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('own.ml'),
            controller: _ml,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.myListsNameMl,
              errorText: _showErrors && empty()
                  ? l10n.myListsNameRequired
                  : null,
            ),
          ),
          TextField(
            key: const Key('own.en'),
            controller: _en,
            decoration: InputDecoration(labelText: l10n.myListsNameEn),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          key: const Key('own.save'),
          onPressed: () {
            if (empty()) {
              setState(() => _showErrors = true);
              return;
            }
            Navigator.of(context).pop((_value(_ml), _value(_en)));
          },
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
