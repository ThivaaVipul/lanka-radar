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

/// 12 Oct 2026, the same on every phone whatever its language.
String shortDate(DateTime day) =>
    '${day.day} ${_months[day.month - 1]} ${day.year}';

/// 12 Oct in the current year, 12 Oct 2025 in any other.
String cardDate(DateTime day, {required DateTime today}) =>
    day.year == today.year
    ? '${day.day} ${_months[day.month - 1]}'
    : shortDate(day);

/// October 2026, for the feed's month headings.
String monthHeading(DateTime day) =>
    '${_monthNames[day.month - 1]} ${day.year}';
