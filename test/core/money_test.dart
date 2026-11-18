import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/money/money.dart';
import 'package:thottam/core/money/money_format.dart';
import 'package:thottam/core/money/money_parse.dart';

void main() {
  group('stored amounts round once, half away from zero (spec rule 8)', () {
    test('12.5 kg at ₹64.33 is stored as ₹804.13', () {
      expect(amountForQuantity(12500, 6433), 80413);
    });

    test('attendance 900, 900, 700, 900 full, full, half, absent → ₹2,150', () {
      final wages = [
        mulDivRound(90000, 1000, 1000),
        mulDivRound(90000, 1000, 1000),
        mulDivRound(70000, 500, 1000),
        mulDivRound(90000, 0, 1000),
      ];
      expect(wages.reduce((a, b) => a + b), 215000);
    });

    test('overtime: ₹900 full day plus 2 hours at ₹150 → ₹1,200', () {
      expect(90000 + amountForQuantity(2000, 15000), 120000);
    });

    test('unnamed group: 5 at ₹800 and 1 at ₹1,200 → ₹5,200', () {
      expect(
        amountForQuantity(5000, 80000) + amountForQuantity(1000, 120000),
        520000,
      );
    });

    test('halves go away from zero, both signs', () {
      expect(mulDivRound(1, 1, 2), 1);
      expect(mulDivRound(-1, 1, 2), -1);
      expect(mulDivRound(3, 1, 2), 2);
      expect(mulDivRound(-3, 1, 2), -2);
      expect(mulDivRound(1, 1, 3), 0);
      expect(mulDivRound(2, 1, 3), 1);
      expect(mulDivRound(-2, 1, 3), -1);
      expect(mulDivRound(1, -1, 2), -1);
    });

    test(
      'per-unit figures are for display only: ₹8,500 over 120 kg → ₹70.83',
      () {
        expect(formatPaise(mulDivRound(850000, 1000, 120000)), '₹70.83');
      },
    );

    test('very large values do not overflow', () {
      expect(amountForQuantity(9000000000000, 9000000), 81000000000000000);
    });
  });

  group('splits use the largest-remainder rule (spec rule 8)', () {
    test('₹3,600 at 60 / 30 / 10 → ₹2,160, ₹1,080, ₹360', () {
      expect(splitPaise(360000, [60, 30, 10]), [216000, 108000, 36000]);
    });

    test('₹100 in three equal parts → ₹33.34, ₹33.33, ₹33.33', () {
      expect(splitPaise(10000, [1, 1, 1]), [3334, 3333, 3333]);
    });

    test('₹3,333 at 50.5% / 49.5% → ₹1,683.17 and ₹1,649.83', () {
      expect(splitPaise(333300, [50500, 49500]), [168317, 164983]);
    });

    test('leftover paise go to the largest remainders first', () {
      // 100 paise by 1/1/1/2: 20, 20, 20, 40 exactly; by 3/3/1: 42.86, 42.86, 14.29
      expect(splitPaise(100, [3, 3, 1]), [43, 43, 14]);
      expect(splitPaise(10, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), [
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, //
      ]);
    });

    test('a zero weight gets nothing, negative amounts split as refunds', () {
      expect(splitPaise(1000, [0, 1]), [0, 1000]);
      expect(splitPaise(-10000, [1, 1, 1]), [-3334, -3333, -3333]);
    });

    test('bad weights are rejected', () {
      expect(() => splitPaise(100, []), throwsArgumentError);
      expect(() => splitPaise(100, [0, 0]), throwsArgumentError);
      expect(() => splitPaise(100, [1, -1]), throwsArgumentError);
    });

    test(
      'property: parts always sum to the amount and stay within a paisa',
      () {
        final r = Random(7);
        for (var i = 0; i < 20000; i++) {
          final amount = r.nextInt(1 << 31) * (r.nextBool() ? 1 : 1000);
          final weights = List.generate(
            1 + r.nextInt(8),
            (_) => r.nextInt(100000),
          );
          if (weights.every((w) => w == 0)) weights[0] = 1;
          final parts = splitPaise(amount, weights);
          expect(parts.reduce((a, b) => a + b), amount);
          final total = weights.reduce((a, b) => a + b);
          for (var k = 0; k < parts.length; k++) {
            final exact = amount * weights[k] / total;
            expect((parts[k] - exact).abs() < 1.0001, isTrue);
          }
        }
      },
    );
  });

  group('format and parse', () {
    test('property: formatting then parsing gives the same paise', () {
      final r = Random(11);
      for (var i = 0; i < 20000; i++) {
        final paise = r.nextInt(1 << 32) * (r.nextBool() ? 1 : 100);
        expect(parseRupeesToPaise(formatPaise(paise)), paise);
      }
      expect(parseRupeesToPaise(formatPaise(0)), 0);
    });

    test('negative input is not an amount', () {
      expect(parseRupeesToPaise('-5'), isNull);
      expect(parseRupeesToPaise(formatPaise(-500)), isNull);
    });

    test('quantities show one decimal only when it is not zero', () {
      expect(formatQuantity(120000), '120');
      expect(formatQuantity(12500), '12.5');
      expect(formatQuantity(12549), '12.5');
      expect(formatQuantity(12550), '12.6');
      expect(formatQuantity(-12550), '−12.6');
      expect(formatQuantity(123456789), '1,23,456.8');
      expect(formatQuantity(40), '0');
    });
  });
}
