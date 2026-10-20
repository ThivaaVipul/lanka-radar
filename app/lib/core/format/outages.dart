import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// "Power cut at Home" or "2 power cuts at Work".
String powerCutsTitle(int count, String place) => switch (count) {
  0 => 'No power cuts at $place',
  1 => 'Power cut at $place',
  _ => '$count power cuts at $place',
};

/// The places with a cut, in one line: "Power cut at Home", "2 power cuts at
/// Home" or "Power cuts at Home and Work".
String cutPlacesTitle(List<PlaceCuts> cut) => cut.length == 1
    ? powerCutsTitle(cut.single.outages.length, cut.single.place.name)
    : 'Power cuts at ${_and([for (final cuts in cut) cuts.place.name])}';

/// When a cut began or should end: "since 09:24" or "until 17:00"; null
/// without a time.
String? outageWhen(Outage outage) {
  final time = outage.time;
  if (time == null) {
    return null;
  }
  final at = clock(time.hour * 60 + time.minute);
  return switch (outage.kind) {
    OutageKind.breakdown => 'since $at',
    OutageKind.maintenance => 'until $at',
  };
}

/// The day a cut to come starts, from [now]: "Today", "Tomorrow" or "Sun 25
/// Oct".
String cutDay(AccountCut cut, {required DateTime now}) {
  final start = cut.start;
  return switch (DateTime.utc(
    start.year,
    start.month,
    start.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => weekdayDate(start),
  };
}

/// Its hours: "19:30 to 20:30", and "22:00 to 02:00" across midnight.
String cutHours(AccountCut cut) {
  String at(DateTime time) => clock(time.hour * 60 + time.minute);
  return '${at(cut.start)} to ${at(cut.end)}';
}

/// When a cut to come is: "Today 19:30 to 20:30", "Sun 25 Oct 09:00 to
/// 17:00".
String cutTimes(AccountCut cut, {required DateTime now}) =>
    '${cutDay(cut, now: now)} ${cutHours(cut)}';

/// "Home and Work", "Home, Work and School".
String _and(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
