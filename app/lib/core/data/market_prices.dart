import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/market_report.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/format/dates.dart';

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

/// The market prices the phone has read from the Central Bank's reports, kept
/// as JSON: each good's prices are columns by day.
final class MarketPrices extends Equatable {
  const MarketPrices({
    this.days = const [],
    this.goods = const [],
    this.skipped = const [],
  });

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
      skipped: [
        for (final day in json['skipped'] as List<Object?>? ?? const [])
          if (day is String) DateTime.parse(day),
      ],
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

  /// Listed reports that couldn't be read, so they aren't tried again.
  final List<DateTime> skipped;

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

  /// With [day]'s report added, or put in place of what that day had.
  MarketPrices withReport(DateTime day, List<ReportRow> rows) {
    final goods = {for (final good in this.goods) good.name: good};
    for (final row in rows) {
      final prices = {
        for (final MapEntry(key: market, value: points)
            in goods[row.name]?.prices.entries ??
                const <MapEntry<String, List<PricePoint>>>[])
          market: [
            for (final point in points)
              if (point.day != day) point,
          ],
      };
      for (final MapEntry(key: market, value: price) in row.retail.entries) {
        if (price != null) {
          (prices[market] ??= []).add(PricePoint(day, price));
        }
      }
      for (final points in prices.values) {
        points.sort((a, b) => a.day.compareTo(b.day));
      }
      goods[row.name] = MarketGood(
        name: row.name,
        unit: row.unit,
        section: row.section,
        prices: prices,
      );
    }
    return MarketPrices(
      days: {...days, day}.toList()..sort(),
      goods: goods.values.toList(),
      skipped: skipped,
    );
  }

  /// With [day]'s report marked as not readable.
  MarketPrices skipping(DateTime day) =>
      MarketPrices(days: days, goods: goods, skipped: [...skipped, day]);

  Map<String, Object?> toJson() => {
    'days': [for (final day in days) isoDay(day)],
    'skipped': [for (final day in skipped) isoDay(day)],
    'items': [
      for (final good in goods)
        {
          'name': good.name,
          'unit': good.unit,
          'section': good.section,
          'prices': {
            for (final MapEntry(key: market, value: points)
                in good.prices.entries)
              market: _column(points),
          },
        },
    ],
  };

  /// [points] as a column with a price or null for each of [days].
  List<double?> _column(List<PricePoint> points) {
    final byDay = {for (final point in points) point.day: point.value};
    return [for (final day in days) byDay[day]];
  }

  @override
  List<Object?> get props => [days, goods, skipped];
}
