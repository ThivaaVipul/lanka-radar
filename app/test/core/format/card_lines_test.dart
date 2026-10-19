import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/card_lines.dart';

FeedItem made({
  String topic = 'gazettes',
  String headline = 'A headline',
  String? issuer,
  List<KeyNumber> numbers = const [],
  Map<String, Object?> data = const {},
}) => FeedItem(
  id: 'x',
  source: topic,
  topic: topic,
  headlineEn: headline,
  issuer: issuer,
  keyNumbers: numbers,
  data: data,
  published: DateTime(2026, 10, 12),
);

KeyNumber price(String label, double value, [double? previous]) =>
    KeyNumber(label: label, value: value, unit: 'LKR', previous: previous);

void main() {
  group('a card title says what changed', () {
    test('a price that was set, or moved', () {
      expect(
        cardTitle(made(topic: 'prices', numbers: [price('Tuna 155g', 220)])),
        'Tuna 155g fixed at Rs 220',
      );
      expect(
        cardTitle(
          made(
            topic: 'prices',
            numbers: [price('Lanka Petrol 92 Octane', 399, 414)],
          ),
        ),
        'Petrol 92 down to Rs 399',
      );
      expect(
        priceChange(price('Lanka Auto Diesel', 407, 392)),
        'Diesel up to Rs 407',
      );
      expect(priceChange(price('Rice', 220, 220)), 'Rice stays at Rs 220');
    });

    test('with how many more prices the order sets', () {
      expect(
        cardTitle(
          made(
            topic: 'prices',
            numbers: [
              price('Tuna 155g', 220),
              price('Tuna 425g', 510),
              price('Mackerel 425g', 480),
            ],
          ),
        ),
        'Tuna 155g fixed at Rs 220, and 2 more',
      );
    });

    test('a timetable by its exam', () {
      expect(
        cardTitle(
          made(
            topic: 'exams',
            headline:
                'General Certificate of Education (Ordinary Level) '
                'Examination - 2026 Time Table',
            data: const {'kind': 'timetable'},
          ),
        ),
        'O/L 2026 timetable',
      );
      expect(
        shortExam('Grade 5 Scholarship Examination'),
        'Grade 5 Scholarship',
      );
      expect(shortExam('Press Release'), isNull);
    });

    test('the act an order is made under goes, and exams go short', () {
      expect(
        cardTitle(
          made(
            headline:
                'CONSUMER AFFAIRS AUTHORITY ACT, No. 9 OF 2003 (Amended) '
                'Direction under Section 12 (2)',
          ),
        ),
        'Direction under Section 12 (2)',
      );
      expect(
        cardTitle(
          made(
            topic: 'exams',
            headline:
                'General Certificate of Education (Advanced Level) '
                'Examination - 2026 (Amended)',
          ),
        ),
        'G.C.E. A/L Examination - 2026 (Amended)',
      );
      expect(
        cardTitle(
          made(headline: 'Imports and Exports (Control) Act, 01 of 1969'),
        ),
        'Imports and Exports (Control) Act, 01 of 1969',
      );
    });

    test('otherwise the official title, without its boilerplate', () {
      expect(
        cardTitle(
          made(
            headline:
                'THE INDUSTRIAL DISPUTES ACT, CHAPTER 131 OF THE LEGISLATIVE '
                'ENACTMENTS OF CEYLON (1956 REVISED EDITION) Order',
          ),
        ),
        'The Industrial Disputes Act Order',
      );
    });
  });

  test('the line under it has the issuer and the date', () {
    expect(
      cardMeta(
        made(issuer: 'Consumer Affairs Authority'),
        today: DateTime(2026, 10, 19),
      ),
      contains('Consumer Affairs Authority'),
    );
    expect(cardMeta(made(), today: DateTime(2026, 10, 19)), '12 Oct');
  });
}
