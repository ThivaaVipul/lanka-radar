import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';

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

/// "Home and Work", "Home, Work and School".
String _and(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// What a cut is and when, with a dot between: "Breakdown, since 09:24" or
/// "Way Leaves, until 17:00".
String outageLine(Outage outage) {
  final time = outage.time;
  final at = time == null ? null : clock(time.hour * 60 + time.minute);
  return [
    ...switch (outage.kind) {
      OutageKind.breakdown => ['Breakdown', if (at != null) 'since $at'],
      OutageKind.maintenance => [
        outage.reason ?? 'Maintenance',
        if (at != null) 'until $at',
      ],
    },
  ].join(dot);
}
