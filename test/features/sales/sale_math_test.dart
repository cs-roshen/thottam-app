import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/features/sales/domain/sale_math.dart';

void main() {
  test('50 kg at ₹705 with ₹170 deductions → gross ₹35,250, net ₹35,080, '
      '₹701.60 a kg; at a lot cost of ₹238 a kg, profit ₹463.60 a kg', () {
    final g = gross(50000, 70500);
    expect(g, 3525000);
    final n = net(g, [17000]);
    expect(n, 3508000);
    expect(perUnit(n, 50000), 70160);
    // the lot: ₹28,560 for 120 kg is ₹238 a kg
    const lot = [LotTake(50000, 120000, 2856000)];
    expect(costPerSaleUnit(lot, 50000), 23800);
    expect(profitPerSaleUnit(n, lot, 50000), 46360);
  });

  test('30 kg from a lot at ₹238 a kg and 20 kg from one at ₹250 → '
      '₹242.80 a kg', () {
    const takes = [
      LotTake(30000, 120000, 2856000), // ₹238 a kg
      LotTake(20000, 100000, 2500000), // ₹250 a kg
    ];
    expect(costPerSaleUnit(takes, 50000), 24280);
  });

  test('a sale in another unit carries the lot cost in that unit: paddy '
      'harvested in kg, sold by the quintal', () {
    // 500 kg harvested for ₹10,000 (₹20 a kg); 3 quintal sold
    const takes = [LotTake(300000, 500000, 1000000)];
    expect(costPerSaleUnit(takes, 3000), 200000); // ₹2,000 a quintal
    final n = net(gross(3000, 260000), const []);
    expect(profitPerSaleUnit(n, takes, 3000), 60000);
  });

  test('stock is taken oldest first, never more than there is', () {
    const lots = [StockLot('old', 30000), StockLot('new', 100000)];
    expect(takeFrom(lots, 50000), [('old', 30000), ('new', 20000)]);
    expect(takeFrom(lots, 20000), [('old', 20000)]);
    expect(takeFrom(lots, 130001), isNull);
    // a part sale leaves the rest
    final taken = takeFrom(lots, 130000)!;
    expect(taken.fold<int>(0, (s, t) => s + t.$2), 130000);
  });

  test('nothing sold shows nothing per unit', () {
    expect(perUnit(100, 0), isNull);
    expect(costPerSaleUnit(const [], 0), isNull);
    expect(profitPerSaleUnit(100, const [], 0), isNull);
  });
}
