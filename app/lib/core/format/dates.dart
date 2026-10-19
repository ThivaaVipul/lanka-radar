const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 2026-10-12, as the data branch writes days.
String isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Sat 8 Nov, for lists of days.
String weekdayDate(DateTime day) =>
    '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

/// 12 Oct 2026, the same on every phone whatever its language.
String shortDate(DateTime day) =>
    '${day.day} ${_months[day.month - 1]} ${day.year}';

/// 12 Oct in the current year, 12 Oct 2025 in any other.
String cardDate(DateTime day, {required DateTime today}) =>
    day.year == today.year
    ? '${day.day} ${_months[day.month - 1]}'
    : shortDate(day);

/// 16 Oct, 09:30 in local time (with the year when it isn't this one).
String dayTime(DateTime time, {required DateTime today}) {
  final local = time.toLocal();
  return '${cardDate(local, today: today)}, '
      '${clock(local.hour * 60 + local.minute)}';
}

/// 06:30 for [minutes] after midnight: the app's clock is always 24-hour.
String clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// October 2026, for the feed's month headings.
String monthHeading(DateTime day) =>
    '${_monthNames[day.month - 1]} ${day.year}';

/// "today", "tomorrow" or "in 6 days", from [today] (a day) to [day].
String inDays(DateTime day, {required DateTime today}) {
  final days = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  return switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => 'in $days days',
  };
}
