import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/units/units.dart';

void main() {
  // The same factors the wave 1 template seed carries.
  final templates = [
    Unit.fromTemplate('kg', {'dimension': 'mass', 'factor': 1}),
    Unit.fromTemplate('g', {'dimension': 'mass', 'factor': 0.001}),
    Unit.fromTemplate('quintal', {'dimension': 'mass', 'factor': 100}),
    Unit.fromTemplate('cent', {'dimension': 'area', 'factor': 1}),
    Unit.fromTemplate('acre', {'dimension': 'area', 'factor': 100}),
    Unit.fromTemplate('hectare', {'dimension': 'area', 'factor': 247.105}),
    Unit.fromTemplate('bunch', {'dimension': 'count', 'factor': 1}),
    Unit.fromTemplate('para', {'dimension': 'mass', 'factor': null}),
  ];

  test('same dimension converts through the base unit', () {
    final u = Units(templates);
    expect(u.convert(2500, 'quintal', 'kg'), 250000); // 2.5 q → 250 kg
    expect(u.convert(1500, 'g', 'kg'), 2); // 1.5 g → 0.0015 kg → 0.002
    expect(u.convert(1000, 'hectare', 'acre'), 2471); // 2.47105 → 2.471
    expect(u.convert(1000, 'acre', 'hectare'), 405); // 0.404686 → 0.405
    expect(u.convert(1234, 'kg', 'kg'), 1234);
  });

  test('no conversion across dimensions or to a unit without a factor', () {
    final u = Units(templates);
    expect(u.convert(1000, 'kg', 'cent'), isNull);
    expect(u.convert(1000, 'para', 'kg'), isNull);
    expect(u.convert(1000, 'kg', 'unknown'), isNull);
  });

  test('a farmer\'s own ratio converts local units, both ways', () {
    final u = Units(templates, ratios: [const UnitRatio('para', 'kg', '7')]);
    expect(u.convert(3000, 'para', 'kg'), 21000);
    expect(u.convert(21000, 'kg', 'para'), 3000);
    expect(u.convert(10000, 'kg', 'para'), 1429); // 1.428571… → 1.429
    // one hop further through the template: 3 para → 21 kg → 0.21 quintal
    expect(u.convert(3000, 'para', 'quintal'), 210);
    expect(u.convert(210, 'quintal', 'para'), 3000);
  });

  test('a farmer\'s ratio wins over the template for that pair', () {
    final u = Units(
      templates,
      ratios: [const UnitRatio('bunch', 'kg', '12.5')],
    );
    expect(u.convert(2000, 'bunch', 'kg'), 25000);
  });

  test('a zero ratio gives no conversion instead of a crash', () {
    final u = Units(templates, ratios: [const UnitRatio('para', 'kg', '0')]);
    expect(u.convert(1000, 'kg', 'para'), isNull);
  });
}
