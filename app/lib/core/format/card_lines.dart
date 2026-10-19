import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';

/// Boilerplate that lengthens official titles without saying anything, taken
/// out of card titles (the item page keeps the full title).
final _boilerplate = [
  RegExp(
    r',? Chapter \d+ of the Legislative Enactments of Ceylon',
    caseSensitive: false,
  ),
  RegExp(r' ?\(\d{4} Revised Edition\)', caseSensitive: false),
  // The act an order is made under, when something follows it.
  RegExp(
    r'^[\w ,]*? Act,? No\.? ?\d+ of \d{4}( \(Amended\))?,? (?=\S)',
    caseSensitive: false,
  ),
];

/// Long exam names and the short ones people use.
final _examNames = [
  (
    RegExp(r'General Certificate of Education \(Ordinary Level\)'),
    'G.C.E. O/L',
  ),
  (
    RegExp(r'General Certificate of Education \(Advanced Level\)'),
    'G.C.E. A/L',
  ),
  (RegExp('General Information Technology'), 'GIT'),
];

/// School exams by their usual short names, matched in an exam's title.
const _exams = [
  ('ordinary level', 'O/L'),
  ('advanced level', 'A/L'),
  ('scholarship', 'Grade 5 Scholarship'),
  ('information technology', 'GIT'),
];

final _year = RegExp(r'\b20\d\d\b');

/// What a card says first: what changed, when the data says it ("Petrol 92
/// down to Rs 399", "Tuna 155g fixed at Rs 220, and 5 more", "O/L 2026
/// timetable"), otherwise the official title without its boilerplate.
String cardTitle(FeedItem item) {
  final numbers = item.keyNumbers;
  if (item.topic == 'prices' && numbers.isNotEmpty) {
    final more = numbers.length > 1 ? ', and ${numbers.length - 1} more' : '';
    return '${priceChange(numbers.first)}$more';
  }
  if (item.topic == 'exams' && item.data['kind'] == 'timetable') {
    final exam = shortExam(item.headlineEn);
    if (exam != null) {
      return '$exam timetable';
    }
  }
  var title = displayHeadline(item);
  for (final pattern in _boilerplate) {
    title = title.replaceAll(pattern, '');
  }
  for (final (pattern, short) in _examNames) {
    title = title.replaceAll(pattern, short);
  }
  title = title.trim();
  return title.isEmpty ? displayHeadline(item) : title;
}

/// A price as a change: "Petrol 92 down to Rs 399", or "Tuna 155g fixed at Rs
/// 220" when the price before isn't known.
String priceChange(KeyNumber number) {
  final name = shortLabel(number.label);
  final value = 'Rs ${amount(number.value)}';
  final previous = number.previous;
  if (previous == null) {
    return '$name fixed at $value';
  }
  if (previous == number.value) {
    return '$name stays at $value';
  }
  return '$name ${number.value < previous ? 'down' : 'up'} to $value';
}

/// "O/L 2026" from an exam's title, if it names a school exam.
String? shortExam(String title) {
  final lower = title.toLowerCase();
  for (final (words, name) in _exams) {
    if (lower.contains(words)) {
      final year = _year.firstMatch(title)?.group(0);
      return year == null ? name : '$name $year';
    }
  }
  return null;
}

/// The small line under a card's title: who published it and when.
String cardMeta(FeedItem item, {required DateTime today}) =>
    [?item.issuer, cardDate(item.published, today: today)].join(dot);
