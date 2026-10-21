import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/market_report.dart';

/// HARTI's Daily Food Commodities Bulletin: a PDF every day, weekends too, with
/// the wholesale prices of vegetables at ten economic centres and, on
/// weekdays, of rice and dried foods at Pettah. HARTI's server doesn't answer
/// GitHub, so the phone reads it.
///
/// The PDFs come from spreadsheets: a row's dashes and some of its letters sit
/// a few points off its line, so a row is gathered from characters a few
/// points apart, and each price goes to the column whose heading is nearest.
abstract final class HartiBulletin {
  /// The list of bulletins, newest first. The whole page is 2.8 MB; its first
  /// [listingBytes] list the last two months or so.
  static final listing = Uri.parse('https://www.harti.gov.lk/daily-price.php');
  static const listingBytes = 64 * 1024;

  static Uri file(String path) =>
      Uri.parse('https://www.harti.gov.lk/${Uri.encodeFull(path)}');
}

/// The economic centres in the order the bulletin lists them.
const wholesaleCentres = [
  'Peliyagoda',
  'Kandy',
  'Dambulla',
  'Meegoda',
  'Norochchole',
  'Thambuththegama',
  'Keppetipola',
  'Nuwaraeliya',
  'Bandarawela',
  'Veyangoda',
];

/// Where rice and dried foods are priced.
const foodsMarket = 'Pettah';

/// The groups the Wholesale section offers, in order.
const wholesaleGroups = ['Vegetables', 'Rice', 'Other'];

/// A price range, as the bulletin gives prices: lowest and highest that day.
typedef PriceRange = ({double low, double high});

/// A good in a bulletin with its price range at each market that had one.
final class WholesaleRow extends Equatable {
  const WholesaleRow({
    required this.name,
    required this.group,
    required this.unit,
    required this.prices,
  });

  final String name;

  /// Vegetables, Rice or Other.
  final String group;

  /// kg or egg.
  final String unit;

  /// By centre (vegetables) or [foodsMarket].
  final Map<String, PriceRange> prices;

  @override
  List<Object?> get props => [name, group, unit, prices];
}

final _listed = RegExp(
  r'(assets/pdf/food_price/daily/eng/\d{4}/[A-Za-z]+/[^"]*?'
  r'\((\d{4})\.(\d{2})\.(\d{2})\)[^"]*?\.pdf)',
);

/// The bulletins the start of the listing links, newest first: each day once,
/// with its file's path.
List<(DateTime, String)> listedBulletins(String html) {
  final found = <DateTime, String>{};
  for (final match in _listed.allMatches(html)) {
    final day = DateTime(
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
    );
    found.putIfAbsent(day, () => match[1]!);
  }
  return [for (final entry in found.entries) (entry.key, entry.value)]
    ..sort((a, b) => b.$1.compareTo(a.$1));
}

/// The goods of a bulletin, from its pages' characters: the vegetables page
/// (headed by the centres) and, on weekdays, the rice and dried foods page
/// (headed by Pettah). Other pages (the Sinhala copy, charts) are left out.
List<WholesaleRow> parseBulletin(List<List<ReportChar>> pages) {
  final rows = <WholesaleRow>[];
  for (final page in pages) {
    final bands = _bands(page);
    final centres = _centres(bands);
    if (centres != null) {
      rows.addAll(_vegetables(bands, centres));
    } else if (_foodColumns(bands) case final columns?) {
      rows.addAll(_foods(bands, columns));
    }
  }
  if (rows.isEmpty) {
    throw const FormatException('No prices in the bulletin');
  }
  return rows;
}

/// A page's rows: characters each within a few points of the one before, by
/// height, are one row (a row's dashes and descenders sit a little off it,
/// and rows are a dozen points apart). Each row is left to right.
List<List<ReportChar>> _bands(List<ReportChar> chars) {
  final byHeight = [
    for (final char in chars)
      if (char.text.trim().isNotEmpty) char,
  ]..sort((a, b) => a.bottom.compareTo(b.bottom));
  final bands = <List<ReportChar>>[];
  double? last;
  for (final char in byHeight) {
    if (last != null && char.bottom - last < 4.5) {
      bands.last.add(char);
    } else {
      bands.add([char]);
    }
    last = char.bottom;
  }
  return [
    for (final band in bands) band..sort((a, b) => a.left.compareTo(b.left)),
  ];
}

/// A band's words (split at gaps of a couple of points), with their centres.
List<(String, double, double, double)> _words(List<ReportChar> band) {
  final words = <List<ReportChar>>[];
  for (final char in band) {
    if (words.isNotEmpty && char.left - words.last.last.right < 2.2) {
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
        word.first.left,
        word.last.right,
      ),
  ];
}

typedef _Column = ({String name, double centre});

