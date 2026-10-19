import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/market_prices.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/features/item/widgets/highlight.dart';
import 'package:lanka_radar/features/search/search_results.dart';

import '../../helpers/fake_branch.dart';

final day = DateTime(2026, 10, 19);

final now = NowData(
  fuel: [
    FuelNow(name: 'Petrol 92', price: 414, since: day, was: 399),
    FuelNow(name: 'Diesel', price: 392, since: day),
    FuelNow(name: 'Super Diesel', price: 528, since: day),
  ],
  rates: [RateNow(day: day, rate: 331.28)],
  gas: FeedItem(
    id: 'gas-litro',
    source: 'gas',
    topic: 'prices',
    headlineEn: 'Litro gas prices',
    published: day,
  ),
  market: MarketPrices.fromJson(marketDataset),
);

final holidays = [
  HolidayNow(
    day: DateTime(2026, 10, 25),
    name: 'Vap Full Moon Poya Day',
    tamil: 'TA-POYA',
  ),
  HolidayNow(day: DateTime(2026, 11, 8), name: 'Deepavali Festival Day'),
];

final order = FeedItem(
  id: 'gazette-2504-86',
  source: 'gazettes',
  topic: 'prices',
  headlineEn: 'Maximum retail prices',
  published: DateTime(2026, 9, 4),
  keyNumbers: const [
    KeyNumber(label: 'Tuna 155g', value: 220, unit: 'LKR'),
    KeyNumber(label: 'Lanka Auto Diesel', value: 392, unit: 'LKR'),
  ],
);

SearchResults search(String query, {List<FeedItem> notices = const []}) =>
    searchEverything(
      words: searchWords(query),
      notices: notices,
      now: now,
      holidays: holidays,
    );

void main() {
  test('finds current fuel prices by name, or all of them as fuel', () {
    expect(search('diesel').prices, [
      FuelHit(now.fuel[1]),
      FuelHit(now.fuel[2]),
    ]);
    expect(search('fuel').prices, hasLength(3));
  });

  test('finds USD/LKR and LP gas by the usual words', () {
    expect(search('dollar').prices, [RateHit(now.rates.first)]);
    expect(search('lpg').prices, [GasHit(now.gas!)]);
  });

  test("finds a price order's goods, but not its fuel, which is current", () {
    expect(search('tuna', notices: [order]).prices, [
      OrderPriceHit(order, order.keyNumbers.first),
    ]);
    expect(
      search('diesel', notices: [order]).prices.whereType<OrderPriceHit>(),
      isEmpty,
    );
  });

  test('finds market goods by name, section and other names', () {
    List<String> goods(String query) => [
      for (final hit in search(query).prices.whereType<MarketHit>())
        hit.quote.good.name,
    ];

    final beans = search('beans').prices.single as MarketHit;
    expect(beans.quote.market, 'Narahenpita');
    expect(beans.day, day);
    expect(goods('onion'), ['Red Onion (Imp)']);
    expect(goods('fish'), ['Thalapath']);
    expect(goods('market'), hasLength(5));
  });

  test('a word matches from its start: rice is not in price', () {
    expect(search('rice', notices: [order]).prices, [
      isA<MarketHit>().having((hit) => hit.quote.good.name, 'good', 'Samba'),
    ]);
    expect(search('dies').prices, hasLength(2));
  });

  test('finds holidays by name in English or Tamil', () {
    expect(search('poya').dates, [holidays.first]);
    expect(search('ta-poya').dates, [holidays.first]);
    expect(search('holiday').dates, hasLength(2));
  });

  test('every word must match', () {
    expect(search('super diesel').prices, [FuelHit(now.fuel[2])]);
    expect(search('diesel poya').isEmpty, isTrue);
  });

  test('matched words are picked out, case aside, overlaps merged', () {
    const strong = TextStyle(fontWeight: FontWeight.w700);
    final span = highlighted('Super Diesel', ['diesel', 'die'], strong: strong);

    expect(
      [
        for (final child in span.children!.cast<TextSpan>())
          (child.text, child.style == strong),
      ],
      [('Super ', false), ('Diesel', true)],
    );
  });
}
