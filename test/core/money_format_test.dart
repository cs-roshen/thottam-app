import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/money/money_format.dart';

void main() {
  test('Indian grouping, no paise when whole', () {
    expect(formatPaise(18450000), '₹1,84,500');
    expect(formatPaise(10000), '₹100');
    expect(formatPaise(100), '₹1');
    expect(formatPaise(0), '₹0');
  });

  test('lakh and crore grouping', () {
    expect(formatPaise(1234567800), '₹1,23,45,678');
    expect(formatPaise(100000000), '₹10,00,000');
  });

  test('paise shown to two places when not whole', () {
    expect(formatPaise(46360), '₹463.60');
    expect(formatPaise(7083), '₹70.83');
    expect(formatPaise(5), '₹0.05');
  });

  test('negative amounts carry a minus sign', () {
    expect(formatPaise(-50000), '−₹500');
    expect(formatPaise(-1), '−₹0.01');
  });
}
