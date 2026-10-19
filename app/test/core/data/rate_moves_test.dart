import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/rate_moves.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// Rates on consecutive days from [start].
Map<String, double> series(DateTime start, List<double> rates) => {
  for (var day = 0; day < rates.length; day++)
    isoDay(DateTime(start.year, start.month, start.day + day)): rates[day],
};

void main() {
  // The same cases as the workflow's tests (scrapers/tests/sources/test_rates.py).
  test('reports a weekly move of 2% once', () {
    final moves = weeklyMoves(
      series(DateTime(2026, 3), [
        ...List.filled(8, 300.0),
        ...List.filled(10, 307.0),
      ]),
    );

    expect(moves, [const RateMove(day: '2026-03-09', rate: 307, weekAgo: 300)]);
    expect(moves.single.change.toStringAsFixed(4), '0.0233');
  });

  test('ignores small moves', () {
    final drift = [for (var day = 0; day < 40; day++) 300.0 + day * 0.1];

    expect(weeklyMoves(series(DateTime(2026, 3), drift)), isEmpty);
  });

  test('a week ago is the last rate on or before that day', () {
    final moves = weeklyMoves({
      '2026-03-02': 300,
      '2026-03-04': 301,
      '2026-03-12': 310,
    });

    expect(moves, [const RateMove(day: '2026-03-12', rate: 310, weekAgo: 301)]);
  });

  test('a move item reads naturally', () {
    final item = moveItem(
      const RateMove(day: '2026-03-09', rate: 294, weekAgo: 300),
    );

    expect(item['id'], 'rates-usd-lkr-2026-03-09');
    expect(item['headline'], {
      'en': 'USD/LKR down 2.0% in a week, to 294.00',
      'ta': null,
    });
    expect(item['alert'], isTrue);
  });

  test("the phone's item is the workflow's, field for field", () {
    // rates-usd-lkr-2026-05-22 as the workflow wrote it on the data branch.
    final workflow =
        jsonDecode('''
{
  "id": "rates-usd-lkr-2026-05-22",
  "source": "rates",
  "topic": "rates",
  "issuer": "Central Bank of Sri Lanka",
  "headline": {"en": "USD/LKR up 2.9% in a week, to 333.99", "ta": null},
  "keyNumbers": [
    {"label": "USD/LKR", "value": 333.9925, "unit": "LKR", "previous": 324.7184}
  ],
  "published": "2026-05-22",
  "effective": null,
  "links": {"page": "https://www.cbsl.gov.lk/en/rates-and-indicators/exchange-rates"},
  "data": {"change": 0.0286},
  "alert": true
}''')
            as Map<String, Object?>;

    final item = moveItem(
      const RateMove(day: '2026-05-22', rate: 333.9925, weekAgo: 324.7184),
    );

    expect(item, workflow);
  });

  test("reads the workflow's rates by day", () {
    expect(
      datasetRates(
        '{"source": "frankfurter", "rates": '
        '[{"date": "2026-10-01", "rate": 330.7005}]}',
      ),
      {'2026-10-01': 330.7005},
    );
    expect(datasetRates(null), isEmpty);
  });
}
