import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';

import '../../helpers/fake_branch.dart';
import '../../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeSources sources;
  late DateTime now;
  late NowRepository phone;

  setUp(() {
    database = memoryDatabase();
    sources = FakeSources();
    now = DateTime(2026, 10, 16, 9);
    phone = sources.repository(database, now: () => now);
  });

  tearDown(() => database.close());

  test('a refresh stores the fuel prices and rates and records each '
      "source's success", () async {
    await phone.refresh();

    final card = await phone.load(const []);
    expect(card.fuel, hasLength(6));
    expect(card.fuel.first.name, 'Petrol 92');
    expect(card.rates.first.rate, 331.286);
    expect(card.ratesFromBackup, isFalse);
    expect(card.fuelAsOf, now);
    final status = await phone.status(NowRepository.ceypetcoSource);
    expect(status.lastSuccess, now);
    expect(status.lastError, isNull);
  });

  test(
    'a failing source is recorded, keeps what it had, and stops nothing',
    () async {
      await phone.refresh();
      final before = now;
      sources.offline = true;
      now = now.add(const Duration(hours: 1));

      await phone.refresh();

      final status = await phone.status(NowRepository.cbslSource);
      expect(status.lastRun, now);
      expect(status.lastSuccess, before);
      expect(status.lastError, contains('offline'));
      expect((await phone.load(const [])).rates, isNotEmpty);
    },
  );

  test('a price CEYPETCO changes keeps the one before', () async {
    await phone.refresh();
    final json = jsonDecode(sources.ceypetco) as Map<String, Object?>;
    for (final entry in json['data']! as List<Object?>) {
      final row = entry! as Map<String, Object?>;
      if (row['product'] == 'Lanka Petrol 92 Octane') {
        row['price'] = 399;
        row['effectiveDate'] = '2026-10-15T00:00:00.000Z';
      }
    }
    sources.ceypetco = jsonEncode(json);

    await phone.refresh();

    final petrol = (await phone.load(const [])).fuel.first;
    expect(petrol.name, 'Petrol 92');
    expect(petrol.price, 399);
    expect(petrol.since, DateTime(2026, 10, 15));
    expect(petrol.was, 414);
  });

  test('refreshIfStale waits until the last try is old enough', () async {
    const maxAge = Duration(minutes: 15);

    await phone.refreshIfStale(maxAge);
    sources.requests.clear();
    now = now.add(const Duration(minutes: 10));
    await phone.refreshIfStale(maxAge);
    expect(sources.requests, isEmpty);

    now = now.add(const Duration(minutes: 10));
    await phone.refreshIfStale(maxAge);
    expect(sources.requests, ['api.ceypetco.gov.lk', 'www.cbsl.gov.lk']);
  });

  group('market prices', () {
    final monday = DateTime(2026, 10, 19);

    setUp(() {
      sources
        ..marketListing = fixture('cbsl_price_report_listing.html')
        ..reports['price_report_20261019_e.pdf'] = fixtureBytes(
          'cbsl_price_report_20261019.pdf',
        );
      now = DateTime(2026, 10, 19, 15);
    });

    test('a refresh reads the reports the listing has, newest first', () async {
      await phone.refresh();

      expect(sources.marketRequests.take(3), [
        'price-report',
        'price_report_20261019_e.pdf',
        'price_report_20261016_e.pdf',
      ]);
      final prices = await phone.marketPrices();
      expect(prices.days, [monday]);
      expect(prices.good('Beans')!.quoteOn(monday)!.price, 700);
      // The other listed days have no report here: not asked for again.
      expect(prices.skipped, hasLength(11));
      final status = await phone.status(NowRepository.marketSource);
      expect(status.lastSuccess, now);
      expect((await phone.load(const [])).market.quotes, hasLength(39));
    });

    test("once the day's report is in, the listing isn't looked at", () async {
      await phone.refresh();
      sources.marketRequests.clear();

      now = now.add(const Duration(hours: 3));
      await phone.refresh();
      expect(sources.marketRequests, isEmpty);
    });

    test('until it is, the listing is looked at every two hours', () async {
      now = DateTime(2026, 10, 20, 9);
      await phone.refresh();
      sources.marketRequests.clear();

      now = now.add(const Duration(hours: 1));
      await phone.refresh();
      expect(sources.marketRequests, isEmpty);

      now = now.add(const Duration(hours: 1));
      await phone.refresh();
      expect(sources.marketRequests, ['price-report']);
    });

    test('a report that is not a readable PDF is skipped', () async {
      sources.reports['price_report_20261019_e.pdf'] = utf8.encode(
        '<html>Moved</html>',
      );

      await phone.refresh();

      final prices = await phone.marketPrices();
      expect(prices.days, isEmpty);
      expect(prices.skipped, contains(monday));
      final status = await phone.status(NowRepository.marketSource);
      expect(status.lastError, isNull);
    });

    test('Sources lists them with the other phone sources', () async {
      await phone.refresh();

      final health = await phone.health();
      expect(
        [for (final source in health.phone) source.name],
        ['Fuel prices', 'USD/LKR', 'Market prices'],
      );
    });
  });

  group('power cuts', () {
    test('without a place, EDLCare is not asked and nothing shows', () async {
      await phone.refresh();

      expect(sources.requests, isNot(contains('edlcare.edl.lk')));
      expect(await phone.powerNow(), isNull);
      final health = await phone.health();
      expect([
        for (final source in health.phone) source.name,
      ], isNot(contains('Power cuts')));
    });

    test("a refresh reads the place's area and finds the cuts at it", () async {
      await storePowerSetup(phone);

      await phone.refresh();

      final power = (await phone.powerNow())!;
      expect(power.places.single.place.name, 'Home');
      expect(power.places.single.outages, hasLength(1));
      expect(power.cut, hasLength(1));
      expect(power.checked, now);
      expect((await phone.load(const [])).power, power);
      final health = await phone.health();
      expect(health.phone.last.name, 'Power cuts');
    });

    test('each area is read once, for however many places are in it', () async {
      await phone.savePowerSetup(
        PowerSetup(
          places: [
            home,
            const Place(
              id: 'work',
              name: 'Work',
              area: gampaha,
              point: (lat: 7.1, lon: 80.0),
            ),
            const Place(
              id: 'school',
              name: 'School',
              area: CebRegion(id: '37', name: 'Negombo'),
              point: (lat: 7.2, lon: 79.84),
            ),
          ],
        ),
      );

      await phone.refreshPower();

      expect(
        sources.edlPaths.where((path) => path.endsWith('/outage-locations')),
        hasLength(2),
      );
    });

    group('load shedding', () {
      setUp(() async {
        now = DateTime(2026, 10, 20, 12);
        await storePowerSetup(phone);
      });

      test('the schedule is read for today and tomorrow', () async {
        await phone.refreshPower();

        expect(sources.scheduleQueries.single, {
          'from': '2026-10-20',
          'to': '2026-10-22',
        });
      });

      test("a place's group is found from its point, once a day", () async {
        await phone.refreshGroups();
        // Group by group until the one whose areas the place is in.
        expect(sources.groupQueries.last, 'V');
        expect(sources.groupQueries, hasLength(22));

        sources.groupQueries.clear();
        now = now.add(const Duration(hours: 5));
        await phone.refreshGroups();
        expect(sources.groupQueries, isEmpty);

        // A day on, the group it was in is looked at first.
        now = now.add(const Duration(days: 1));
        await phone.refreshGroups();
        expect(sources.groupQueries, ['V']);
      });

      test(
        "the place's group's cuts to come are listed, soonest first",
        () async {
          await phone.refresh();

          final place = (await phone.powerNow())!.places.single;
          expect(place.group, 'V');
          expect(
            [for (final cut in place.ahead) cut.start],
            [DateTime(2026, 10, 20, 19, 30), DateTime(2026, 10, 21, 16, 30)],
          );
          // The map's breakdown is still the cut on now.
          expect(place.outages.single.kind, OutageKind.breakdown);
        },
      );

      test("load shedding on now is the place's cut", () async {
        await phone.refresh();
        now = DateTime(2026, 10, 20, 19, 45);

        final place = (await phone.powerNow())!.places.single;
        expect(place.outages.single.reason, 'Load shedding');
        expect(place.outages.single.time, DateTime(2026, 10, 20, 20, 30));
        expect(place.ahead.single.start, DateTime(2026, 10, 21, 16, 30));
      });

      test('a schedule that fails keeps the last one, quietly', () async {
        await phone.refresh();
        sources.powerSchedule = 'not the schedule';

        await phone.refreshPower();

        expect((await phone.powerNow())!.places.single.ahead, hasLength(2));
        expect((await phone.status('edlcare')).lastError, isNull);
      });

      test('a place that moved has no group until it is looked up', () async {
        await phone.refresh();
        await phone.savePowerSetup(
          PowerSetup(
            places: [home.copyWith(point: () => (lat: 7.2, lon: 79.84))],
          ),
        );

        expect((await phone.powerNow())!.places.single.group, isNull);
        sources.groupQueries.clear();
        await phone.refreshGroups();
        // In no group: every group was looked at, and none is kept.
        expect(sources.groupQueries, hasLength(26));
        expect((await phone.powerNow())!.places.single.ahead, isEmpty);
      });
    });

    test("an area nobody's place is in any more is not kept", () async {
      await storePowerSetup(phone);
      await phone.refresh();
      await phone.savePowerSetup(
        PowerSetup(
          places: [
            home.copyWith(
              area: () => const CebRegion(id: '37', name: 'Negombo'),
            ),
          ],
        ),
      );
      sources.offline = true;
      await phone.refreshPower();

      expect((await phone.powerNow())!.places.single.outages, isEmpty);
    });
  });
}
