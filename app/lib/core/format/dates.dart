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

/// 12 Oct 2026, the same on every phone whatever its language.
String shortDate(DateTime day) =>
    '${day.day} ${_months[day.month - 1]} ${day.year}';
