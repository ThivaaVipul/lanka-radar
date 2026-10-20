import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/features/power/cubit/power_cubit.dart';
import 'package:lanka_radar/features/power/hero_status.dart';
import 'package:lanka_radar/features/power/widgets/power_line.dart';

import '../../helpers/fake_sources.dart';

void main() {
  final now = DateTime(2026, 10, 20, 11);
  final checked = DateTime(2026, 10, 20, 10, 50);
  final outages = parseOutages(fixture('edlcare_outages_49.json'));
  const work = Place(
    id: 'work',
    name: 'Work',
    area: gampaha,
    point: (lat: 7.0, lon: 79.9),
  );

  HeroStatus status(
    List<Place> places, {
    Map<String, List<Outage>> cuts = const {},
    PowerCheck check = PowerCheck.done,
    bool read = true,
    DateTime? at,
  }) => heroStatusFor(
    PowerState(
      setup: PowerSetup(places: places),
      check: check,
      power: read
          ? PowerNow(
              places: [
                for (final place in places)
                  if (place.ready)
                    PlaceCuts(
                      place: place,
                      outages: cuts[place.id] ?? const [],
                    ),
              ],
              checked: at ?? checked,
            )
          : null,
    ),
    now: now,
  );

  test('invites a first place', () {
    final hero = status(const []);

    expect(hero.title, 'Watch for power cuts');
    expect(hero.action, HeroAction.add);
  });

  test('asks to finish a place that has no area or point', () {
    final hero = status(const [Place(id: 'home', name: 'Home')]);

    expect(hero.title, 'Finish setting up Home');
    expect(hero.action, HeroAction.finish);
    expect(hero.nodes.single.state, NodeState.unfinished);
  });

  test('with no cuts, says so in a line, with when it looked', () {
    final hero = status(const [home, work]);

    expect(hero.tone, HeroTone.clear);
    expect(hero.title, 'No cuts reported at your places');
    expect(hero.detail, isNull);
    expect(hero.checked, 'Checked 10:50');
    expect(hero.live, isTrue);
    expect(hero.line, LineMode.flowing);
    expect(hero.nodes, [
      (name: 'Home', state: NodeState.clear),
      (name: 'Work', state: NodeState.clear),
    ]);
    expect(status(const [home]).title, 'No cuts reported at Home');
  });

  test('a cut at the first place breaks the line there, and says what', () {
    final at = outagesAt(outages, gampahaHome);
    final hero = status(const [home, work], cuts: {'home': at});

    expect(hero.tone, HeroTone.attention);
    expect(hero.title, 'Power cut at Home');
    expect(hero.detail, 'A breakdown since 09:24');
    expect(hero.nodes, [
      (name: 'Home', state: NodeState.cut),
      (name: 'Work', state: NodeState.clear),
    ]);
  });

  test('several cuts at a place say how many', () {
    final both = [...outagesAt(outages, gampahaHome), outages.last];
    final hero = status(const [home, work], cuts: {'home': both});

    expect(hero.title, '2 power cuts at Home');
    expect(hero.detail, 'A breakdown since 09:24, and 1 more');
  });

  test('cuts at several places name them', () {
    final at = outagesAt(outages, gampahaHome);
    final hero = status(const [home, work], cuts: {'home': at, 'work': at});

    expect(hero.title, 'Power cuts at Home and Work');
  });

  test("says when EDLCare didn't answer, and what it shows instead", () {
    final hero = status(const [home], check: PowerCheck.failed);

    expect(hero.tone, HeroTone.trouble);
    expect(hero.detail, 'Showing the check from 10:50.');
    expect(hero.checked, isNull);
    expect(hero.live, isFalse);
    expect(hero.action, HeroAction.retry);
    expect(hero.line, LineMode.down);
  });

  test('the first look says it is looking', () {
    final hero = status(const [home], check: PowerCheck.checking, read: false);

    expect(hero.title, 'Checking for power cuts');
    expect(hero.checking, isTrue);
    expect(hero.line, LineMode.checking);
    expect(hero.nodes.single.state, NodeState.waiting);
  });

  test('a look older than a quarter hour is no longer live', () {
    final hero = status(const [
      home,
    ], at: now.subtract(const Duration(minutes: 20)));

    expect(hero.live, isFalse);
  });
}
