import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';

import '../../helpers/fake_sources.dart';

void main() {
  final outages = parseOutages(fixture('edlcare_outages_49.json'));

  test('reads breakdowns and maintenance, a job with all its lines', () {
    final breakdowns = [
      for (final outage in outages)
        if (outage.kind == OutageKind.breakdown) outage,
    ];
    final jobs = [
      for (final outage in outages)
        if (outage.kind == OutageKind.maintenance) outage,
    ];

    expect(breakdowns, hasLength(12));
    expect(breakdowns.first.customers, 3);
    expect(breakdowns.first.time, DateTime(2026, 10, 20, 9, 24));
    // Three jobs on the same lines until 17:00 are one cut.
    expect(jobs, hasLength(1));
    expect(jobs.single.reason, 'Maintenance, Way Leaves');
    expect(jobs.single.customers, 5513);
    expect(jobs.single.time, DateTime(2026, 10, 20, 17));
    // Each line keeps its own outline.
    expect(
      [for (final shape in jobs.single.shapes) shape.length],
      [248, 24, 72],
    );
  });

  test('a cut covers the places on its lines, not those around them', () {
    // 51 m from the line one breakdown traces; 794 m from the maintenance
    // area and 943 m from another breakdown.
    final cuts = outagesAt(outages, gampahaHome);

    expect(cuts.single.kind, OutageKind.breakdown);
    expect(cuts.single.time, DateTime(2026, 10, 20, 9, 24));
  });

  test('a cut covers the places inside its area', () {
    final cuts = outagesAt(outages, (lat: 7.1, lon: 79.99));

    expect(cuts.single.kind, OutageKind.maintenance);
  });

  test("a cut of one customer covers only a pin on that customer's house", () {
    final spot = outages.firstWhere(
      (outage) => outage.time == DateTime(2026, 10, 20, 9, 36),
    );

    expect(spot.shapes.single, hasLength(1));
    // About 40 m and 80 m north of it.
    expect(spot.covers((lat: 7.03881, lon: 79.96877)), isTrue);
    expect(spot.covers((lat: 7.03917, lon: 79.96877)), isFalse);
  });

  test('provinces and areas are read with their names trimmed', () {
    final provinces = parseRegions(
      fixture('edlcare_provinces.json'),
      'province',
    );
    final areas = parseRegions(fixture('edlcare_areas_wpn.json'), 'area');

    expect(provinces, hasLength(15));
    expect(
      provinces.first,
      const CebRegion(id: 'CP', name: 'Central Province 1'),
    );
    expect(areas, contains(gampaha));
  });

  group("an account's calendar", () {
    final cuts = parseCalendar(fixture('edlcare_calendar.json'));

    test('is read soonest first, with plain names', () {
      expect(
        [for (final cut in cuts) cut.name],
        ['Breakdown', 'Load shedding', 'Load shedding', 'Maintenance'],
      );
      expect([for (final cut in cuts) cut.group], [null, 'V', 'V', null]);
      expect(cuts.first.breakdown, isTrue);
      expect(cuts[1].start, DateTime(2026, 10, 20, 19, 30));
      expect(cuts[1].end, DateTime(2026, 10, 20, 20, 30));
    });

    test('an account EDLCare does not know has none', () {
      expect(parseCalendar('202'), isEmpty);
    });

    test('a cut is on from its start to its end', () {
      final shedding = cuts[1];

      expect(shedding.onAt(DateTime(2026, 10, 20, 19, 29)), isFalse);
      expect(shedding.onAt(DateTime(2026, 10, 20, 19, 30)), isTrue);
      expect(shedding.onAt(DateTime(2026, 10, 20, 20, 30)), isFalse);
    });

    test('as a cut on now: a breakdown since it began, else until it ends', () {
      expect(cuts.first.asOutage.kind, OutageKind.breakdown);
      expect(cuts.first.asOutage.time, DateTime(2026, 10, 19, 11));
      expect(cuts[1].asOutage.kind, OutageKind.maintenance);
      expect(cuts[1].asOutage.reason, 'Load shedding');
      expect(cuts[1].asOutage.time, DateTime(2026, 10, 20, 20, 30));
    });

    test('the cuts to come at every place come soonest first', () {
      const work = Place(id: 'work', name: 'Work');
      final power = PowerNow(
        places: [
          PlaceCuts(place: home, ahead: [cuts[3]]),
          PlaceCuts(place: work, ahead: [cuts[1], cuts[2]]),
        ],
      );

      expect(
        [for (final (place, _) in cutsAhead(power)) place.name],
        ['Work', 'Work', 'Home'],
      );
      expect(cutsAhead(power, before: DateTime(2026, 10, 21)), [
        (work, cuts[1]),
      ]);
    });
  });

  group('PowerSetup', () {
    const work = Place(id: 'work', name: 'Work', area: gampaha);

    test('keeps its places as JSON', () {
      const setup = PowerSetup(places: [homeWithAccount, work]);

      expect(PowerSetup.fromJson(setup.toJson()), setup);
      expect(setup.accounts, {testAccount});
      expect(setup.ready, [homeWithAccount]);
      expect(setup.areaIds, {'49'});
    });

    test('reads the first build, which kept one home', () {
      final setup = PowerSetup.fromJson(
        jsonEncode({
          'province': {'id': 'WPN', 'name': 'Western Province North'},
          'area': {'id': '49', 'name': 'Gampaha'},
          'home': {'lat': gampahaHome.lat, 'lon': gampahaHome.lon},
        }),
      );

      expect(setup.places, [home]);
    });

    test('changes, adds and removes a place by its ID', () {
      const setup = PowerSetup(places: [home]);

      final renamed = setup.withPlace(home.copyWith(name: 'House'));
      expect(renamed.places.single.name, 'House');
      expect(setup.withPlace(work).places, [home, work]);
      expect(setup.withPlace(work).without('home').places, [work]);
      expect(PowerSetup.fromJson(null).places, isEmpty);
    });
  });
}
