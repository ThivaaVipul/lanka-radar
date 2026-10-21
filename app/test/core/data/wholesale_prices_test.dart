import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/harti_bulletin.dart';
import 'package:lanka_radar/core/data/wholesale_prices.dart';

WholesaleRow beans(PriceRange dambulla, {PriceRange? kandy}) => WholesaleRow(
  name: 'Beans',
  group: 'Vegetables',
  unit: 'kg',
  prices: {'Dambulla': dambulla, 'Kandy': ?kandy},
);

const samba = WholesaleRow(
  name: 'Samba 1',
  group: 'Rice',
  unit: 'kg',
  prices: {'Pettah': (low: 225, high: 230)},
);

void main() {
  final monday = DateTime(2026, 10, 19);
  final tuesday = DateTime(2026, 10, 20);

  test("a day's quotes come with the day before's", () {
    final prices = const WholesalePrices()
        .withBulletin(monday, [beans((low: 380, high: 420)), samba])
        .withBulletin(tuesday, [
          beans((low: 350, high: 450), kandy: (low: 400, high: 450)),
        ]);

    final [quote] = prices.quotes('Vegetables', centre: 'Dambulla');
    expect(quote.now, RangePoint(tuesday, 350, 450));
    expect(quote.before, RangePoint(monday, 380, 420));
    expect(quote.now.middle, 400);
    expect(prices.quotes('Vegetables', centre: 'Kandy').single.before, isNull);
    // Samba wasn't in Tuesday's bulletin.
    expect(prices.quotes('Rice', centre: 'Dambulla'), isEmpty);
    expect(prices.good('Beans')!.markets, ['Kandy', 'Dambulla']);
  });

  test('round trips through JSON, a day read again replacing it', () {
    final prices = const WholesalePrices()
        .withBulletin(monday, [beans((low: 380, high: 420)), samba])
        .withBulletin(tuesday, [beans((low: 350, high: 450))])
        .withBulletin(tuesday, [beans((low: 360, high: 450))])
        .skipping(DateTime(2026, 10, 18));

    final again = WholesalePrices.fromJson(jsonEncode(prices.toJson()));

    expect(again, prices);
    expect(again.good('Beans')!.prices['Dambulla']!.last.low, 360);
    expect(again.skipped, [DateTime(2026, 10, 18)]);
  });
}
