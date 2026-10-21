import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/gas_prices.dart';
import 'package:lanka_radar/core/data/market_prices.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/data/wholesale_prices.dart';
import 'package:lanka_radar/core/format/labels.dart';

/// The fuels in the order the Now card lists them.
const fuelOrder = [
  'Petrol 92',
  'Petrol 95',
  'Diesel',
  'Super Diesel',
  'Kerosene',
  'Industrial kerosene',
];

/// A value older than this shows its own date ("as of 14 Oct").
const staleAfter = Duration(days: 1);

final class FuelNow extends Equatable {
  const FuelNow({
    required this.name,
    required this.price,
    required this.since,
    this.was,
  });

  final String name;
  final double price;

  /// The day this price started.
  final DateTime since;

  /// The price before it, when the phone or a gazette knows it.
  final double? was;

  @override
  List<Object?> get props => [name, price, since, was];
}

final class RateNow extends Equatable {
  const RateNow({required this.day, required this.rate});

  final DateTime day;

  /// Rupees for a dollar.
  final double rate;

  @override
  List<Object?> get props => [day, rate];
}

final class HolidayNow extends Equatable {
  const HolidayNow({
    required this.day,
    required this.name,
    this.tamil,
    this.tentative = false,
  });

  final DateTime day;
  final String name;
  final String? tamil;
  final bool tentative;

  @override
  List<Object?> get props => [day, name, tamil, tentative];
}

/// What the Now card shows.
final class NowData extends Equatable {
  const NowData({
    this.fuel = const [],
    this.fuelHistories = const {},
    this.fuelAsOf,
    this.fuelFromGazette = false,
    this.rates = const [],
    this.ratesFromBackup = false,
    this.holidays = const [],
    this.gas,
    this.laugfs,
    this.timetable,
    this.market = const MarketPrices(),
    this.wholesale = const WholesalePrices(),
    this.power,
  });

  final List<FuelNow> fuel;

  /// Each fuel's prices this year, oldest first, for its sparkline.
  final Map<String, List<PricePoint>> fuelHistories;

  /// When CEYPETCO last answered or, before it ever has, the date of the fuel
  /// gazette the prices come from.
  final DateTime? fuelAsOf;
  final bool fuelFromGazette;

  /// The last 30 days, newest first.
  final List<RateNow> rates;

  /// The rates are the workflow's copy, because CBSL hasn't answered.
  final bool ratesFromBackup;

  /// The holidays left this year (next year's once this year's are over).
  final List<HolidayNow> holidays;

  /// The latest LP gas price list (Litro's).
  final FeedItem? gas;

  /// Laugfs's LP gas prices.
  final GasTable? laugfs;

  /// The latest exam timetable.
  final FeedItem? timetable;

  /// The Central Bank's daily retail prices.
  final MarketPrices market;

  /// HARTI's daily wholesale prices.
  final WholesalePrices wholesale;

  /// Power cuts at the places watched; null until a place is set.
  final PowerNow? power;

  /// The day the newest fuel price started.
  DateTime? get fuelChanged => fuel.isEmpty
      ? null
      : fuel.map((price) => price.since).reduce((a, b) => a.isAfter(b) ? a : b);

  @override
  List<Object?> get props => [
    fuel,
    fuelHistories,
    fuelAsOf,
    fuelFromGazette,
    rates,
    ratesFromBackup,
    holidays,
    gas,
    laugfs,
    timetable,
    market,
    wholesale,
    power,
  ];
}

/// Puts the Now card together from what the phone has stored. [today] is a day
/// (midnight); [fuelChecked] and [ratesChecked] are when CEYPETCO and CBSL last
/// answered.
NowData buildNow({
  required DateTime today,
  required List<FuelPriceRow> fuelRows,
  required DateTime? fuelChecked,
  required List<RateRow> rates,
  required String? backupRates,
  required String? holidays,
  required Map<String, String> tamilNames,
  required List<FeedItem> items,
  MarketPrices market = const MarketPrices(),
  WholesalePrices wholesale = const WholesalePrices(),
  PowerNow? power,
  String? laugfs,
}) {
  final gazettes = _fuelGazettes(items);
  final fromGazette = fuelRows.isEmpty && gazettes.isNotEmpty;
  final fuel = fromGazette
      ? _fuelFromGazette(gazettes.first)
      : _fuelFromRows(fuelRows, gazettes);
  return NowData(
    fuel: fuel,
    fuelHistories: {
      for (final price in fuel)
        price.name: fuelHistory(price.name, fuelRows, items),
    },
    fuelAsOf: fromGazette ? gazettes.first.published : fuelChecked,
    fuelFromGazette: fromGazette,
    rates: rates.isNotEmpty ? _rates(rates) : _backup(backupRates, today),
    ratesFromBackup: rates.isEmpty,
    holidays: _holidays(holidays, today, tamilNames),
    gas: _latest(items, (item) => item.source == 'gas'),
    laugfs: GasTable.parse(laugfs),
    timetable: _latest(
      items,
      (item) => item.topic == 'exams' && item.data['kind'] == 'timetable',
    ),
    market: market,
    wholesale: wholesale,
    power: power,
  );
}