/// The centres' heading, with each centre's position: a band naming at least
/// six of them.
List<_Column>? _centres(List<List<ReportChar>> bands) {
  for (final band in bands) {
    final found = <_Column>[];
    for (final (word, centre, _, _) in _words(band)) {
      final lower = word.toLowerCase();
      for (final name in wholesaleCentres) {
        if (lower.length >= 4 &&
            name.toLowerCase().startsWith(lower.substring(0, 4)) &&
            !found.any((column) => column.name == name)) {
          found.add((name: name, centre: centre));
        }
      }
    }
    if (found.length >= 6) {
      return found..sort((a, b) => a.centre.compareTo(b.centre));
    }
  }
  return null;
}

final _number = RegExp(r'^\d[\d,]*(\.\d+)?$');

/// The vegetables, each with its range at each centre that had one.
List<WholesaleRow> _vegetables(
  List<List<ReportChar>> bands,
  List<_Column> centres,
) {
  final spacing =
      (centres.last.centre - centres.first.centre) / (centres.length - 1);
  final valuesFrom = centres.first.centre - spacing / 2;
  final rows = <WholesaleRow>[];
  var started = false;
  for (final band in bands) {
    final words = _words(band);
    final label = [
      for (final (word, _, left, _) in words)
        if (left < valuesFrom) word,
    ].join(' ');
    if (label.toLowerCase().contains('vegetable')) {
      started = true;
      continue;
    }
    if (!started) {
      continue;
    }
    if (RegExp('banana|fruit', caseSensitive: false).hasMatch(label)) {
      break;
    }
    final numbers = <_Column, List<double>>{};
    for (final (word, centre, left, _) in words) {
      if (left < valuesFrom) {
        continue;
      }
      for (final piece in word.split('-')) {
        if (!_number.hasMatch(piece)) {
          continue;
        }
        final column = centres.reduce(
          (a, b) =>
              (a.centre - centre).abs() <= (b.centre - centre).abs() ? a : b,
        );
        (numbers[column] ??= []).add(double.parse(piece.replaceAll(',', '')));
      }
    }
    final name = _tidy(label);
    if (name.isEmpty || numbers.isEmpty) {
      continue;
    }
    rows.add(
      WholesaleRow(
        name: _named(name),
        group: 'Vegetables',
        unit: 'kg',
        prices: {
          for (final MapEntry(key: column, value: values) in numbers.entries)
            column.name: ?_range(values),
        },
      ),
    );
  }
  return rows;
}

/// The positions of Pettah's columns on the rice and dried foods page, from
/// the band of dates over them: its range, then today's average.
(double, double, double)? _foodColumns(List<List<ReportChar>> bands) {
  final text = bands.map((band) => band.map((c) => c.text).join()).join(' ');
  if (!text.contains(foodsMarket)) {
    return null;
  }
  for (final band in bands) {
    final dates = [
      for (final (word, centre, _, _) in _words(band))
        if (RegExp(r'^\d{4}\.\d{2}\.\d{2}$').hasMatch(word)) centre,
    ];
    if (dates.length >= 6) {
      // Pettah's range, its average today, and where Marandagahamula's start.
      return (dates[0], dates[1], dates[3]);
    }
  }
  return null;
}

/// Rice and dried foods with Pettah's range; a row without one (a heading,
/// or one not sold at Pettah that day) names the group of the rows under it.
List<WholesaleRow> _foods(
  List<List<ReportChar>> bands,
  (double, double, double) columns,
) {
  final (rangeAt, averageAt, nextMarketAt) = columns;
  final valuesFrom = rangeAt - (averageAt - rangeAt);
  final rows = <WholesaleRow>[];
  String? heading;
  var group = '';
  var unit = 'kg';
  var started = false;
  for (final band in bands) {
    final words = _words(band);
    final label = _tidy(
      [
        for (final (word, _, left, _) in words)
          if (left < valuesFrom) word,
      ].join(' '),
    );
    final range = <double>[];
    for (final (word, centre, left, _) in words) {
      if (left < valuesFrom || centre >= (averageAt + nextMarketAt) / 2) {
        continue;
      }
      if ((centre - rangeAt).abs() < (centre - averageAt).abs()) {
        for (final piece in word.split('-')) {
          if (_number.hasMatch(piece)) {
            range.add(double.parse(piece.replaceAll(',', '')));
          }
        }
      }
    }
    final lower = label.toLowerCase();
    if (lower.startsWith('rice')) {
      started = true;
    }
    if (!started || label.isEmpty) {
      continue;
    }
    final bare = label.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    final key = _key(bare);
    if (lower.contains('(rs/') || _headings.contains(key)) {
      // A heading: "Rice (Rs/kg)", "Imported Rice", "Onion (Rs/Kg)", "Big
      // Onion", "Eggs (Rs/Egg)". A row with no price at Pettah ("Sinnan -")
      // is not one.
      if (key == 'subsidiaryfoodcrops') {
        continue;
      }
      unit = key == 'eggs' ? 'egg' : 'kg';
      group = key.contains('rice') ? 'Rice' : 'Other';
      heading = switch (key) {
        'rice' || 'pulses' || 'consumptionitem' => null,
        'importedrice' => 'imported',
        _ => bare,
      };
      continue;
    }
    if (range.isEmpty) {
      continue;
    }
    final name = switch (heading) {
      null => label,
      'imported' => '$label (imported)',
      final heading => '$heading ($label)',
    };
    if (_range(range) case final price?) {
      rows.add(
        WholesaleRow(
          name: _named(name),
          group: group,
          unit: unit,
          prices: {foodsMarket: price},
        ),
      );
    }
  }
  return rows;
}

