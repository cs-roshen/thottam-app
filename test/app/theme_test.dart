import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/theme/theme.dart';
import 'package:thottam/app/theme/tokens.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  const t = ThottamTokens.standard;

  group('every text and background pair meets 4.5:1', () {
    final pairs = <String, (Color, Color)>{
      'ink on ground': (t.ink, t.ground),
      'ink on surface': (t.ink, t.surface),
      'muted on surface': (t.muted, t.surface),
      'muted on ground': (t.muted, t.ground),
      'onPrimary on primary': (t.onPrimary, t.primary),
      'onPrimary on primaryDark': (t.onPrimary, t.primaryDark),
      'accent on primaryDark': (t.accent, t.primaryDark),
      'primaryDark on surface': (t.primaryDark, t.surface),
      'primaryDark on primaryTint': (t.primaryDark, t.primaryTint),
      'primaryDark on primaryPill': (t.primaryDark, t.primaryPill),
      'onAccentTint on accentTint': (t.onAccentTint, t.accentTint),
      'onAccentTintStrong on accentTint': (t.onAccentTintStrong, t.accentTint),
      'ink on noticeBg': (t.ink, t.noticeBg),
      'onExpenseTint on expenseTint': (t.onExpenseTint, t.expenseTint),
      'onExpenseTintStrong on expenseTint': (
        t.onExpenseTintStrong,
        t.expenseTint,
      ),
      'onNegativeTint on negativeTint': (t.onNegativeTint, t.negativeTint),
      'onDanger on surface': (t.onDanger, t.surface),
      'onInfoTint on infoTint': (t.onInfoTint, t.infoTint),
      'onInfoTintStrong on infoTint': (t.onInfoTintStrong, t.infoTint),
      'onToast on toast': (t.onToast, t.toast),
      'ink on segmentTrack': (t.ink, t.segmentTrack),
      'muted on segmentTrack': (t.muted, t.segmentTrack),
    };
    for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
      test(name, () => expect(contrast(fg, bg), greaterThanOrEqualTo(4.5)));
    }
  });

  group('theme', () {
    final theme = buildTheme(t);

    test('carries the tokens', () {
      expect(theme.extension<ThottamTokens>(), same(t));
      expect(theme.scaffoldBackgroundColor, t.ground);
      expect(theme.colorScheme.primary, t.primary);
    });

    test('body is Inter with Noto Sans Malayalam fallback', () {
      final body = theme.textTheme.bodyMedium!;
      expect(body.fontFamily, 'Inter');
      expect(body.fontFamilyFallback, contains('NotoSansMalayalam'));
      expect(body.color, t.ink);
    });

    test('headings and large numbers use Anek Malayalam', () {
      expect(theme.textTheme.displayLarge!.fontFamily, 'AnekMalayalam');
      expect(theme.textTheme.headlineMedium!.fontFamily, 'AnekMalayalam');
      expect(theme.textTheme.titleLarge!.fontFamily, 'AnekMalayalam');
    });

    test('every text style uses tabular figures', () {
      final styles = [
        theme.textTheme.displayLarge,
        theme.textTheme.headlineMedium,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelSmall,
      ];
      for (final s in styles) {
        expect(s!.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
    });

    test('touch targets are padded to 48', () {
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(t.minTouch, 48);
    });
  });

  testWidgets('bundled font files load', (tester) async {
    for (final f in [
      'AnekMalayalam-600',
      'AnekMalayalam-700',
      'Inter-400',
      'Inter-500',
      'Inter-600',
      'Inter-700',
      'NotoSansMalayalam-400',
      'NotoSansMalayalam-500',
      'NotoSansMalayalam-600',
      'NotoSansMalayalam-700',
    ]) {
      final data = await rootBundle.load('assets/fonts/$f.ttf');
      expect(data.lengthInBytes, greaterThan(10000), reason: f);
    }
  });
}