FeedItem? _latest(List<FeedItem> items, bool Function(FeedItem) test) {
  for (final item in items) {
    if (test(item)) {
      return item;
    }
  }
  return null;
}

/// Gazettes with fuel prices among their key numbers, newest first.
List<FeedItem> _fuelGazettes(List<FeedItem> items) => [
  for (final item in items)
    if (item.keyNumbers.any(
      (number) => fuelOrder.contains(shortLabel(number.label)),
    ))
      item,
];

List<FuelNow> _fuelFromGazette(FeedItem gazette) => _ordered([
  for (final number in gazette.keyNumbers)
    if (fuelOrder.contains(shortLabel(number.label)))
      FuelNow(
        name: shortLabel(number.label),
        price: number.value,
        since: gazette.effective ?? gazette.published,
        was: number.previous,
      ),
]);

List<FuelNow> _fuelFromRows(List<FuelPriceRow> rows, List<FeedItem> gazettes) {
  final byProduct = <String, List<FuelPriceRow>>{};
  for (final row in rows) {
    byProduct.putIfAbsent(shortLabel(row.product), () => []).add(row);
  }
  return _ordered([
    for (final MapEntry(key: name, value: history) in byProduct.entries)
      _fuelNow(
        name,
        history..sort((a, b) => b.effective.compareTo(a.effective)),
        gazettes,
      ),
  ]);
}

FuelNow _fuelNow(
  String name,
  List<FuelPriceRow> history,
  List<FeedItem> gazettes,
) {
  final current = history.first;
  final since = DateTime.parse(current.effective);
  return FuelNow(
    name: name,
    price: current.price,
    since: since,
    was: history.length > 1
        ? history[1].price
        : _wasFromGazettes(name, current.price, since, gazettes),
  );
}

/// The price before [price], from the latest fuel gazette up to a few days
/// after it started: that gazette set this price (its "before" is the answer)
/// or the one that was in force until then.
double? _wasFromGazettes(
  String name,
  double price,
  DateTime since,
  List<FeedItem> gazettes,
) {
  final limit = since.add(const Duration(days: 3));
  for (final gazette in gazettes) {
    if (gazette.published.isAfter(limit)) {
      continue;
    }
    for (final number in gazette.keyNumbers) {
      if (shortLabel(number.label) == name) {
        return number.value == price ? number.previous : number.value;
      }
    }
  }
  return null;
}

List<FuelNow> _ordered(List<FuelNow> prices) => prices
  ..sort((a, b) {
    final first = fuelOrder.indexOf(a.name);
    final second = fuelOrder.indexOf(b.name);
    return (first < 0 ? 99 : first).compareTo(second < 0 ? 99 : second);
  });

List<RateNow> _rates(List<RateRow> rows) => [
  for (final row in rows) RateNow(day: DateTime.parse(row.day), rate: row.rate),
];

List<RateNow> _backup(String? body, DateTime today) {
  if (body == null) {
    return const [];
  }
  final json = jsonDecode(body) as Map<String, Object?>;
  final from = today.subtract(const Duration(days: 30));
  return [
    for (final entry in (json['rates'] as List<Object?>? ?? const []).reversed)
      if (entry case {'date': final String date, 'rate': final num rate})
        if (!DateTime.parse(date).isBefore(from))
          RateNow(day: DateTime.parse(date), rate: rate.toDouble()),
  ];
}

/// Every holiday in the workflow's `datasets/holidays.json` from [today] on,
/// soonest first, with its Tamil name when the app has one.
List<HolidayNow> holidaysFrom(
  String? body,
  DateTime today,
  Map<String, String> tamilNames,
) {
  if (body == null) {
    return const [];
  }
  final json = jsonDecode(body) as Map<String, Object?>;
  return [
    for (final entry in json['holidays'] as List<Object?>? ?? const [])
      if (entry case {'date': final String date, 'name': final String name})
        if (!DateTime.parse(date).isBefore(today))
          HolidayNow(
            day: DateTime.parse(date),
            name: name,
            tamil: tamilNames[name],
            tentative: (entry as Map<String, Object?>)['tentative'] == true,
          ),
  ]..sort((a, b) => a.day.compareTo(b.day));
}

List<HolidayNow> _holidays(
  String? body,
  DateTime today,
  Map<String, String> tamilNames,
) {
  final upcoming = holidaysFrom(body, today, tamilNames);
  if (upcoming.isEmpty) {
    return const [];
  }
  final year = upcoming.first.day.year;
  return [
    for (final holiday in upcoming)
      if (holiday.day.year == year) holiday,
  ];
}

/// USD/LKR's move over the last week, in percent: the latest rate against the
/// last one at least 7 days before it. Null without one that old.
double? weekMove(List<RateNow> rates) {
  if (rates.isEmpty) {
    return null;
  }
  final latest = rates.first;
  final weekBefore = latest.day.subtract(const Duration(days: 7));
  for (final rate in rates) {
    if (!rate.day.isAfter(weekBefore)) {
      return (latest.rate / rate.rate - 1) * 100;
    }
  }
  return null;
}
