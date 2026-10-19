import 'package:lanka_radar/core/data/feed_item.dart';

/// Election vacancy notices: most gazettes, so they fold away.
bool isElectionNotice(FeedItem item) =>
    item.topic == 'gazettes' && item.data['group'] == 'elections';

/// A row of the Notices list.
sealed class NoticeRow {
  const NoticeRow();
}

/// A month heading, before the month's first row.
final class MonthRow extends NoticeRow {
  const MonthRow(this.month);

  final DateTime month;
}

final class ItemRow extends NoticeRow {
  const ItemRow(this.item);

  final FeedItem item;
}

/// A week's election notices folded into one row, newest first.
final class ElectionWeek extends NoticeRow {
  const ElectionWeek(this.week, this.items);

  /// The Monday the week starts on.
  final DateTime week;
  final List<FeedItem> items;
}

/// The Notices list for [items] (newest first): month headings, and each
/// week's election notices folded into one row where the week's newest one
/// would be.
List<NoticeRow> noticeRows(List<FeedItem> items) {
  final weeks = <DateTime, List<FeedItem>>{};
  for (final item in items) {
    if (isElectionNotice(item)) {
      weeks.putIfAbsent(weekOf(item.published), () => []).add(item);
    }
  }
  final rows = <NoticeRow>[];
  final folded = <DateTime>{};
  DateTime? month;
  for (final item in items) {
    final NoticeRow row;
    if (isElectionNotice(item)) {
      final week = weekOf(item.published);
      if (!folded.add(week)) {
        continue;
      }
      row = ElectionWeek(week, weeks[week]!);
    } else {
      row = ItemRow(item);
    }
    final day = item.published;
    if (month == null || month.month != day.month || month.year != day.year) {
      rows.add(MonthRow(day));
      month = day;
    }
    rows.add(row);
  }
  return rows;
}

/// The Monday of [day]'s week.
DateTime weekOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
