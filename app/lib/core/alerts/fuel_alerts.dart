import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';

/// The latest price of each fuel CEYPETCO has given, by its short name.
Map<String, FuelPriceRow> latestFuel(List<FuelPriceRow> rows) {
  final latest = <String, FuelPriceRow>{};
  for (final row in rows) {
    final name = shortLabel(row.product);
    final held = latest[name];
    if (held == null || row.effective.compareTo(held.effective) > 0) {
      latest[name] = row;
    }
  }
  return latest;
}

/// What the fuel notification says about prices that changed between two reads
/// of CEYPETCO, in the Now card's order: "Petrol 92 399 (was 414)". Null when
/// none did, which includes the first read, with no price before it.
String? fuelChanges(List<FuelPriceRow> before, List<FuelPriceRow> after) {
  final was = latestFuel(before);
  final now = latestFuel(after);
  final names = [
    ...fuelOrder,
    for (final name in now.keys)
      if (!fuelOrder.contains(name)) name,
  ];
  final changed = [
    for (final name in names)
      if ((was[name], now[name]) case (
        final old?,
        final current?,
      ) when old.price != current.price)
        '$name ${amount(current.price)} (was ${amount(old.price)})',
  ];
  return changed.isEmpty ? null : changed.join(', ');
}

/// Whether [item] is a fuel gazette whose prices CEYPETCO has given the phone
/// already: the fuel alert has said it all then.
bool fuelPricesKnown(FeedItem item, List<FuelPriceRow> rows) {
  final fuel = [
    for (final number in item.keyNumbers)
      if (fuelOrder.contains(shortLabel(number.label))) number,
  ];
  if (fuel.isEmpty) {
    return false;
  }
  final latest = latestFuel(rows);
  return fuel.every(
    (number) => latest[shortLabel(number.label)]?.price == number.value,
  );
}
