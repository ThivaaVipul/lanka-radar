import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// The Central Bank's Daily Price Report: one PDF each weekday with the
/// wholesale and retail prices of everyday food at a few markets. Its server
/// turns GitHub away, so the phone reads it.
///
/// The report's table is a PDF made from a spreadsheet: numbers are split by
/// stray spaces ("5 50.00" is 550.00), so each row's prices are read from the
/// characters and put in a column by where they stand under the header.
abstract final class MarketReport {
  static final listing = Uri.parse(
    'https://www.cbsl.gov.lk/en/statistics/economic-indicators/price-report',
  );

  static Uri of(DateTime day) => Uri.parse(
    'https://www.cbsl.gov.lk/sites/default/files/cbslweb_documents/'
    'statistics/pricerpt/price_report_${isoDay(day).replaceAll('-', '')}_e.pdf',
  );
}

/// A character on the report's table page, with its box in points from the
/// page's left and top. Spaces are characters too.
typedef ReportChar = ({String text, double left, double right, double bottom});

/// A good in a report, with each market's retail price that day (null for
/// n.a.).
final class ReportRow extends Equatable {
  const ReportRow({
    required this.name,
    required this.unit,
    required this.section,
    this.retail = const {},
  });

  final String name;

  /// kg, l, nut or each.
  final String unit;
  final String section;
  final Map<String, double?> retail;

  @override
  List<Object?> get props => [name, unit, section, retail];
}

final _report = RegExp(r'price_report_(\d{8})_?e\.pdf', caseSensitive: false);
final _price = RegExp(r'\d[\d,]*?\.\d{2}|n\.a\.');
const _units = {'kg': 'kg', 'nut': 'nut', 'ltr': 'l', 'each': 'each'};
const _sections = {'VEGETABLES', 'OTHER', 'FRUITS', 'RICE', 'FISH'};
const _markets = {'Pettah', 'Dambulla', 'Narahenpita'};

/// The days the report listing links, newest first.
List<DateTime> listedReportDays(String html) {
  final days = {
    for (final match in _report.allMatches(html))
      DateTime.parse(
        '${match[1]!.substring(0, 4)}-${match[1]!.substring(4, 6)}-'
        '${match[1]!.substring(6)}',
      ),
  };
  return days.toList()..sort((a, b) => b.compareTo(a));
}

/// The report's rows with each market's retail price that day: Pettah's,
/// Dambulla's and Narahenpita's, and Negombo's for fish (the fish table puts
/// Negombo where Dambulla is).
List<ReportRow> parseReport(List<ReportChar> chars) {
  final bands = _bands(chars);
  final columns = _columns(bands);
  final rows = <ReportRow>[];
  var section = '';
  for (final band in bands) {
    final ink = [
      for (final char in band)
        if (char.text.trim().isNotEmpty) char,
    ];
    final text = ink.map((char) => char.text).join();
    if (_sections.contains(text)) {
      section = text[0] + text.substring(1).toLowerCase();
      continue;
    }
    final label = [
      for (final char in band)
        if (char.left < 110) char,
    ];
    final unit = _unit([
      for (final char in ink)
        if (char.left >= 110 && char.left < 150) char,
    ]);
    if (label.every((char) => char.text.trim().isEmpty) || unit == null) {
      continue;
    }
    final fish = section == 'Fish';
    final retail = <String, double?>{
      for (final MapEntry(key: (kind, market), value: price) in _prices([
        for (final char in ink)
          if (char.left >= 150) char,
      ], columns).entries)
        if (kind == 'retail')
          fish && market == 'Dambulla' ? 'Negombo' : market: price,
    };
    rows.add(
      ReportRow(
        name: _name(label),
        unit: unit,
        section: section,
        retail: retail,
      ),
    );
  }
  if (rows.isEmpty) {
    throw const FormatException('No prices in the report');
  }
  return rows;
}

/// The table's rows: a row's name, unit and prices can sit a point or two
/// apart, and rows are a dozen points apart, so characters within a few points
/// of a row's first belong to it. Each row is left to right.
List<List<ReportChar>> _bands(List<ReportChar> chars) {
  final byHeight = [
    for (final char in chars)
      if (char.text != '\n' && char.text != '\r') char,
  ]..sort((a, b) => a.bottom.compareTo(b.bottom));
  final bands = <(double, List<ReportChar>)>[];
  for (final char in byHeight) {
    if (bands.isNotEmpty && char.bottom - bands.last.$1 < 5) {
      bands.last.$2.add(char);
    } else {
      bands.add((char.bottom, [char]));
    }
  }
  return [
    for (final (_, band) in bands)
      band..sort((a, b) => a.left.compareTo(b.left)),
  ];
}

typedef _Column = ({String kind, String market, double centre});

/// The header's markets, left to right: wholesale Pettah and Dambulla, then
/// retail Pettah, Dambulla and Narahenpita. Each name is centred over two
/// prices: the last report's on its left ("Yesterday" or "Last Friday") and
/// today's on its right.
List<_Column> _columns(List<List<ReportChar>> bands) {
  const kinds = ['wholesale', 'wholesale', 'retail', 'retail', 'retail'];
  for (final band in bands) {
    final markets = [
      for (final (text, centre) in _words(band))
        if (_markets.contains(text)) (text, centre),
    ];
    if (markets.length == kinds.length) {
      return [
        for (final (index, (market, centre)) in markets.indexed)
          (kind: kinds[index], market: market, centre: centre),
      ];
    }
  }
  throw const FormatException('No market header in the report');
}

/// Each column's price that day: a number belongs to the nearest market, and
/// is that day's when it stands right of the market's name.
Map<(String, String), double?> _prices(
  List<ReportChar> chars,
  List<_Column> columns,
) {
  final text = chars.map((char) => char.text).join();
  final found = <(String, String), double?>{};
  for (final match in _price.allMatches(text)) {
    final centre = (chars[match.start].left + chars[match.end - 1].right) / 2;
    final column = columns.reduce(
      (a, b) => (a.centre - centre).abs() <= (b.centre - centre).abs() ? a : b,
    );
    if (centre > column.centre) {
      final value = match[0]!;
      found[(column.kind, column.market)] = value == 'n.a.'
          ? null
          : double.parse(value.replaceAll(',', ''));
    }
  }
  return found;
}

/// A band's words (split at gaps) with their centres.
List<(String, double)> _words(List<ReportChar> band) {
  final words = <List<ReportChar>>[];
  for (final char in band) {
    if (char.text.trim().isEmpty) {
      continue;
    }
    if (words.isNotEmpty && char.left - words.last.last.right < 2) {
      words.last.add(char);
    } else {
      words.add([char]);
    }
  }
  return [
    for (final word in words)
      (
        word.map((char) => char.text).join(),
        (word.first.left + word.last.right) / 2,
      ),
  ];
}

/// kg, l, nut or each, from "Rs./kg" and the like.
String? _unit(List<ReportChar> chars) {
  final text = chars.map((char) => char.text).join().toLowerCase();
  return _units[text.startsWith('rs./') ? text.substring(4) : text];
}

String _name(List<ReportChar> chars) => chars
    .map((char) => char.text)
    .join()
    .replaceAll('(lmp)', '(Imp)')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
