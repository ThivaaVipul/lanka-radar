import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/price_history.dart';

FeedItem order(
  String published,
  List<KeyNumber> numbers, {
  String? effective,
  String source = 'gazettes',
}) => FeedItem(
  id: 'gazette-$published',
  source: source,
  topic: 'prices',
  headlineEn: 'An order',
  published: DateTime.parse(published),
  effective: effective == null ? null : DateTime.parse(effective),
  keyNumbers: numbers,
);

KeyNumber price(String label, double value) =>
    KeyNumber(label: label, value: value, unit: 'LKR');

void main() {
  test("a fuel's history joins the gazettes and what CEYPETCO said", () {
    final items = [
      order('2026-08-31', [price('Lanka Petrol 92 Octane', 399)]),
      order('2026-05-30', [
        price('Lanka Petrol 92 Octane', 434),
      ], effective: '2026-06-01'),
    ];
    final rows = [
      const FuelPriceRow(
        product: 'Lanka Petrol 92 Octane',
        effective: '2026-09-30',
        price: 414,
      ),
      const FuelPriceRow(
        product: 'Lanka Auto Diesel',
        effective: '2026-09-30',
        price: 392,
      ),
    ];

    expect(fuelHistory('Petrol 92', rows, items), [
      PricePoint(DateTime(2026, 6), 434),
      PricePoint(DateTime(2026, 8, 31), 399),
      PricePoint(DateTime(2026, 9, 30), 414),
    ]);
  });

  test(
    "the rate joins the workflow's copy and the phone's, the phone's first",
    () {
      const dataset =
          '{"rates": [{"date": "2026-10-01", "rate": 330.7}, '
          '{"date": "2026-10-02", "rate": 330.9}]}';
      final phone = [
        const RateRow(day: '2026-10-02', rate: 331),
        const RateRow(day: '2026-10-05', rate: 331.2),
      ];

      expect(rateHistory(dataset, phone), [
        PricePoint(DateTime(2026, 10), 330.7),
        PricePoint(DateTime(2026, 10, 2), 331),
        PricePoint(DateTime(2026, 10, 5), 331.2),
      ]);
    },
  );

  test('goods keep their prices across orders, without fuel or gas', () {
    final items = [
      order('2026-09-04', [
        price('Tuna 155g', 220),
        price('Lanka Auto Diesel', 1),
      ]),
      order('2026-03-10', [price('Tuna 155g', 240)]),
      order('2026-10-06', [price('Litro 12.5kg', 3690)], source: 'gas'),
    ];

    expect(goodsHistory(items), {
      'Tuna 155g': [
        PricePoint(DateTime(2026, 3, 10), 240),
        PricePoint(DateTime(2026, 9, 4), 220),
      ],
    });
  });

  test('a range starts with the price in force at its start', () {
    final points = [
      PricePoint(DateTime(2026, 6), 434),
      PricePoint(DateTime(2026, 8, 31), 399),
      PricePoint(DateTime(2026, 9, 30), 414),
    ];

    expect(since(points, DateTime(2026, 9)), [
      PricePoint(DateTime(2026, 9), 399),
      PricePoint(DateTime(2026, 9, 30), 414),
    ]);
    expect(since(points, DateTime(2026, 8, 31)), points.skip(1).toList());
    expect(since(points, DateTime(2026, 1)), points);
  });
}
