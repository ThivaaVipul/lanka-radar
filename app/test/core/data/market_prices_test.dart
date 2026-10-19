import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/market_prices.dart';
import 'package:lanka_radar/core/data/market_report.dart';
import 'package:lanka_radar/core/data/price_history.dart';

import '../../helpers/fake_sources.dart';

void main() {
  final prices = MarketPrices.fromJson(marketDataset);
  final latest = DateTime(2026, 10, 19);

  test("reads the report's days and each market's prices", () {
    expect(prices.days, [DateTime(2026, 10, 16), latest]);
    expect(prices.latest, latest);
    final beans = prices.good('Beans')!;
    expect(beans.section, 'Vegetables');
    expect(beans.prices['Narahenpita'], [
      PricePoint(DateTime(2026, 10, 16), 650),
      PricePoint(latest, 700),
    ]);
    expect(beans.markets, ['Narahenpita', 'Pettah', 'Dambulla']);
    expect(prices.good('Red Onion (Imp)')!.markets, ['Pettah']);
    expect(prices.good('Balaya')!.prices['Negombo'], hasLength(1));
  });

  test("quotes Narahenpita's price, then Pettah's, then Negombo's", () {
    final quotes = {for (final quote in prices.quotes) quote.good.name: quote};

    expect(quotes['Beans']!.market, 'Narahenpita');
    expect(quotes['Beans']!.price, 700);
    expect(quotes['Beans']!.before, 650);
    expect(quotes['Red Onion (Imp)']!.market, 'Pettah');
    expect(quotes['Thalapath']!.market, 'Negombo');
  });

  test('leaves out goods the latest report has no price for', () {
    expect(
      [for (final quote in prices.quotes) quote.good.name],
      ['Beans', 'Red Onion (Imp)', 'Egg (White)', 'Thalapath', 'Samba'],
    );
  });

  test('says what a price is for', () {
    expect(prices.good('Beans')!.perUnit, 'per kg');
    expect(prices.good('Egg (White)')!.perUnit, 'each');
    expect(
      const MarketGood(
        name: 'Coconut oil',
        unit: 'l',
        section: 'Other',
      ).perUnit,
      'per litre',
    );
  });

  test('is empty before the workflow has written it', () {
    expect(MarketPrices.fromJson(null).quotes, isEmpty);
    expect(MarketPrices.fromJson(null).latest, isNull);
  });

  test('a report adds its day, and the JSON reads back the same', () {
    final tuesday = DateTime(2026, 10, 20);
    final next = prices
        .withReport(tuesday, const [
          ReportRow(
            name: 'Beans',
            unit: 'kg',
            section: 'Vegetables',
            retail: {'Narahenpita': 720, 'Pettah': null},
          ),
          ReportRow(
            name: 'Carrot',
            unit: 'kg',
            section: 'Vegetables',
            retail: {'Pettah': 230},
          ),
        ])
        .skipping(DateTime(2026, 10, 21));

    expect(next.latest, tuesday);
    final beans = next.good('Beans')!.quoteOn(tuesday)!;
    expect(
      (beans.market, beans.price, beans.before),
      ('Narahenpita', 720, 700),
    );
    expect(next.good('Beans')!.prices['Pettah'], hasLength(2));
    expect(next.good('Carrot')!.markets, ['Pettah']);
    expect(MarketPrices.fromJson(jsonEncode(next.toJson())), next);
  });

  test('a report read again replaces its day', () {
    final again = prices.withReport(latest, const [
      ReportRow(
        name: 'Beans',
        unit: 'kg',
        section: 'Vegetables',
        retail: {'Narahenpita': 710},
      ),
    ]);

    expect(again.days, prices.days);
    expect(again.good('Beans')!.prices['Narahenpita']!.last.value, 710);
  });
}
