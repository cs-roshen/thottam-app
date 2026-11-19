import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/features/harvest/domain/harvest_math.dart';

void main() {
  // the spec's harvest: Group A 6 at ₹800 with 75 kg, Group B 3 at ₹900
  // with 30 kg, one named worker at ₹1,000 with 15 kg
  const groupA = HarvestTeam(heads: 6, ratePaise: 80000, quantity: 75000);
  const groupB = HarvestTeam(heads: 3, ratePaise: 90000, quantity: 30000);
  const named = HarvestTeam(ratePaise: 100000, quantity: 15000, workerId: 'w');

  test('per-team quantity on: 120 kg, wages ₹8,500; Group A 12.5 kg per '
      'person and ₹64 per kg; overall 12 kg per person, ₹70.83 per kg', () {
    final s = summarise(const [groupA, groupB, named], perTeam: true);
    expect(s.quantity, 120000);
    expect(s.paidWagesPaise, 850000);
    expect(s.people, 10);
    expect(s.perPerson, 12000);
    expect(s.labourCostPerUnit, 7083); // 8,500 / 120 = 70.833…
    expect(teamRates(groupA), (12500, 6400));
  });

  test('per-team quantity off: the total entered stands; the summary is '
      'overall', () {
    const teams = [
      HarvestTeam(heads: 6, ratePaise: 80000),
      HarvestTeam(heads: 3, ratePaise: 90000),
      HarvestTeam(ratePaise: 100000, workerId: 'w'),
    ];
    final s = summarise(teams, perTeam: false, total: 120000);
    expect(s.quantity, 120000);
    expect(s.paidWagesPaise, 850000);
    expect(s.perPerson, 12000);
    expect(s.labourCostPerUnit, 7083);
  });

  test('removing a team recalculates', () {
    final s = summarise(const [groupA, named], perTeam: true);
    expect(s.quantity, 90000);
    expect(s.paidWagesPaise, 580000);
    expect(s.people, 7);
  });

  test('a piece-rate team is paid by its own quantity, even with per-team '
      'quantity off', () {
    const piece = HarvestTeam(
      heads: 2,
      ratePaise: 600, // ₹6 a kg
      pieceRate: true,
      quantity: 40000,
    );
    expect(piece.wagePaise, 24000);
    final s = summarise(const [groupA, piece], perTeam: false, total: 115000);
    expect(s.quantity, 115000);
    expect(s.paidWagesPaise, 480000 + 24000);
  });

  test('family labour is its own line and stays out of the cost per unit', () {
    const family = HarvestTeam(
      ratePaise: 100000,
      quantity: 15000,
      workerId: 'w',
      isFamily: true,
    );
    final s = summarise(const [groupA, groupB, family], perTeam: true);
    expect(s.paidWagesPaise, 750000);
    expect(s.familyWagesPaise, 100000);
    expect(s.labourCostPerUnit, 6250);
  });

  test('lot cost: ₹20,060 since the last harvest plus ₹8,500 wages → '
      '₹28,560, ₹238 per kg', () {
    final cost = lotCost(costsSincePaise: 2006000, paidWagesPaise: 850000);
    expect(cost, 2856000);
    expect(costPerUnit(cost, 120000), 23800);
  });

  test('with the ₹1,000 named worker as family the lot stores ₹27,560, '
      '₹229.67 per kg', () {
    final s = summarise(const [
      groupA,
      groupB,
      HarvestTeam(
        ratePaise: 100000,
        quantity: 15000,
        workerId: 'w',
        isFamily: true,
      ),
    ], perTeam: true);
    final cost = lotCost(
      costsSincePaise: 2006000,
      paidWagesPaise: s.paidWagesPaise,
    );
    expect(cost, 2756000);
    expect(costPerUnit(cost, 120000), 22967);
  });

  test('no people or no quantity shows nothing per unit', () {
    expect(summarise(const [], perTeam: true).perPerson, isNull);
    expect(summarise(const [groupA], perTeam: false).labourCostPerUnit, isNull);
    expect(costPerUnit(1000, 0), isNull);
  });
}
