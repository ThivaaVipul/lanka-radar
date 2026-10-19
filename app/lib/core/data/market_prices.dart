import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/price_history.dart';

/// The markets a good's price is taken from, in order: Narahenpita's retail
/// price is the one shown, then Pettah's, and Negombo's for fish.
const marketOrder = ['Narahenpita', 'Pettah', 'Negombo', 'Dambulla'];

/// The report's sections in the order Prices offers them.
const marketSections = ['Vegetables', 'Fruits', 'Rice', 'Fish', 'Other'];

/// Other names people search for.
const _aliases = {
  'Papaw': 'papaya',
  'Red Dhal': 'dal lentils parippu',
  'Coconut (Avg.)': 'pol',
  'Sprat (Imp)': 'haal masso',
  'Katta (Imp)': 'dried fish',
};

/// A good in the Central Bank's Daily Price Report, with its retail prices.
final class MarketGood extends Equatable {
  const MarketGood({
    required this.name,
    required this.unit,
    required this.section,
    this.prices = const {},
  });

  final String name;

  /// kg, l, nut or each.
  final String unit;
  final String section;

  /// Each market's prices, oldest first; days the market had none left out.
  final Map<String, List<PricePoint>> prices;

  /// The markets with prices, in [marketOrder].
  List<String> get markets => [
    for (final market in marketOrder)
      if (prices[market]?.isNotEmpty ?? false) market,
  ];

  /// "per kg", "per litre", "per nut" or "each".
  String get perUnit => switch (unit) {
    'each' => 'each',
    'l' => 'per litre',
    _ => 'per $unit',
  };

  /// What search matches it by.
  String get searchText => '$name ${_aliases[name] ?? ''} $section market';

  /// Its price on report day [day], from the first market in [marketOrder]
  /// that had one; null when none did.
  MarketQuote? quoteOn(DateTime day) {
    for (final market in marketOrder) {
      final points = prices[market] ?? const <PricePoint>[];
      if (points.isNotEmpty && points.last.day == day) {
        return MarketQuote(
          good: this,
          market: market,
          price: points.last.value,
          before: points.length > 1 ? points[points.length - 2].value : null,
        );
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [name, unit, section, prices];
}

/// A good's latest price at one market, and its price in the report before.
final class MarketQuote extends Equatable {
  const MarketQuote({
    required this.good,
    required this.market,
    required this.price,
    this.before,
  });

  final MarketGood good;
  final String market;
  final double price;
  final double? before;

  @override
  List<Object?> get props => [good, market, price, before];
}

/// The workflow's `datasets/market-prices.json`: the report's days and goods.
final class MarketPrices extends Equatable {
  const MarketPrices({this.days = const [], this.goods = const []});

  factory MarketPrices.fromJson(String? body) {
    if (body == null) {
      return const MarketPrices();
    }
    final json = jsonDecode(body) as Map<String, Object?>;
    final days = [
      for (final day in json['days'] as List<Object?>? ?? const [])
        if (day is String) DateTime.parse(day),
    ];
    return MarketPrices(
      days: days,
      goods: [
        for (final item in json['items'] as List<Object?>? ?? const [])
          if (item case {
            'name': final String name,
            'unit': final String unit,
            'section': final String section,
            'prices': final Map<String, Object?> prices,
          })
            MarketGood(
              name: name,
              unit: unit,
              section: section,
              prices: {
                for (final MapEntry(key: market, value: column)
                    in prices.entries)
                  if (column is List<Object?>)
                    market: [
                      for (final (index, price) in column.indexed)
                        if (price is num && index < days.length)
                          PricePoint(days[index], price.toDouble()),
                    ],
              },
            ),
      ],
    );
  }

  /// Report days, oldest first.
  final List<DateTime> days;

  /// In the report's order.
  final List<MarketGood> goods;

  /// The latest report's day.
  DateTime? get latest => days.lastOrNull;

  /// The goods priced in the latest report, in the report's order.
  List<MarketQuote> get quotes {
    final latest = this.latest;
    if (latest == null) {
      return const [];
    }
    return [for (final good in goods) ?good.quoteOn(latest)];
  }

  MarketGood? good(String name) {
    for (final good in goods) {
      if (good.name == name) {
        return good;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [days, goods];
}
