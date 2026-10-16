import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';

final today = DateTime(2026, 10, 16);

FeedItem fuelGazette(DateTime published, double value, double previous) =>
    FeedItem(
      id: 'gazette-fuel-${published.month}',
      source: 'gazettes',
      topic: 'prices',
      headlineEn: 'Revise the Fuel Price',
      published: published,
      keyNumbers: [
        KeyNumber(
          label: 'Lanka Petrol 92 Octane',
          value: value,
          unit: 'LKR',
          previous: previous,
        ),
      ],
    );

FuelPriceRow row(String product, String effective, double price) =>
    FuelPriceRow(product: product, effective: effective, price: price);

NowData build({
  List<FuelPriceRow> fuelRows = const [],
  DateTime? fuelChecked,
  List<RateRow> rates = const [],
  String? backupRates,
  String? holidays,
  List<FeedItem> items = const [],
}) => buildNow(
  today: today,
  fuelRows: fuelRows,
  fuelChecked: fuelChecked,
  rates: rates,
  backupRates: backupRates,
  holidays: holidays,
  tamilNames: const {'Deepavali': 'TA Deepavali'},
  items: items,
);

void main() {
  group('fuel', () {
    test("lists CEYPETCO's prices in the card's order, with the price before "
        'from the phone', () {
      final now = build(
        fuelRows: [
          row('Lanka Auto Diesel', '2026-09-30', 392),
          row('Lanka Petrol 92 Octane', '2026-09-30', 414),
          row('Lanka Petrol 92 Octane', '2026-08-31', 399),
        ],
        fuelChecked: today,
      );

      expect(
        [for (final price in now.fuel) price.name],
        ['Petrol 92', 'Diesel'],
      );
      expect(now.fuel.first.price, 414);
      expect(now.fuel.first.since, DateTime(2026, 9, 30));
      expect(now.fuel.first.was, 399);
      expect(now.fuelChanged, DateTime(2026, 9, 30));
    });

    test('takes the price before from the gazette that was in force, or the '
        'one that set this price', () {
      final rows = [row('Lanka Petrol 92 Octane', '2026-09-30', 414)];
      final august = fuelGazette(DateTime(2026, 8, 31), 399, 414);

      expect(build(fuelRows: rows, items: [august]).fuel.first.was, 399);

      final september = fuelGazette(DateTime(2026, 9, 30), 414, 399);
      expect(
        build(fuelRows: rows, items: [september, august]).fuel.first.was,
        399,
      );
    });

    test('uses the latest fuel gazette until CEYPETCO first answers', () {
      final now = build(items: [fuelGazette(DateTime(2026, 8, 31), 399, 414)]);

      expect(now.fuelFromGazette, isTrue);
      expect(now.fuelAsOf, DateTime(2026, 8, 31));
      expect(now.fuel.single.price, 399);
      expect(now.fuel.single.was, 414);
    });
  });

  group('USD/LKR', () {
    test("uses CBSL's rates, newest first", () {
      final now = build(
        rates: [
          RateRow(day: '2026-10-16', rate: 331.286),
          RateRow(day: '2026-10-15', rate: 331.1235),
        ],
      );

      expect(now.ratesFromBackup, isFalse);
      expect(now.rates.first, RateNow(day: today, rate: 331.286));
    });

    test("falls back to the workflow's copy for the last 30 days", () {
      final backup = jsonEncode({
        'source': 'frankfurter',
        'rates': [
          {'date': '2026-08-01', 'rate': 300.0},
          {'date': '2026-10-08', 'rate': 330.5},
          {'date': '2026-10-09', 'rate': 330.9},
        ],
      });

      final now = build(backupRates: backup);

      expect(now.ratesFromBackup, isTrue);
      expect([for (final rate in now.rates) rate.rate], [330.9, 330.5]);
    });
  });

  test("holidays: this year's remaining ones, with Tamil names", () {
    final holidays = jsonEncode({
      'holidays': [
        {
          'date': '2026-10-06',
          'name': 'Vap Full Moon Poya Day',
          'tentative': false,
        },
        {'date': '2026-11-08', 'name': 'Deepavali', 'tentative': false},
        {'date': '2026-12-25', 'name': 'Christmas Day', 'tentative': true},
        {
          'date': '2027-01-14',
          'name': 'Tamil Thai Pongal Day',
          'tentative': false,
        },
      ],
    });

    final now = build(holidays: holidays);

    expect(now.holidays, [
      HolidayNow(
        day: DateTime(2026, 11, 8),
        name: 'Deepavali',
        tamil: 'TA Deepavali',
      ),
      HolidayNow(
        day: DateTime(2026, 12, 25),
        name: 'Christmas Day',
        tentative: true,
      ),
    ]);
  });

  test('the latest LP gas list and exam timetable', () {
    FeedItem item(
      String id,
      String source,
      String topic,
      Map<String, Object?> data,
    ) => FeedItem(
      id: id,
      source: source,
      topic: topic,
      headlineEn: id,
      published: today,
      data: data,
    );
    final items = [
      item('exam-1', 'exams', 'exams', const {'kind': 'school'}),
      item('exam-2', 'exams', 'exams', const {'kind': 'timetable'}),
      item('gas-litro-2026-10-06', 'gas', 'prices', const {}),
    ];

    final now = build(items: items);

    expect(now.timetable?.id, 'exam-2');
    expect(now.gas?.id, 'gas-litro-2026-10-06');
  });
}
