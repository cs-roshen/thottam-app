import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/split/split.dart';

void main() {
  const coconut = SplitTarget('c', templateWeight: 60, areaShare: 50000);
  const pepper = SplitTarget('p', templateWeight: 30, areaShare: 30000);
  const banana = SplitTarget('b', templateWeight: 10, areaShare: 20000);

  test('₹3,600 by template share 60 / 30 / 10 → ₹2,160, ₹1,080, ₹360', () {
    expect(
      splitAmount(360000, const [
        coconut,
        pepper,
        banana,
      ], SplitMode.templateShare),
      [216000, 108000, 36000],
    );
  });

  test('₹100 equally across three → ₹33.34, ₹33.33, ₹33.33', () {
    expect(
      splitAmount(10000, const [coconut, pepper, banana], SplitMode.equal),
      [3334, 3333, 3333],
    );
  });

  test('₹3,333 split 50.5% / 49.5% → ₹1,683.17 and ₹1,649.83', () {
    expect(
      splitAmount(333300, const [
        SplitTarget('a', templateWeight: 50.5),
        SplitTarget('b', templateWeight: 49.5),
      ], SplitMode.templateShare),
      [168317, 164983],
    );
  });

  test('by area and by plants', () {
    expect(
      splitAmount(100000, const [coconut, pepper, banana], SplitMode.area),
      [50000, 30000, 20000],
    );
    expect(
      splitAmount(90000, const [
        SplitTarget('a', plantCount: 60),
        SplitTarget('b', plantCount: 120),
      ], SplitMode.plants),
      [30000, 60000],
    );
  });

  test('a missing figure shares equally rather than leaving a crop out', () {
    expect(
      splitAmount(90000, const [
        SplitTarget('a', plantCount: 60),
        SplitTarget('b'),
      ], SplitMode.plants),
      [45000, 45000],
    );
  });

  group('editing one part by hand', () {
    test('the others share the rest in their proportions; the total holds', () {
      final parts = rebalance(360000, [216000, 108000, 36000], 0, 200000);
      expect(parts[0], 200000);
      expect(parts.reduce((a, b) => a + b), 360000);
      expect(parts, [200000, 120000, 40000]);
    });

    test('a part set earlier stays while it fits', () {
      final parts = rebalance(
        360000,
        [200000, 120000, 40000],
        1,
        100000,
        fixed: {0},
      );
      expect(parts, [200000, 100000, 60000]);
    });

    test('more than the total is cut to the total', () {
      expect(rebalance(10000, [5000, 5000], 0, 99999), [10000, 0]);
    });

    test(
      'with every other part fixed, the edited part takes the difference',
      () {
        expect(rebalance(10000, [5000, 5000], 0, 3000, fixed: {1}), [
          5000,
          5000,
        ]);
      },
    );

    test('the amount changes after a manual edit: the split still sums', () {
      // the farmer set coconut to ₹2,000, then the amount became ₹4,000
      final edited = rebalance(360000, [216000, 108000, 36000], 0, 200000);
      final next = rebalance(400000, edited, 0, edited[0]);
      expect(next[0], 200000);
      expect(next.reduce((a, b) => a + b), 400000);
    });
  });
}
