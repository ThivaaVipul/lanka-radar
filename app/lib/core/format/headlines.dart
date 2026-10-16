import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/topics.dart';

const _smallWords = {
  'a',
  'an',
  'and',
  'as',
  'at',
  'by',
  'for',
  'from',
  'in',
  'into',
  'of',
  'on',
  'or',
  'per',
  'the',
  'to',
  'under',
  'upon',
  'via',
  'with',
};

/// Capital words that stay capitals (most acronyms have no vowel and stay anyway).
const _acronyms = {
  'CAA',
  'CEB',
  'EPF',
  'ETF',
  'GCE',
  'GIT',
  'NIC',
  'PAYE',
  'PUCSL',
  'SLS',
  'SSCL',
  'UDA',
  'USD',
  'VAT',
};

final _capitals = RegExp(r'^[A-Z]{2,}$');
final _vowel = RegExp('[AEIOUY]');
final _roman = RegExp(r'^(?=[IVXLC])C{0,3}(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$');
final _word = RegExp(r'^([^A-Za-z0-9]*)(.*?)([^A-Za-z0-9]*)$');

/// Title case for the words of a headline set in capitals ("FILLING OF A VACANCY"
/// reads "Filling of a Vacancy"): small words in lower case except at the start,
/// acronyms and roman numerals kept, and words already in mixed case or with
/// digits (66A(1)(b), No.) left as they are. Tamil has no case and is untouched.
String titleCase(String headline) {
  var first = true;
  final words = <String>[];
  for (final token in headline.split(' ')) {
    final match = _word.firstMatch(token)!;
    final core = match.group(2)!;
    final parts = [
      for (final (index, part) in core.split('-').indexed)
        _titleWord(part, first: first && index == 0),
    ];
    words.add('${match.group(1)}${parts.join('-')}${match.group(3)}');
    if (core.isNotEmpty) {
      first = false;
    }
  }
  return words.join(' ');
}

String _titleWord(String word, {required bool first}) {
  if (!_capitals.hasMatch(word) && word != 'A') {
    return word;
  }
  if (_acronyms.contains(word) ||
      _roman.hasMatch(word) ||
      !_vowel.hasMatch(word)) {
    return word;
  }
  final lower = word.toLowerCase();
  if (!first && _smallWords.contains(lower)) {
    return lower;
  }
  return '${word[0]}${lower.substring(1)}';
}

/// The headline to show for an item. The English one, in title case and without
/// the issuer's name the list puts in front ("Issuer - Subject"). When there was
/// no English PDF and the headline is only the issuer, the Tamil title instead,
/// or else the gazette's number.
String displayHeadline(FeedItem item) {
  if (_onlyIssuer(item)) {
    final number = item.data['number'];
    return item.headlineTa ??
        (number is String ? 'Gazette $number' : item.headlineEn);
  }
  final issuer = item.issuer;
  final headline = issuer != null && item.headlineEn.startsWith('$issuer - ')
      ? item.headlineEn.substring(issuer.length + 3)
      : item.headlineEn;
  return titleCase(headline);
}

/// The Tamil title to show under the English headline, if it isn't the headline
/// already.
String? tamilUnderHeadline(FeedItem item) =>
    _onlyIssuer(item) ? null : item.headlineTa;

bool _onlyIssuer(FeedItem item) => item.headlineEn == item.issuer;

/// A middle dot between parts of a line, written by code point to keep the
/// source plain ASCII.
final dot = ' ${String.fromCharCode(0xB7)} ';

/// The line above a headline: the topic and who published it.
String itemMeta(FeedItem item) =>
    [topicLabel(item.topic), ?item.issuer].join(dot);
