import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_parse.dart';
import '../../../l10n/app_localizations.dart';
import '../data/labour_providers.dart';
import '../data/labour_repository.dart';

/// Add a worker, or edit [worker]: name, phone, usual daily wage, family.
Future<void> showWorkerForm(
  BuildContext context,
  WidgetRef ref, {
  WorkerView? worker,
}) => showThottamSheet<void>(
  context,
  builder: (context) => _WorkerForm(worker: worker),
);

class _WorkerForm extends ConsumerStatefulWidget {
  const _WorkerForm({this.worker});

  final WorkerView? worker;

  @override
  ConsumerState<_WorkerForm> createState() => _WorkerFormState();
}

class _WorkerFormState extends ConsumerState<_WorkerForm> {
  late final _name = TextEditingController(text: widget.worker?.name);
  late final _phone = TextEditingController(text: widget.worker?.phone);
  late final _rate = TextEditingController(
    text: widget.worker == null || widget.worker!.defaultRatePaise == 0
        ? ''
        : formatPaise(widget.worker!.defaultRatePaise)
              .replaceAll('₹', '')
              .replaceAll(',', ''),
  );
  late bool _family = widget.worker?.isFamily ?? false;
  bool _showErrors = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(labourRepositoryProvider);
    final rate = parseRupeesToPaise(_rate.text) ?? 0;
    final List<String> events;
    if (widget.worker case final w?) {
      events = await repo.updateWorker(
        w.id,
        _name.text,
        phone: _phone.text,
        defaultRatePaise: rate,
        isFamily: _family,
      );
    } else {
      (_, events) = await repo.createWorker(
        _name.text,
        phone: _phone.text,
        defaultRatePaise: rate,
        isFamily: _family,
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
    showUndoToast(context, l10n.toastSaved, () => repo.undo(events));
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
            l10n.labourAddWorker,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          TextField(
            key: const Key('workerForm.name'),
            controller: _name,
            autofocus: widget.worker == null,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.labourWorkerName,
              errorText: _showErrors && _name.text.trim().isEmpty
                  ? l10n.labourWorkerNameRequired
                  : null,
            ),
          ),
          TextField(
            key: const Key('workerForm.rate'),
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.labourDailyRate,
              prefixText: '₹ ',
            ),
          ),
          TextField(
            key: const Key('workerForm.phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: l10n.fieldOptional(l10n.fieldPhone),
            ),
          ),
          SwitchRow(
            key: const Key('workerForm.family'),
            title: l10n.labourFamily,
            subtitle: l10n.labourFamilyHint,
            value: _family,
            onChanged: (v) => setState(() => _family = v),
          ),
          SizedBox(height: t.cardGap),
          PrimaryButton(
            key: const Key('workerForm.save'),
            label: l10n.actionSave,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
