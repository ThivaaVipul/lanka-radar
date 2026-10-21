import 'package:equatable/equatable.dart';
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
  (RegExp('liquefied petroleum|lp gas|litro|laugfs'), 'gas lpg'),
  (RegExp('value added tax'), 'vat'),
  (RegExp('electricity'), 'power'),
  // Not 'vacancy': election notices fill council vacancies.
  (RegExp('recruit'), 'job vacancy'),
];

/// What isn't part of a word. Search matches words from their start, so
/// "rice" doesn't find "price"; the slash stays, for "o/l" and "2509/31".
final _notWord = RegExp(r'[^\p{L}\p{M}\p{N}/]+', unicode: true);

/// [text] as search keeps it: lower case, its words one space apart, and a
/// space before the first, so every word starts after a space.
String searchWords(String text) =>
    ' ${text.toLowerCase().replaceAll(_notWord, ' ').trim()}';

/// The words of a search query, as [searchWords] keeps them.
List<String> queryWords(String query) => [
  for (final word in searchWords(query).split(' '))
    if (word.isNotEmpty) word,
];

/// An item found by its text rather than its title, with the line of text
/// around the first word found.
final class TextHit extends Equatable {
  const TextHit(this.item, this.line);

  final FeedItem item;
  final String line;

  @override
  List<Object?> get props => [item, line];
}

/// The line of [text] around the first place one of [words] starts a word:
/// about [before] characters before it and [after] after, cut at spaces, with
/// "..." where it was cut. Null when no word is found.
String? lineAround(
  String text,
  List<String> words, {
  int before = 40,
  int after = 110,
}) {
  final lower = text.toLowerCase();
  int? at;
  for (final word in words) {
    final match = RegExp(
      r'(^|[^\p{L}\p{M}\p{N}])' + RegExp.escape(word),
      unicode: true,
    ).firstMatch(lower);
    if (match != null) {
      final start = match.start + match[1]!.length;
      at = at == null || start < at ? start : at;
    }
  }
  if (at == null || lower.length != text.length) {
    return at == null ? null : text.substring(0, text.length.clamp(0, after));
  }
  var start = at - before;
  if (start <= 0) {
    start = 0;
  } else {
    final space = text.indexOf(' ', start);
    start = space < 0 || space >= at ? start : space + 1;
  }
  var end = at + after;
  if (end >= text.length) {
    end = text.length;
  } else {
    final space = text.lastIndexOf(' ', end);
    end = space > at ? space : end;
  }
  return [
    if (start > 0) '...',
    text.substring(start, end).trim(),
    if (end < text.length) '...',
  ].join();
}

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
  return searchWords(
    [
      text,
      for (final (pattern, words) in _aliases)
        if (pattern.hasMatch(text)) words,
    ].join(' '),
  );
}
