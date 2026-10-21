import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/harti_bulletin.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// The centre vegetables are shown for until another is picked.
const defaultWholesaleCentre = 'Dambulla';

/// A day's wholesale price range.
final class RangePoint extends Equatable {
  const RangePoint(this.day, this.low, this.high);

  final DateTime day;
  final double low;
  final double high;

  /// What the chart and the arrows go by.
  double get middle => (low + high) / 2;

  @override
  List<Object?> get props => [day, low, high];
}

/// A good in HARTI's bulletins, with its ranges at each market day by day.
final class WholesaleGood extends Equatable {
  const WholesaleGood({
    required this.name,
    required this.group,
    required this.unit,
    this.prices = const {},
  });

  final String name;

  /// Vegetables, Rice or Other.
  final String group;

  /// kg or egg.
  final String unit;

  /// Each market's ranges, oldest first; days it had none left out.
  final Map<String, List<RangePoint>> prices;

  String get perUnit => unit == 'egg' ? 'per egg' : 'per kg';

  /// The markets with prices: the centres in the bulletin's order, or Pettah.
  List<String> get markets => [
    for (final market in [...wholesaleCentres, foodsMarket])
      if (prices[market]?.isNotEmpty ?? false) market,
  ];

  /// What search matches it by.
  String get searchText => '$name $group wholesale harti';

  /// Each market's middle prices, for charting.
  Map<String, List<PricePoint>> get middles => {
    for (final MapEntry(key: market, value: points) in prices.entries)
      market: [for (final point in points) PricePoint(point.day, point.middle)],
  };

  /// Its range at [market] on [day], with the one before; null when the
  /// market had none that day.
  WholesaleQuote? quoteAt(String market, DateTime day) {
    final points = prices[market] ?? const <RangePoint>[];
    if (points.isEmpty || points.last.day != day) {
      return null;
    }
    return WholesaleQuote(
      good: this,
      market: market,
      now: points.last,
      before: points.length > 1 ? points[points.length - 2] : null,
    );
  }

  @override
  List<Object?> get props => [name, group, unit, prices];
}

/// A good's latest range at one market, and its range the day before.
final class WholesaleQuote extends Equatable {
  const WholesaleQuote({
    required this.good,
    required this.market,
    required this.now,
    this.before,
  });

  final WholesaleGood good;
  final String market;
  final RangePoint now;
  final RangePoint? before;

  @override
  List<Object?> get props => [good, market, now, before];
}

/// The wholesale prices the phone has read from HARTI's bulletins, kept as
/// JSON: each good's ranges are columns by day.
final class WholesalePrices extends Equatable {
  const WholesalePrices({
    this.days = const [],
    this.goods = const [],
    this.skipped = const [],
  });

  factory WholesalePrices.fromJson(String? body) {
    if (body == null) {
      return const WholesalePrices();
    }
    final json = jsonDecode(body) as Map<String, Object?>;
    final days = [
      for (final day in json['days'] as List<Object?>? ?? const [])
        if (day is String) DateTime.parse(day),
    ];
    return WholesalePrices(
      days: days,
      skipped: [
        for (final day in json['skipped'] as List<Object?>? ?? const [])
          if (day is String) DateTime.parse(day),
      ],
      goods: [
        for (final item in json['items'] as List<Object?>? ?? const [])
          if (item case {
            'name': final String name,
            'group': final String group,
            'unit': final String unit,
            'prices': final Map<String, Object?> prices,
          })
            WholesaleGood(
              name: name,
              group: group,
              unit: unit,
              prices: {
                for (final MapEntry(key: market, value: column)
                    in prices.entries)
                  if (column is List<Object?>)
                    market: [
                      for (final (index, range) in column.indexed)
                        if (range case [
                          final num low,
                          final num high,
                        ] when index < days.length)
                          RangePoint(
                            days[index],
                            low.toDouble(),
                            high.toDouble(),
                          ),
                    ],
              },
            ),
      ],
    );
  }

  /// Bulletin days, oldest first.
  final List<DateTime> days;

  /// In the bulletin's order.
  final List<WholesaleGood> goods;

  /// Listed bulletins that couldn't be read, so they aren't tried again.
  final List<DateTime> skipped;

  /// The latest bulletin's day.
  DateTime? get latest => days.lastOrNull;

  /// The good named [name] priced at [market]: a name can be both a
  /// vegetable at the centres and a dried food at Pettah (big onions,
  /// potatoes).
  WholesaleGood? good(String name, {String? market}) {
    for (final good in goods) {
      if (good.name == name &&
          (market == null || good.prices.containsKey(market))) {
        return good;
      }
    }
    return null;
  }

  /// The latest day's prices in [group]: vegetables at [centre], rice and
  /// dried foods at Pettah.
  List<WholesaleQuote> quotes(String group, {required String centre}) {
    final latest = this.latest;
    if (latest == null) {
      return const [];
    }
    final market = group == 'Vegetables' ? centre : foodsMarket;
    return [
      for (final good in goods)
        if (good.group == group) ?good.quoteAt(market, latest),
    ];
  }

  /// With [day]'s bulletin added, or put in place of what that day had.
  WholesalePrices withBulletin(DateTime day, List<WholesaleRow> rows) {
    // A good is its group and name: big onions are both vegetables at the
    // centres and dried foods at Pettah.
    final goods = {
      for (final good in this.goods) (good.group, good.name): good,
    };
    for (final row in rows) {
      final prices = {
        for (final MapEntry(key: market, value: points)
            in goods[(row.group, row.name)]?.prices.entries ??
                const <MapEntry<String, List<RangePoint>>>[])
          market: [
            for (final point in points)
              if (point.day != day) point,
          ],
      };
      for (final MapEntry(key: market, value: range) in row.prices.entries) {
        (prices[market] ??= []).add(RangePoint(day, range.low, range.high));
      }
      for (final points in prices.values) {
        points.sort((a, b) => a.day.compareTo(b.day));
      }
      goods[(row.group, row.name)] = WholesaleGood(
        name: row.name,
        group: row.group,
        unit: row.unit,
        prices: prices,
      );
    }
    return WholesalePrices(
      days: {...days, day}.toList()..sort(),
      goods: goods.values.toList(),
      skipped: skipped,
    );
  }

  /// With [day]'s bulletin marked as not readable.
  WholesalePrices skipping(DateTime day) =>
      WholesalePrices(days: days, goods: goods, skipped: [...skipped, day]);

  Map<String, Object?> toJson() => {
    'days': [for (final day in days) isoDay(day)],
    'skipped': [for (final day in skipped) isoDay(day)],
    'items': [
      for (final good in goods)
        {
          'name': good.name,
          'group': good.group,
          'unit': good.unit,
          'prices': {
            for (final MapEntry(key: market, value: points)
                in good.prices.entries)
              market: _column(points),
          },
        },
    ],
  };

  /// [points] as a column with a range or null for each of [days].
  List<List<double>?> _column(List<RangePoint> points) {
    final byDay = {for (final point in points) point.day: point};
    return [
      for (final day in days)
        if (byDay[day] case final point?) [point.low, point.high] else null,
    ];
  }

  @override
  List<Object?> get props => [days, goods, skipped];
}
