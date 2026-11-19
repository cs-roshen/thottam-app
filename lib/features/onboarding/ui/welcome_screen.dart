import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/settings.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';

/// Screen 1: choose the language and text size, then sign in. Each choice
/// applies to the whole app at once and is kept on the phone.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final languages = [
      (
        LanguageChoice.malayalam,
        l10n.languageMalayalam,
        l10n.languageMalayalamHint,
      ),
      (LanguageChoice.english, l10n.languageEnglish, l10n.languageEnglishHint),
      (LanguageChoice.mixed, l10n.languageMixed, l10n.languageMixedHint),
    ];
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // green header; its last strip is the panel's rounded top
            ColoredBox(
              color: t.primary,
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(28, 40, 28, t.screenPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TintIconTile(
                            icon: Icons.eco_outlined,
                            background: t.accent,
                            foreground: t.primaryDark,
                            size: 72,
                          ),
                          SizedBox(height: t.cardGap),
                          Text(
                            l10n.appName,
                            style: text.displayLarge!.copyWith(
                              color: t.onPrimary,
                            ),
                          ),
                          Text(
                            l10n.welcomeTagline,
                            style: text.bodyMedium!.copyWith(
                              color: t.onPrimary,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: t.sheetRadius,
                      decoration: BoxDecoration(
                        color: t.ground,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(t.sheetRadius),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.welcomeChooseLanguage, style: text.titleLarge),
                  SizedBox(height: t.cardGap),
                  for (final (choice, label, hint) in languages) ...[
                    _LanguageOption(
                      key: Key('welcome.${choice.name}'),
                      label: label,
                      hint: hint,
                      selected: settings.language == choice,
                      onTap: () => notifier.setLanguage(choice),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SwitchRow(
                    key: const Key('welcome.largeText'),
                    title: l10n.settingsLargeText,
                    subtitle: l10n.settingsLargeTextHint,
                    value: settings.largeText,
                    onChanged: notifier.setLargeText,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // the main action stays in reach of the thumb, whatever the text size
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 10, 24, t.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                key: const Key('welcome.continue'),
                label: l10n.actionContinue,
                onPressed: () => context.go('/signin'),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.welcomeChangeLater,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    super.key,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(t.buttonRadius);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? t.primary : t.line, width: 2),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.listRowMax),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? t.primary : t.muted,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: text.bodyLarge!.copyWith(fontSize: 19),
                        ),
                        Text(hint, style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
