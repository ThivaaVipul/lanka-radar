import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/features/home/notice_rows.dart';

FeedItem gazette(String id, DateTime published, {String? group}) => FeedItem(
  id: id,
  source: 'gazettes',
  topic: 'gazettes',
  headlineEn: id,
  published: published,
  data: {'group': ?group},
);

FeedItem weekly(String id, String week, {String topic = 'jobs'}) => FeedItem(
  id: id,
  source: 'weekly',
  topic: topic,
  headlineEn: id,
  published: DateTime.parse(week),
  data: {'week': week},
);

String describe(NoticeRow row) => switch (row) {
  MonthRow(:final month) => 'month ${month.month}',
  DayRow(:final day) => 'day ${day.day}',
  ItemRow(:final item) => item.id,
  ElectionWeek(:final items) => 'elections ${items.map((i) => i.id).join(',')}',
  WeeklyGazette(:final week, :final items) =>
    'gazette ${week.day} ${items.map((i) => i.id).join(',')}',
};

void main() {
  test("a week's election notices fold into one row where the newest was", () {
    // Monday 12 October 2026 starts the week.
    final rows = noticeRows([
      gazette('e3', DateTime(2026, 10, 14), group: 'elections'),
      gazette('labour', DateTime(2026, 10, 13), group: 'labour'),
      gazette('e2', DateTime(2026, 10, 13), group: 'elections'),
      gazette('e1', DateTime(2026, 10, 9), group: 'elections'),
    ]);

    expect(rows.map(describe), [
      'month 10',
      'day 14',
      'elections e3,e2',
      'day 13',
      'labour',
      'day 9',
      'elections e1',
    ]);
  });

  test("a weekly gazette's notices fold into one row on its day", () {
    final rows = noticeRows([
      gazette('order', DateTime(2026, 10, 12)),
      weekly('post', '2026-10-09'),
      weekly('exam', '2026-10-09', topic: 'exams'),
      gazette('labour', DateTime(2026, 10, 9)),
      weekly('older', '2026-10-02'),
    ]);

    expect(rows.map(describe), [
      'month 10',
      'day 12',
      'order',
      'day 9',
      'gazette 9 post,exam',
      'labour',
      'day 2',
      'gazette 2 older',
    ]);
  });

  test('a month heading comes before each month and a day heading before '
      'each day, also for a fold', () {
    final rows = noticeRows([
      gazette('oct', DateTime(2026, 10, 1)),
      gazette('e1', DateTime(2026, 9, 30), group: 'elections'),
      gazette('sep', DateTime(2026, 9, 29)),
    ]);

    expect(rows.map(describe), [
      'month 10',
      'day 1',
      'oct',
      'month 9',
      'day 30',
      'elections e1',
      'day 29',
      'sep',
    ]);
  });

  test('weeks start on Monday', () {
    expect(weekOf(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
    expect(weekOf(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
  });
}
