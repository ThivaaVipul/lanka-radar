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

String describe(NoticeRow row) => switch (row) {
  MonthRow(:final month) => 'month ${month.month}',
  ItemRow(:final item) => item.id,
  ElectionWeek(:final items) => 'elections ${items.map((i) => i.id).join(',')}',
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
      'elections e3,e2',
      'labour',
      'elections e1',
    ]);
  });

  test('a month heading comes before each month, also for a fold', () {
    final rows = noticeRows([
      gazette('oct', DateTime(2026, 10, 1)),
      gazette('e1', DateTime(2026, 9, 30), group: 'elections'),
      gazette('sep', DateTime(2026, 9, 29)),
    ]);

    expect(rows.map(describe), [
      'month 10',
      'oct',
      'month 9',
      'elections e1',
      'sep',
    ]);
  });

  test('weeks start on Monday', () {
    expect(weekOf(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
    expect(weekOf(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
  });
}