PriceRange? _range(List<double> values) => switch (values) {
  [final price] => (low: price, high: price),
  [final low, final high, ...] => (
    low: low < high ? low : high,
    high: low < high ? high : low,
  ),
  _ => null,
};

/// The headings on the rice and dried foods page that carry no unit.
const _headings = {'importedrice', 'bigonion', 'subsidiaryfoodcrops'};

/// A name's letters and digits, in lower case: the same good's key whatever
/// the day's spelling ("Beet root", "Beetroot", "AshPlantains").
String _key(String name) =>
    name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Names as the app shows them, by their key.
const _names = {
  'beans': 'Beans',
  'carrot': 'Carrot',
  'leeks': 'Leeks',
  'beetroot': 'Beetroot',
  'beetrootneliya': 'Beetroot (Nuwara Eliya)',
  'knolkhol': 'Knolkhol',
  'raddish': 'Radish',
  'cabbageneliya': 'Cabbage (Nuwara Eliya)',
  'cabbagekandy': 'Cabbage (Kandy)',
  'tomato': 'Tomato',
  'ladiesfingers': 'Ladies fingers',
  'brinjals': 'Brinjal',
  'capsicum': 'Capsicum',
  'pumpkin': 'Pumpkin',
  'cucumber': 'Cucumber',
  'bittergourd': 'Bitter gourd',
  'snakegourd': 'Snake gourd',
  'drumstick': 'Drumstick',
  'luffa': 'Luffa',
  'longbeans': 'Long beans',
  'ashplantains': 'Ash plantain',
  'greenchillies': 'Green chilli',
  'lime': 'Lime',
  'sweetpotatoe': 'Sweet potato',
  'manioc': 'Manioc',
  'eggplant': 'Eggplant',
  'potatoimported': 'Potato (imported)',
  'potatowelimada': 'Potato (Welimada)',
  'potatonuwaraeliya': 'Potato (Nuwara Eliya)',
  'bonionimported': 'Big onion (imported)',
  'bigonionlocal': 'Big onion (local)',
  'samba1': 'Samba 1',
  'samba2': 'Samba 2',
  'keerisamba': 'Keeri samba',
  'nadu1': 'Nadu 1',
  'nadu2': 'Nadu 2',
  'rawred': 'Raw red',
  'rawwhite': 'Raw white',
  'ponnesambaimported': 'Ponni samba (imported)',
  'naduimported': 'Nadu (imported)',
  'rawwhiteimported': 'Raw white (imported)',
  'rawredimported': 'Raw red (imported)',
  'driedchilliesimported': 'Dried chillies (imported)',
  'driedchillieslocal': 'Dried chillies (local)',
  'onionsinnan': 'Red onion (Sinnan)',
  'onionvedalan': 'Red onion (Vedalan)',
  'onionimported': 'Red onion (imported)',
  'bigonionimported': 'Big onion (imported)',
  'potatoeswelimada': 'Potato (Welimada)',
  'potatoesnuwaraeliya': 'Potato (Nuwara Eliya)',
  'potatoesimported': 'Potato (imported)',
  'greengram': 'Green gram',
  'cowpea': 'Cowpea',
  'reddhal': 'Red dhal',
  'sugarwhite': 'Sugar (white)',
  'wheatflour': 'Wheat flour',
  'eggsbrown': 'Eggs (brown)',
  'eggswhite': 'Eggs (white)',
};

String _named(String printed) => _names[_key(printed)] ?? _sentence(printed);

String _tidy(String label) => label
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'\s*\(\s*'), ' (')
    .replaceAll(RegExp(r'\s*\)'), ')')
    .trim();

/// A name the app doesn't know yet, with a capital only where it starts:
/// "Snake Gourd" as "Snake gourd".
String _sentence(String name) {
  final lower = name.toLowerCase();
  return lower.isEmpty ? lower : lower[0].toUpperCase() + lower.substring(1);
}
