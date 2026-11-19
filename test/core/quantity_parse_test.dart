import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/units/quantity_parse.dart';

void main() {
  test('typed quantities become thousandths of the unit', () {
    expect(parseQuantity('2.5'), 2500);
    expect(parseQuantity('1,200'), 1200000);
    expect(parseQuantity(' 0.125 '), 125);
    expect(parseQuantity('7.'), 7000);
    expect(parseQuantity('0'), 0);
    expect(parseQuantity('.5'), 500);
  });

  test('empty, negative and too precise input is refused', () {
    expect(parseQuantity(''), isNull);
    expect(parseQuantity('-1'), isNull);
    expect(parseQuantity('1.2345'), isNull);
    expect(parseQuantity('abc'), isNull);
    expect(parseQuantity('.'), isNull);
  });
}
