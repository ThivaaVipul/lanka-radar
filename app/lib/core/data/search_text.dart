import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/topics.dart';

/// Other ways people write what an item says: when the left side is in an
/// item's text, search also finds it by the words on the right.
final _aliases = [
  (RegExp('ordinary level'), 'o/l ol'),
  (RegExp('advanced level'), 'a/l al'),
  (RegExp('time[ -]table'), 'timetable'),
  (RegExp('grade (5|five)|scholarship'), 'grade 5 scholarship'),
  (RegExp(r'\busd\b|us dollar'), 'usd dollar'),
  (RegExp('petrol|diesel|kerosene|octane'), 'fuel'),
  (RegExp('liquefied petroleum|lp gas|litro'), 'gas lpg'),
  (RegExp('value added tax'), 'vat'),
  (RegExp('electricity'), 'power'),
  // Not 'vacancy': election notices fill council vacancies.
  (RegExp('recruit'), 'job vacancy'),
];

/// What search matches an item by, in lower case: its headlines, issuer and
/// gazette number, what its card shows (the topic, price labels long and
/// short, "gazette 2509/31"), and the other ways of writing common words.
String searchText(FeedItem item) {
  final number = item.data['number'];
  final text = [
    item.headlineEn,
    ?item.headlineTa,
    ?item.issuer,
    topicLabel(item.topic),
    if (number is String) 'gazette $number',
    for (final key in item.keyNumbers) ...[key.label, shortLabel(key.label)],
  ].join('\n').toLowerCase();
  return [
    text,
    for (final (pattern, words) in _aliases)
      if (pattern.hasMatch(text)) words,
  ].join('\n');
}
