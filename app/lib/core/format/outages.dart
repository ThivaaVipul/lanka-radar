import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';

/// "Power cut at Home" or "2 power cuts at Work".
String powerCutsTitle(int count, String place) => switch (count) {
  0 => 'No power cuts at $place',
  1 => 'Power cut at $place',
  _ => '$count power cuts at $place',
};

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
