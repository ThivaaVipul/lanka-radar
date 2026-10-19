import 'package:flutter/painting.dart';

/// [text] with every place one of [words] (lower case) appears set in
/// [strong], for showing what a search matched.
TextSpan highlighted(
  String text,
  List<String> words, {
  required TextStyle? strong,
}) {
  final lower = text.toLowerCase();
  final ranges = <(int, int)>[
    for (final word in words)
      if (word.isNotEmpty)
        for (
          var at = lower.indexOf(word);
          at >= 0;
          at = lower.indexOf(word, at + 1)
        )
          (at, at + word.length),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final spans = <TextSpan>[];
  var done = 0;
  for (final (start, end) in ranges) {
    if (end <= done) {
      continue;
    }
    final from = start > done ? start : done;
    if (from > done) {
      spans.add(TextSpan(text: text.substring(done, from)));
    }
    spans.add(TextSpan(text: text.substring(from, end), style: strong));
    done = end;
  }
  if (done < text.length) {
    spans.add(TextSpan(text: text.substring(done)));
  }
  return TextSpan(children: spans);
}
