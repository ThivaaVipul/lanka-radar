import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/card_lines.dart';

/// An exam with the days its timetable sets, read from the timetable's PDF by
/// the workflow (`data.days` on the item).
final class ExamDates extends Equatable {
  const ExamDates({required this.item, required this.name, required this.days});

  final FeedItem item;

  /// "O/L 2026".
  final String name;

  /// Oldest first.
  final List<DateTime> days;

  DateTime get first => days.first;
  DateTime get last => days.last;

  @override
  List<Object?> get props => [item, name, days];
}

/// The exams whose last day is [today] or later, soonest first. When a
/// timetable is amended, only the latest one for that exam is kept.
List<ExamDates> upcomingExams(List<FeedItem> items, DateTime today) {
  final byName = <String, ExamDates>{};
  for (final item in items) {
    final days = _days(item.data['days']);
    final name = shortExam(item.headlineEn);
    if (item.topic != 'exams' || days.isEmpty || name == null) {
      continue;
    }
    final held = byName[name];
    if (held == null || item.published.isAfter(held.item.published)) {
      byName[name] = ExamDates(item: item, name: name, days: days);
    }
  }
  return [
    for (final exam in byName.values)
      if (!exam.last.isBefore(today)) exam,
  ]..sort((a, b) => a.first.compareTo(b.first));
}

List<DateTime> _days(Object? value) => [
  if (value is List)
    for (final day in value)
      if (day is String) DateTime.parse(day),
]..sort();

/// The weekly gazette's vacancies and examinations still open on [today], the
/// soonest to close first.
List<FeedItem> applicationsClosing(List<FeedItem> items, DateTime today) => [
  for (final item in items)
    if (item.source == 'weekly' && !(item.closes?.isBefore(today) ?? true))
      item,
]..sort((a, b) => a.closes!.compareTo(b.closes!));

/// Three or more days off in a row, a weekend with a public holiday on or next
/// to it.
final class LongWeekend extends Equatable {
  const LongWeekend({
    required this.first,
    required this.last,
    required this.holidays,
  });

  final DateTime first;
  final DateTime last;

  /// The holidays in it, in order.
  final List<HolidayNow> holidays;

  int get length => last.difference(first).inDays + 1;

  bool get tentative => holidays.any((holiday) => holiday.tentative);

  @override
  List<Object?> get props => [first, last, holidays];
}

/// The long weekends that [holidays] make, from [today] on: runs of days off
/// (Saturdays, Sundays and the holidays) three days long or more.
List<LongWeekend> longWeekends(List<HolidayNow> holidays, DateTime today) {
  final byDay = {for (final holiday in holidays) _day(holiday.day): holiday};
  bool off(DateTime day) =>
      day.weekday == DateTime.saturday ||
      day.weekday == DateTime.sunday ||
      byDay.containsKey(day);

  final found = <LongWeekend>[];
  for (final holiday in byDay.keys.toList()..sort()) {
    if (found.isNotEmpty && !holiday.isAfter(found.last.last)) {
      continue;
    }
    var first = holiday;
    while (off(_shift(first, -1))) {
      first = _shift(first, -1);
    }
    var last = holiday;
    while (off(_shift(last, 1))) {
      last = _shift(last, 1);
    }
    final weekend = LongWeekend(
      first: first,
      last: last,
      holidays: [
        for (var day = first; !day.isAfter(last); day = _shift(day, 1))
          ?byDay[day],
      ],
    );
    if (weekend.length >= 3 && !last.isBefore(today)) {
      found.add(weekend);
    }
  }
  return found;
}

DateTime _day(DateTime time) => DateTime(time.year, time.month, time.day);

/// [day] moved by whole days, safe across daylight saving.
DateTime _shift(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);
