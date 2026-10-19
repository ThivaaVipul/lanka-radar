import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/item/widgets/topic_badge.dart';

void main() {
  test('the fuel note says when prices changed, or how old they are', () {
    final today = DateTime(2026, 10, 16, 9);
    final changed = NowData(
      fuel: [
        FuelNow(
          name: 'Petrol 92',
          price: 399,
          since: DateTime(2026, 9, 30),
          was: 414,
        ),
      ],
      fuelAsOf: DateTime(2026, 10, 16, 8),
    );
    expect(fuelNote(changed, today: today), 'changed 30 Sep');

    final old = NowData(fuel: changed.fuel, fuelAsOf: DateTime(2026, 10, 12));
    expect(fuelNote(old, today: today), 'as of 12 Oct');
  });

  test('the week move compares with the last rate a week or more before', () {
    final rates = [
      RateNow(day: DateTime(2026, 10, 16), rate: 333),
      RateNow(day: DateTime(2026, 10, 12), rate: 340),
      RateNow(day: DateTime(2026, 10, 8), rate: 330),
    ];

    expect(weekMove(rates), closeTo(0.909, 0.001));
    expect(weekMove(rates.take(2).toList()), isNull);
    expect(weekMove(const []), isNull);
  });

  test('days to go read naturally', () {
    final today = DateTime(2026, 10, 19, 15);
    expect(inDays(DateTime(2026, 10, 19), today: today), 'today');
    expect(inDays(DateTime(2026, 10, 20), today: today), 'tomorrow');
    expect(inDays(DateTime(2026, 10, 25), today: today), 'in 6 days');
  });

  test('each kind of item has its own look', () {
    FeedItem made(
      String topic, {
      String source = 'x',
      String? group,
      List<KeyNumber> numbers = const [],
    }) => FeedItem(
      id: 'x',
      source: source,
      topic: topic,
      headlineEn: 'x',
      published: DateTime(2026, 10),
      keyNumbers: numbers,
      data: {'group': ?group},
    );

    expect(
      TopicLook.of(
        made(
          'prices',
          numbers: const [
            KeyNumber(label: 'Lanka Auto Diesel', value: 392, unit: 'LKR'),
          ],
        ),
      ),
      TopicLook.fuel,
    );
    expect(TopicLook.of(made('prices')), TopicLook.prices);
    expect(TopicLook.of(made('prices', source: 'gas')), TopicLook.gas);
    expect(TopicLook.of(made('rates')), TopicLook.rates);
    expect(TopicLook.of(made('exams')), TopicLook.exams);
    expect(TopicLook.of(made('gazettes', group: 'labour')), TopicLook.labour);
    expect(TopicLook.of(made('gazettes')), TopicLook.notice);
  });
}
