import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/alerts/quiet_hours.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/outages.dart';

/// A power cut notification: what and where, then when.
final class PowerAlert extends Equatable {
  const PowerAlert({
    required this.key,
    required this.title,
    required this.body,
  });

  /// Stays the same for what it is about, so posting it again replaces it.
  final String key;
  final String title;
  final String body;

  @override
  List<Object?> get props => [key, title, body];
}

/// A reminder shortly before load shedding.
final class CutReminder extends Equatable {
  const CutReminder({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Stays the same for a slot, so scheduling it again replaces it.
  final String key;

  /// When it goes out, Sri Lanka time.
  final DateTime at;
  final String title;
  final String body;

  @override
  List<Object?> get props => [key, at, title, body];
}

/// How long before load shedding its reminder goes out.
const remindBefore = Duration(minutes: 30);

/// What [power] shows, to tell next time what is new: each place's cuts on
/// now, and each load shedding slot to come. Load shedding that has started
/// keeps its slot's key, as its reminder has told of it already.
Set<String> powerKeys(PowerNow? power) => {
  for (final cuts in power?.places ?? const <PlaceCuts>[]) ...[
    for (final outage in cuts.outages) _nowKey(cuts.place, outage),
    for (final cut in cuts.ahead) _slotKey(cut.id),
  ],
};

/// What is new in [power] since [seen]: a notification for each place with a
/// cut on now that wasn't seen, and one for each set of places with load
/// shedding slots seen for the first time (today's and tomorrow's for Home
/// come in one).
List<PowerAlert> powerAlerts(
  PowerNow? power,
  Set<String> seen, {
  required DateTime now,
}) {
  final places = power?.places ?? const <PlaceCuts>[];
  final fresh = <String, (PlannedCut, List<String>)>{};
  for (final cuts in places) {
    for (final cut in cuts.ahead) {
      if (!seen.contains(_slotKey(cut.id))) {
        fresh
            .putIfAbsent(_slotKey(cut.id), () => (cut, []))
            .$2
            .add(cuts.place.name);
      }
    }
  }
  final byPlaces = <String, List<PlannedCut>>{};
  for (final (cut, names) in fresh.values) {
    byPlaces.putIfAbsent(listAnd(names), () => []).add(cut);
  }
  return [
    for (final cuts in places)
      if (cuts.outages.any(
        (outage) => !seen.contains(_nowKey(cuts.place, outage)),
      ))
        PowerAlert(
          key: 'power-now-${cuts.place.id}',
          title: powerCutsTitle(cuts.outages.length, cuts.place.name),
          body:
              '${outageSentence(cuts.outages.first)}'
              '${cuts.outages.length > 1 ? ', and ${cuts.outages.length - 1} more' : ''}',
        ),
    for (final MapEntry(key: where, value: slots) in byPlaces.entries)
      PowerAlert(
        key: 'power-ahead-$where',
        title: '${slots.first.name} at $where',
        body: [
          for (final cut in slots..sort((a, b) => a.start.compareTo(b.start)))
            cutTimes(cut, now: now),
        ].join(', '),
      ),
  ];
}

/// A reminder [remindBefore] each load shedding slot to come, for the places
/// it is at, unless that time has passed or falls in [quiet] hours.
List<CutReminder> cutReminders(
  PowerNow? power, {
  required DateTime now,
  required QuietHours quiet,
}) {
  final slots = <String, (PlannedCut, List<String>)>{};
  for (final cuts in power?.places ?? const <PlaceCuts>[]) {
    for (final cut in cuts.ahead) {
      slots
          .putIfAbsent(_slotKey(cut.id), () => (cut, []))
          .$2
          .add(cuts.place.name);
    }
  }
  String at(DateTime time) => clock(time.hour * 60 + time.minute);
  return [
    for (final (cut, names) in slots.values)
      if (cut.start.subtract(remindBefore) case final time
          when time.isAfter(now) && !quiet.holds(time))
        CutReminder(
          key: 'power-${_slotKey(cut.id)}',
          at: time,
          title: '${cut.name} at ${listAnd(names)} at ${at(cut.start)}',
          body: 'Until ${at(cut.end)}',
        ),
  ];
}

String _slotKey(String id) => 'slot:$id';

String _nowKey(Place place, Outage outage) => outage.from != null
    ? _slotKey(outage.id ?? '')
    : [
        'now',
        place.id,
        outage.kind.name,
        outage.id ?? '',
        outage.time?.toIso8601String() ?? '',
        // A breakdown has no ID: where it is tells two at once apart.
        '${outage.shapes.firstOrNull?.firstOrNull}',
      ].join(':');
