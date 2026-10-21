import 'package:lanka_radar/core/alerts/weekly_alerts.dart' as weekly;
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

/// A day heading, before the day's first row.
final class DayRow extends NoticeRow {
  const DayRow(this.day);

  final DateTime day;
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

/// A weekly gazette's notices folded into one row, newest first.
final class WeeklyGazette extends NoticeRow {
  const WeeklyGazette(this.week, this.items);

  /// The gazette's date.
  final DateTime week;
  final List<FeedItem> items;
}

/// The Notices list for [items] (newest first): month and day headings, each
/// week's election notices folded into one row and each weekly gazette's
/// notices into another, where the newest of them would be.
List<NoticeRow> noticeRows(List<FeedItem> items) {
  final weeks = <DateTime, List<FeedItem>>{};
  final gazettes = <DateTime, List<FeedItem>>{};
  for (final item in items) {
    if (isElectionNotice(item)) {
      weeks.putIfAbsent(weekOf(item.published), () => []).add(item);
    } else if (item.source == 'weekly') {
      gazettes.putIfAbsent(weekly.weekOf(item), () => []).add(item);
    }
  }
  final rows = <NoticeRow>[];
  final folded = <Object>{};
  DateTime? month;
  DateTime? day;
  for (final item in items) {
    final NoticeRow row;
    if (isElectionNotice(item)) {
      final week = weekOf(item.published);
      if (!folded.add(('elections', week))) {
        continue;
      }
      row = ElectionWeek(week, weeks[week]!);
    } else if (item.source == 'weekly') {
      final week = weekly.weekOf(item);
      if (!folded.add(('weekly', week))) {
        continue;
      }
      row = WeeklyGazette(week, gazettes[week]!);
    } else {
      row = ItemRow(item);
    }
    final published = item.published;
    final date = DateTime(published.year, published.month, published.day);
    if (month == null || month.month != date.month || month.year != date.year) {
      rows.add(MonthRow(date));
      month = date;
    }
    if (date != day) {
      rows.add(DayRow(date));
      day = date;
    }
    rows.add(row);
  }
  return rows;
}

/// The Monday of [day]'s week.
DateTime weekOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
