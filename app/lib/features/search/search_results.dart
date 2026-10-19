import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/labels.dart';

/// The groups search results come in, in the order they are shown.
enum SearchGroup { prices, notices, dates }

/// A price found by search.
sealed class PriceHit extends Equatable {
  const PriceHit();
}

/// A fuel's current price from CEYPETCO.
final class FuelHit extends PriceHit {
  const FuelHit(this.fuel);

  final FuelNow fuel;

  @override
  List<Object?> get props => [fuel];
}

/// The latest USD/LKR rate.
final class RateHit extends PriceHit {
  const RateHit(this.rate);

  final RateNow rate;

  @override
  List<Object?> get props => [rate];
}

/// Litro's latest price list.
final class GasHit extends PriceHit {
  const GasHit(this.list);

  final FeedItem list;

  @override
  List<Object?> get props => [list];
}

/// A price set in a price order, such as a can of tuna's.
final class OrderPriceHit extends PriceHit {
  const OrderPriceHit(this.order, this.number);

  final FeedItem order;
  final KeyNumber number;

  @override
  List<Object?> get props => [order, number];
}

/// Everything a search found, by group.
final class SearchResults extends Equatable {
  const SearchResults({
    this.prices = const [],
    this.notices = const [],
    this.dates = const [],
  });

  final List<PriceHit> prices;
  final List<FeedItem> notices;
  final List<HolidayNow> dates;

  bool get isEmpty => prices.isEmpty && notices.isEmpty && dates.isEmpty;

  int count(SearchGroup group) => switch (group) {
    SearchGroup.prices => prices.length,
    SearchGroup.notices => notices.length,
    SearchGroup.dates => dates.length,
  };

  @override
  List<Object?> get props => [prices, notices, dates];
}

/// The words of a query, in lower case.
List<String> searchWords(String query) => [
  for (final word in query.toLowerCase().split(RegExp(r'\s+')))
    if (word.isNotEmpty) word,
];

/// Puts the results together: [notices] are the stored items the query found;
/// the current prices and the [holidays] ahead are matched here, each by its
/// name and the usual ways of asking for it.
SearchResults searchEverything({
  required List<String> words,
  required List<FeedItem> notices,
  required NowData? now,
  required List<HolidayNow> holidays,
}) {
  bool matches(String text) {
    final lower = text.toLowerCase();
    return words.every(lower.contains);
  }

  final rate = now?.rates.firstOrNull;
  final gas = now?.gas;
  return SearchResults(
    prices: [
      for (final fuel in now?.fuel ?? const <FuelNow>[])
        if (matches('${fuel.name} fuel ceypetco')) FuelHit(fuel),
      if (rate != null && matches('usd/lkr usd lkr dollar rupee exchange rate'))
        RateHit(rate),
      if (gas != null && matches('lp gas lpg litro gas cylinder')) GasHit(gas),
      for (final order in notices)
        if (order.topic == 'prices')
          for (final number in order.keyNumbers)
            if (!fuelOrder.contains(shortLabel(number.label)) &&
                matches('${number.label} ${shortLabel(number.label)} price'))
              OrderPriceHit(order, number),
    ],
    notices: notices,
    dates: [
      for (final holiday in holidays)
        if (matches(
          '${holiday.name} ${holiday.tamil ?? ''} holiday '
          '${weekdayDate(holiday.day)}',
        ))
          holiday,
    ],
  );
}
