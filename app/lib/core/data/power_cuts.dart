import 'dart:convert';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// A place on the map, in degrees.
typedef GeoPoint = ({double lat, double lon});

/// A CEB province or area office, as EDLCare lists them.
final class CebRegion extends Equatable {
  const CebRegion({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static CebRegion? fromJson(Object? json) => switch (json) {
    {'id': final String id, 'name': final String name} => CebRegion(
      id: id,
      name: name,
    ),
    _ => null,
  };

  @override
  List<Object?> get props => [id, name];
}

/// A place to watch for power cuts, such as Home or Work: its CEB area office,
/// where it is, and its CEB account number if given.
final class Place extends Equatable {
  const Place({
    required this.id,
    required this.name,
    this.province,
    this.area,
    this.point,
    this.account,
  });

  /// Stays the same when the place is renamed.
  final String id;
  final String name;
  final CebRegion? province;
  final CebRegion? area;
  final GeoPoint? point;

  /// The meter's 10-digit account number, as on the bill: its calendar has
  /// the cuts at that meter, past and to come.
  final String? account;

  /// Both an area to read and a point to look near.
  bool get ready => area != null && point != null;

  Place copyWith({
    String? name,
    CebRegion? Function()? province,
    CebRegion? Function()? area,
    GeoPoint? Function()? point,
    String? Function()? account,
  }) => Place(
    id: id,
    name: name ?? this.name,
    province: province != null ? province() : this.province,
    area: area != null ? area() : this.area,
    point: point != null ? point() : this.point,
    account: account != null ? account() : this.account,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'province': ?province?.toJson(),
    'area': ?area?.toJson(),
    if (point case final point?) 'point': {'lat': point.lat, 'lon': point.lon},
    'account': ?account,
  };

  static Place? fromJson(Object? json) {
    if (json case {'id': final String id, 'name': final String name}) {
      return Place(
        id: id,
        name: name,
        province: CebRegion.fromJson(json['province']),
        area: CebRegion.fromJson(json['area']),
        point: _point(json['point']),
        account: json['account'] as String?,
      );
    }
    return null;
  }

  /// Whether [text] looks like an account number: 10 digits.
  static bool isAccount(String text) => RegExp(r'^\d{10}$').hasMatch(text);

  @override
  List<Object?> get props => [id, name, province, area, point, account];
}

/// The places the phone watches for power cuts, kept on the phone only.
final class PowerSetup extends Equatable {
  const PowerSetup({this.places = const []});

  factory PowerSetup.fromJson(String? body) {
    if (body == null) {
      return const PowerSetup();
    }
    final json = jsonDecode(body) as Map<String, Object?>;
    final places = json['places'];
    if (places is List<Object?>) {
      return PowerSetup(
        places: [for (final place in places) ?Place.fromJson(place)],
      );
    }
    // The first build kept one home, without a list.
    final area = CebRegion.fromJson(json['area']);
    final home = _point(json['home']);
    return area == null && home == null
        ? const PowerSetup()
        : PowerSetup(
            places: [
              Place(
                id: 'home',
                name: 'Home',
                province: CebRegion.fromJson(json['province']),
                area: area,
                point: home,
              ),
            ],
          );
  }

  /// How many places can be watched.
  static const most = 3;

  final List<Place> places;

  List<Place> get ready => [
    for (final place in places)
      if (place.ready) place,
  ];

  /// The area offices to read, once each.
  Set<String> get areaIds => {for (final place in places) ?place.area?.id};

  /// The account calendars to read, once each.
  Set<String> get accounts => {for (final place in places) ?place.account};

  Place? place(String id) {
    for (final place in places) {
      if (place.id == id) {
        return place;
      }
    }
    return null;
  }

  /// With [place] put in place of the one with its ID, or added.
  PowerSetup withPlace(Place place) => PowerSetup(
    places: this.place(place.id) == null
        ? [...places, place]
        : [
            for (final held in places)
              if (held.id == place.id) place else held,
          ],
  );

  /// With [place] back at [index], as it was before it was removed.
  PowerSetup inserted(Place place, int index) => PowerSetup(
    places: [...places]..insert(index.clamp(0, places.length), place),
  );

  PowerSetup without(String id) => PowerSetup(
    places: [
      for (final place in places)
        if (place.id != id) place,
    ],
  );

  String toJson() => jsonEncode({
    'places': [for (final place in places) place.toJson()],
  });

  @override
  List<Object?> get props => [places];
}

GeoPoint? _point(Object? json) => switch (json) {
  {'lat': final num lat, 'lon': final num lon} => (
    lat: lat.toDouble(),
    lon: lon.toDouble(),
  ),
  _ => null,
};

enum OutageKind { breakdown, maintenance }

/// A power cut on EDLCare's outage map: where the customers it cuts off are,
/// how many they are, and when it was reported (a breakdown) or should end
/// (maintenance).
final class Outage extends Equatable {
  const Outage({
    required this.kind,
    required this.customers,
    required this.shapes,
    this.time,
    this.reason,
    this.id,
  });

  final OutageKind kind;
  final int customers;

  /// EDLCare's outlines around the customers cut off, one per line: a ring
  /// around an area, a thin ring traced along a line, or one point for one
  /// customer.
  final List<List<GeoPoint>> shapes;

  /// A breakdown's report time, or when maintenance should end.
  final DateTime? time;

  /// Maintenance's reason, such as "Way Leaves".
  final String? reason;

  /// CEB's interruption number, for maintenance.
  final String? id;

  /// Whether [place] is among the customers cut off: inside an outline, or
  /// close enough to one to be on its lines.
  bool covers(GeoPoint place) => shapes.any(
    (shape) =>
        _metresOutside(shape, place) <=
        (shape.length == 1 ? _oneCustomer : _offTheLine),
  );

  @override
  List<Object?> get props => [kind, customers, shapes, time, reason, id];
}

/// How far a place can be from an outline and still be on its lines: houses
/// stand back from the lines EDLCare traces, and a pin is never exact.
const _offTheLine = 100.0;

/// A cut of one customer is one house: only a pin on it counts.
const _oneCustomer = 50.0;

/// How far [place] is outside [shape], in metres; 0 inside a ring.
double _metresOutside(List<GeoPoint> shape, GeoPoint place) {
  // Flat metres around the place, close enough over a few kilometres.
  const metresPerDegree = 6371000.0 * math.pi / 180;
  final across = metresPerDegree * math.cos(place.lat * math.pi / 180);
  final points = [
    for (final point in shape)
      (
        (point.lon - place.lon) * across,
        (point.lat - place.lat) * metresPerDegree,
      ),
  ];
  var inside = false;
  var nearest = double.infinity;
  for (var i = 0; i < points.length; i++) {
    final (ax, ay) = points[i];
    final (bx, by) = points[i == 0 ? points.length - 1 : i - 1];
    // A ray from the place to the east crosses the ring's edges an odd
    // number of times when the place is inside.
    if ((ay > 0) != (by > 0) && ax - ay * (bx - ax) / (by - ay) > 0) {
      inside = !inside;
    }
    nearest = math.min(nearest, _toSegment(ax, ay, bx, by));
  }
  return inside && points.length > 2 ? 0 : nearest;
}

/// The distance from the origin to the segment from (ax, ay) to (bx, by).
double _toSegment(double ax, double ay, double bx, double by) {
  final dx = bx - ax;
  final dy = by - ay;
  final length = dx * dx + dy * dy;
  final t = length == 0 ? 0.0 : (-(ax * dx + ay * dy) / length).clamp(0.0, 1.0);
  final x = ax + t * dx;
  final y = ay + t * dy;
  return math.sqrt(x * x + y * y);
}

/// EDLCare's `outage-locations` answer for an area: a breakdown per entry, and
/// maintenance once per job (EDLCare lists it once per line it covers, each
/// with its own outline).
List<Outage> parseOutages(String body) {
  final breakdowns = <Outage>[];
  final jobs = <String, Outage>{};
  for (final entry in jsonDecode(body) as List<Object?>) {
    if (entry is! Map<String, Object?>) {
      continue;
    }
    final points = [
      for (final point in entry['points'] as List<Object?>? ?? const [])
        if (point case {'lat': final num lat, 'lon': final num lon})
          (lat: lat.toDouble(), lon: lon.toDouble()),
    ];
    final customers = (entry['numberOfCustomers'] as num?)?.toInt() ?? 0;
    final time = _time(entry['timestamp']);
    if (entry['outageTypeId'] == 2) {
      final id = '${entry['interruptionId'] ?? ''}';
      final held = jobs[id];
      jobs[id] = Outage(
        kind: OutageKind.maintenance,
        customers: customers,
        shapes: [...?held?.shapes, if (points.isNotEmpty) points],
        time: time,
        reason: entry['interruptionTypeName'] as String?,
        id: id.isEmpty ? null : id,
      );
    } else if (points.isNotEmpty) {
      breakdowns.add(
        Outage(
          kind: OutageKind.breakdown,
          customers: customers,
          shapes: [points],
          time: time,
        ),
      );
    }
  }
  // Jobs on the same lines until the same time are one cut to the people on
  // them: kept once, with each job's reason.
  final cuts = <String, Outage>{};
  for (final job in jobs.values) {
    final lines = [
      for (final shape in job.shapes)
        shape.map((point) => '${point.lat},${point.lon}').join(';'),
    ];
    final key = '${job.time}|${lines.join('|')}';
    final held = cuts[key];
    cuts[key] = held == null
        ? job
        : Outage(
            kind: held.kind,
            customers: held.customers,
            shapes: held.shapes,
            time: held.time,
            reason: {?held.reason, ?job.reason}.join(', '),
            id: held.id,
          );
  }
  return [...breakdowns, ...cuts.values];
}

/// EDLCare's provinces or areas: `[{"provinceId": ..., "provinceName": ...}]`
/// or the same with `area`.
List<CebRegion> parseRegions(String body, String kind) => [
  for (final entry in jsonDecode(body) as List<Object?>)
    if (entry is Map<String, Object?> &&
        entry['${kind}Id'] is String &&
        entry['${kind}Name'] is String)
      CebRegion(
        id: entry['${kind}Id']! as String,
        name: (entry['${kind}Name']! as String).trim(),
      ),
];

final _stamp = RegExp(r'^(\d{2,4})-(\d{2})-(\d{2}) (\d{1,2}):(\d{2}) ([AP]M)$');

/// "2026-10-20 05:33 AM" (a breakdown) or "26-10-20 05:00 PM" (maintenance),
/// in Sri Lanka's time like the phone's.
DateTime? _time(Object? value) {
  final match = value is String ? _stamp.firstMatch(value.trim()) : null;
  if (match == null) {
    return null;
  }
  final year = int.parse(match[1]!);
  final hour = int.parse(match[4]!) % 12 + (match[6] == 'PM' ? 12 : 0);
  return DateTime(
    year < 100 ? 2000 + year : year,
    int.parse(match[2]!),
    int.parse(match[3]!),
    hour,
    int.parse(match[5]!),
  );
}

/// A place, the cuts at it now, and the cuts its account's calendar has to
/// come.
final class PlaceCuts extends Equatable {
  const PlaceCuts({
    required this.place,
    this.outages = const [],
    this.ahead = const [],
  });

  final Place place;
  final List<Outage> outages;

  /// Soonest first.
  final List<AccountCut> ahead;

  @override
  List<Object?> get props => [place, outages, ahead];
}

/// The power cuts at each place set up, from each area's last listing.
final class PowerNow extends Equatable {
  const PowerNow({this.places = const [], this.checked});

  final List<PlaceCuts> places;

  /// When EDLCare last answered.
  final DateTime? checked;

  /// The places with a cut.
  List<PlaceCuts> get cut => [
    for (final place in places)
      if (place.outages.isNotEmpty) place,
  ];

  @override
  List<Object?> get props => [places, checked];
}

/// The cuts to come at every place, soonest first; with [before], only
/// those that start before it.
List<(Place, AccountCut)> cutsAhead(PowerNow? power, {DateTime? before}) => [
  for (final cuts in power?.places ?? const <PlaceCuts>[])
    for (final cut in cuts.ahead)
      if (before == null || cut.start.isBefore(before)) (cuts.place, cut),
]..sort((a, b) => a.$2.start.compareTo(b.$2.start));

/// The cuts in [outages] that cover [point].
List<Outage> outagesAt(List<Outage> outages, GeoPoint point) => [
  for (final outage in outages)
    if (outage.covers(point)) outage,
];

/// A cut on a CEB account's calendar: a breakdown, maintenance or load
/// shedding at that meter.
final class AccountCut extends Equatable {
  const AccountCut({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.group,
    this.breakdown = false,
  });

  final String id;

  /// Its plain name: "Load shedding", "Breakdown" or "Maintenance".
  final String name;

  /// The load shedding group, such as "V".
  final String? group;
  final DateTime start;
  final DateTime end;
  final bool breakdown;

  /// Whether it is on at [time].
  bool onAt(DateTime time) => !time.isBefore(start) && time.isBefore(end);

  /// As a cut on now, for the lists of cuts at a place: a breakdown since it
  /// began, anything else until it should end.
  Outage get asOutage => breakdown
      ? Outage(
          kind: OutageKind.breakdown,
          customers: 0,
          shapes: const [],
          time: start,
          id: id,
        )
      : Outage(
          kind: OutageKind.maintenance,
          customers: 0,
          shapes: const [],
          time: end,
          reason: name,
          id: id,
        );

  @override
  List<Object?> get props => [id, name, group, start, end, breakdown];
}

/// EDLCare's `calendar` answer for an account: `{"interruptions": [...]}`, or
/// `202` for an account it doesn't know. Sorted by start.
List<AccountCut> parseCalendar(String body) {
  final json = jsonDecode(body);
  final entries = json is Map<String, Object?> ? json['interruptions'] : null;
  return [
    if (entries is List<Object?>)
      for (final entry in entries)
        if (entry case final Map<String, Object?> fields
            when fields['interruptionId'] is String &&
                fields['startTime'] is String &&
                fields['endTime'] is String)
          AccountCut(
            id: fields['interruptionId']! as String,
            name: _plainName(fields),
            group: RegExp(
              r'\(Group ([^)]+)\)',
            ).firstMatch('${fields['interruptionTypeName']}')?[1],
            start: DateTime.parse(fields['startTime']! as String),
            end: DateTime.parse(fields['endTime']! as String),
            breakdown: _breakdown(fields),
          ),
  ]..sort((a, b) => a.start.compareTo(b.start));
}

bool _breakdown(Map<String, Object?> entry) =>
    '${entry['interruptionTypeName'] ?? ''}'.startsWith('Breakdown');

/// "Demand management (Group V)" says "Load shedding" (its group is kept
/// apart); breakdowns say "Breakdown"; safety clearances "Maintenance".
String _plainName(Map<String, Object?> entry) {
  final name = '${entry['interruptionTypeName'] ?? ''}'.trim();
  if (entry['interruptionTypeId'] == '7' ||
      name.toLowerCase().startsWith('demand management')) {
    return 'Load shedding';
  }
  if (_breakdown(entry)) {
    return 'Breakdown';
  }
  if (name.isEmpty || name == 'Safety Clearance') {
    return 'Maintenance';
  }
  return name;
}
