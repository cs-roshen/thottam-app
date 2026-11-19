import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session.dart';
import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../core/units/quantity_parse.dart';
import '../../../l10n/app_localizations.dart';
import '../data/onboarding_providers.dart';
import '../domain/setup.dart';

/// Screen 17: three steps, name → first farm → crops. Only the name and the
/// farm name are needed; finishing creates the farm, its plot and crop
/// cycles on the phone and opens Home.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  static const _steps = 3;
  int _step = 0;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _farm = TextEditingController();
  final _area = TextEditingController();
  String? _unit;
  String _tenure = 'owned';
  final _crops = <String>{};
  bool _showErrors = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final account = ref.read(sessionProvider).account;
    _name.text = account?.name ?? '';
    _phone.text = account?.phone ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _farm, _area]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _areaOk =>
      _area.text.trim().isEmpty || parseQuantity(_area.text) != null;

  bool get _stepOk => switch (_step) {
    0 => _name.text.trim().isNotEmpty,
    1 => _farm.text.trim().isNotEmpty && _areaOk,
    _ => true,
  };

  Future<void> _next(String defaultUnit) async {
    if (!_stepOk) {
      setState(() => _showErrors = true);
      return;
    }
    if (_step < _steps - 1) {
      setState(() {
        _step++;
        _showErrors = false;
      });
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final phone = _phone.text.trim();
    final input = SetupInput(
      name: _name.text.trim(),
      phone: phone.isEmpty ? null : phone,
      farmName: _farm.text,
      area: parseQuantity(_area.text),
      areaUnit: _unit ?? defaultUnit,
      tenure: _tenure,
      cropIds: _crops.toList(),
    );
    final farmId = await ref
        .read(onboardingRepositoryProvider)
        .createFarm(ref.read(userIdProvider), input);
    final session = ref.read(sessionProvider.notifier);
    await session.updateProfile(input.name, input.phone);
    if (mounted) showToast(context, l10n.setupWelcomeDone);
    await session.openFarm(farmId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final choices = ref.watch(setupChoicesProvider).value;
    final (title, hint) = switch (_step) {
      0 => (l10n.setupStepNameTitle, l10n.setupStepNameHint),
      1 => (l10n.setupStepFarmTitle, l10n.setupStepFarmHint),
      _ => (l10n.setupStepCropsTitle, l10n.setupStepCropsHint),
    };
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(t.screenPadding),
                  children: [
                    ExcludeSemantics(
                      child: Row(
                        children: [
                          for (var i = 0; i < _steps; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i <= _step ? t.primary : t.chipBorder,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: t.cardGap),
                    Text(
                      l10n.setupStepOf(_step + 1, _steps),
                      style: text.bodyLarge!.copyWith(color: t.primary),
                    ),
                    Text(title, style: text.headlineMedium),
                    Text(hint, style: text.bodySmall),
                    SizedBox(height: t.cardGap),
                    if (choices != null)
                      switch (_step) {
                        0 => _nameStep(l10n),
                        1 => _farmStep(l10n, choices.$2),
                        _ => _cropsStep(choices.$1),
                      },
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  t.screenPadding,
                  0,
                  t.screenPadding,
                  t.screenPadding,
                ),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: SizedBox(
                          height: t.primaryButtonHeight,
                          child: OutlineButton(
                            key: const Key('setup.back'),
                            label: l10n.actionBack,
                            onPressed: () => setState(() => _step--),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        key: const Key('setup.next'),
                        label: _step < _steps - 1
                            ? l10n.actionNext
                            : l10n.setupFinish,
                        onPressed: choices == null || _saving
                            ? null
                            : () => _next(choices.$2.first),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameStep(AppLocalizations l10n) => ThottamCard(
    child: Column(
      children: [
        TextField(
          key: const Key('setup.name'),
          controller: _name,
          autofocus: _name.text.isEmpty,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.fieldName,
            errorText: _showErrors && _name.text.trim().isEmpty
                ? l10n.setupNameRequired
                : null,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('setup.phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
          ],
          decoration: InputDecoration(
            labelText: l10n.fieldOptional(l10n.fieldPhone),
          ),
        ),
      ],
    ),
  );

  Widget _farmStep(AppLocalizations l10n, List<String> units) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final unit = _unit ?? units.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThottamCard(
          child: Column(
            children: [
              TextField(
                key: const Key('setup.farmName'),
                controller: _farm,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.setupFarmName,
                  errorText: _showErrors && _farm.text.trim().isEmpty
                      ? l10n.setupFarmNameRequired
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('setup.area'),
                controller: _area,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.fieldOptional(l10n.fieldArea),
                  suffixText: unit,
                  errorText: _areaOk ? null : l10n.setupAreaInvalid,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: t.cardGap),
        Text(l10n.setupAreaUnit, style: text.bodySmall),
        Wrap(
          spacing: 8,
          children: [
            for (final u in units)
              ChoiceChipX(
                key: Key('setup.unit.$u'),
                label: u,
                selected: u == unit,
                onSelected: (_) => setState(() => _unit = u),
              ),
          ],
        ),
        SizedBox(height: t.cardGap),
        Text(l10n.setupTenure, style: text.bodySmall),
        Wrap(
          spacing: 8,
          children: [
            for (final (code, label) in [
              ('owned', l10n.tenureOwned),
              ('leased', l10n.tenureLeased),
            ])
              ChoiceChipX(
                key: Key('setup.tenure.$code'),
                label: label,
                selected: _tenure == code,
                onSelected: (_) => setState(() => _tenure = code),
              ),
          ],
        ),
      ],
    );
  }

  Widget _cropsStep(List<CropChoice> crops) {
    final settings = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      children: [
        for (final c in crops)
          ChoiceChipX(
            key: Key('setup.crop.${c.nameEn}'),
            label: localName(settings, c.nameMl, c.nameEn, l10n.nameMixed),
            selected: _crops.contains(c.id),
            onSelected: (on) =>
                setState(() => on ? _crops.add(c.id) : _crops.remove(c.id)),
          ),
      ],
    );
  }
}
