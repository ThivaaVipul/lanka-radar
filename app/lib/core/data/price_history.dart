import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/rate_moves.dart';
import 'package:lanka_radar/core/format/labels.dart';

/// A price on a day.
final class PricePoint extends Equatable {
  const PricePoint(this.day, this.value);

  final DateTime day;
  final double value;

  @override
  List<Object?> get props => [day, value];
}

/// A fuel's prices over time, oldest first: the fuel revision gazettes' (from
/// the day each took effect) and CEYPETCO's as the phone saw them, which win
/// on the same day.
List<PricePoint> fuelHistory(
  String name,
  List<FuelPriceRow> rows,
  List<FeedItem> items,
) {
  final byDay = <DateTime, double>{};
  for (final item in items) {
    if (item.topic != 'prices') {
      continue;
    }
    for (final number in item.keyNumbers) {
      if (shortLabel(number.label) == name) {
        byDay[_day(item.effective ?? item.published)] = number.value;
      }
    }
  }
  for (final row in rows) {
    if (shortLabel(row.product) == name) {
      byDay[_day(DateTime.parse(row.effective))] = row.price;
    }
  }
  return _points(byDay);
}

/// USD/LKR by day, oldest first: the workflow's copy of CBSL's rates since
/// January ([dataset], `datasets/usd-lkr.json`) with the rates the phone read
/// from CBSL itself, which win on the same day.
List<PricePoint> rateHistory(String? dataset, List<RateRow> phone) => _points({
  for (final MapEntry(key: day, value: rate) in datasetRates(dataset).entries)
    _day(DateTime.parse(day)): rate,
  for (final row in phone) _day(DateTime.parse(row.day)): row.rate,
});

/// The prices price orders set for goods other than fuel, by the good's name,
/// each oldest first.
Map<String, List<PricePoint>> goodsHistory(List<FeedItem> items) {
  final goods = <String, Map<DateTime, double>>{};
  for (final item in items) {
    if (item.topic != 'prices' || item.source == 'gas') {
      continue;
    }
    for (final number in item.keyNumbers) {
      final name = shortLabel(number.label);
      if (!fuelOrder.contains(name)) {
        goods.putIfAbsent(
          name,
          () => {},
        )[_day(item.effective ?? item.published)] = number.value;
      }
    }
  }
  return {
    for (final MapEntry(key: name, value: byDay) in goods.entries)
      name: _points(byDay),
  };
}

/// The latest price order for each good in [goodsHistory], by the good's
/// name: the one that set its current price.
Map<String, FeedItem> goodsOrders(List<FeedItem> items) {
  final orders = <String, FeedItem>{};
  for (final item in items) {
    if (item.topic != 'prices' || item.source == 'gas') {
      continue;
    }
    final day = _day(item.effective ?? item.published);
    for (final number in item.keyNumbers) {
      final name = shortLabel(number.label);
      final held = orders[name];
      if (!fuelOrder.contains(name) &&
          (held == null ||
              day.isAfter(_day(held.effective ?? held.published)))) {
        orders[name] = item;
      }
    }
  }
  return orders;
}

/// The points from [from] on, keeping the one in force at [from] so a step
/// chart starts at the right level.
List<PricePoint> since(List<PricePoint> points, DateTime from) {
  final earlier = [
    for (final point in points)
      if (point.day.isBefore(from)) point,
  ];
  final kept = [
    for (final point in points)
      if (!point.day.isBefore(from)) point,
  ];
  final startsThen = kept.isNotEmpty && kept.first.day == from;
  return [
    if (earlier.isNotEmpty && !startsThen) PricePoint(from, earlier.last.value),
    ...kept,
  ];
}

List<PricePoint> _points(Map<DateTime, double> byDay) => [
  for (final day in byDay.keys.toList()..sort()) PricePoint(day, byDay[day]!),
];

DateTime _day(DateTime time) => DateTime(time.year, time.month, time.day);
