import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/market_prices.dart';
import 'package:lanka_radar/core/data/market_report.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/format/card_lines.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/format/outages.dart';

// What is shared, as plain text: what it is in one line, who and when in a
// second, then the official link. Nothing about the app.

/// A notice as its row shows it, with its English PDF (or else its page, or
/// another language's PDF).
String noticeShare(FeedItem item) {
  final links = item.links;
  return _lines([
    cardTitle(item),
    [?item.issuer, shortDate(item.published)].join(', '),
    links['pdf_en'] ??
        links['page'] ??
        links['pdf_ta'] ??
        links['pdf_si'] ??
        links['image'],
  ]);
}

/// "Petrol 92: Rs 399, down Rs 13 since 1 Oct", from CEYPETCO's page; until
/// CEYPETCO first answers, the price comes [fromGazette].
String fuelShare(
  FuelNow price, {
  required DateTime asOf,
  bool fromGazette = false,
}) => _lines([
  '${price.name}: Rs ${amount(price.price)}'
      '${_moved(price.price, price.was)}'
      ' since ${cardDate(price.since, today: asOf)}',
  '${fromGazette ? 'Fuel price gazette' : 'CEYPETCO'}, ${shortDate(asOf)}',
  Ceypetco.page,
]);

/// "USD/LKR: 331.54, up 0.2% in a week", from the Central Bank's page.
String rateShare(List<RateNow> rates, {required bool backup}) {
  final latest = rates.first;
  final move = weekMove(rates);
  return _lines([
    'USD/LKR: ${amount(latest.rate)}'
        '${move == null || move == 0 ? '' : ', ${move > 0 ? 'up' : 'down'} '
                  '${move.abs().toStringAsFixed(1)}% in a week'}',
    '${backup ? 'Backup copy' : 'Central Bank of Sri Lanka'}, '
        '${shortDate(latest.day)}',
    Cbsl.page,
  ]);
}

/// "Beans: Rs 480 per kg at Narahenpita, up Rs 20", with that day's report.
String marketShare(MarketQuote quote, {required DateTime day}) => _lines([
  '${quote.good.name}: Rs ${amount(quote.price)} ${quote.good.perUnit} at '
      '${quote.market}${_moved(quote.price, quote.before)}',
  'Central Bank of Sri Lanka, ${shortDate(day)}',
  MarketReport.of(day).toString(),
]);

/// "Tuna 155g: maximum retail price Rs 480, down Rs 20", with the price order
/// that set it.
String goodShare(String name, List<PricePoint> history, FeedItem order) {
  final latest = history.last;
  final before = history.length > 1 ? history[history.length - 2] : null;
  return _lines([
    '$name: maximum retail price Rs ${amount(latest.value)}'
        '${_moved(latest.value, before?.value)}',
    [?order.issuer, shortDate(latest.day)].join(', '),
    order.links['pdf_en'] ?? order.links['page'],
  ]);
}

/// "Power cut in Jaffna (CEB area): a breakdown since 11:20". Names the CEB
/// area, never the place's name or where it is.
String cutShare(PlaceCuts cuts, {DateTime? checked}) {
  final outages = cuts.outages;
  final first = outages.first;
  final what = [
    switch (first.kind) {
      OutageKind.breakdown => 'a breakdown',
      OutageKind.maintenance => first.reason ?? 'maintenance',
    },
    ?outageWhen(first),
  ].join(' ');
  final count = outages.length;
  return _lines([
    '${count == 1 ? 'Power cut' : '$count power cuts'} in '
        '${cuts.place.area?.name ?? 'the area'} (CEB area): $what'
        '${count > 1 ? ', and ${count - 1} more' : ''}',
    ['EDLCare', if (checked != null) _stamp(checked.toLocal())].join(', '),
    EdlCare.outageMap.toString(),
  ]);
}

/// "20 Oct 2026, 12:28".
String _stamp(DateTime time) =>
    '${shortDate(time)}, ${clock(time.hour * 60 + time.minute)}';

/// ", down Rs 13", ", up Rs 20", or nothing without a change.
String _moved(double now, double? before) {
  if (before == null || before == now) {
    return '';
  }
  return ', ${now > before ? 'up' : 'down'} Rs ${amount((now - before).abs())}';
}

String _lines(List<String?> lines) => [
  for (final line in lines)
    if (line != null && line.isNotEmpty) line,
].join('\n');
