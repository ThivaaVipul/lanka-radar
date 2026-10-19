import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/background_sync.dart';
import 'package:lanka_radar/core/alerts/fuel_alerts.dart';
import 'package:lanka_radar/core/alerts/holiday_reminders.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/alerts/quiet_hours.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_data.dart';

import '../../helpers/fake_branch.dart';
import '../../helpers/fake_notifier.dart';
import '../../helpers/fake_sources.dart';

FeedItem feedItem(
  String topic, {
  String? group,
  bool alert = true,
  DateTime? published,
  List<KeyNumber> numbers = const [],
}) => FeedItem(
  id: '$topic-$group',
  source: topic,
  topic: topic,
  issuer: 'Issuer',
  headlineEn: 'Headline',
  published: published ?? DateTime(2026, 10, 15),
  keyNumbers: numbers,
  data: {'group': ?group},
  alert: alert,
);

void main() {
  group('switches', () {
    test('an item falls under its topic, or its group for a gazette', () {
      expect(switchFor(feedItem('prices')), AlertSwitch.prices);
      expect(switchFor(feedItem('exams')), AlertSwitch.exams);
      expect(switchFor(feedItem('jobs')), AlertSwitch.jobs);
      expect(switchFor(feedItem('rates')), AlertSwitch.rates);
      expect(
        switchFor(feedItem('gazettes', group: 'labour')),
        AlertSwitch.labour,
      );
      expect(
        switchFor(feedItem('gazettes', group: 'elections')),
        AlertSwitch.elections,
      );
      expect(switchFor(feedItem('gazettes')), isNull);
    });

    test('everything starts on except election notices', () {
      expect(
        [
          for (final alert in AlertSwitch.values)
            if (!alert.on) alert,
        ],
        [AlertSwitch.elections],
      );
    });

    test(
      'alerts only for recent items marked to alert with their switch on',
      () {
        final now = DateTime(2026, 10, 16);
        final items = [
          feedItem('prices'),
          feedItem('exams', alert: false),
          feedItem('rates', published: DateTime(2026, 9, 20)),
          feedItem('gazettes', group: 'elections'),
          feedItem('gazettes', group: 'energy'),
        ];
        final on = {
          for (final alert in AlertSwitch.values)
            if (alert.on) alert,
        };

        expect(
          [for (final item in itemsToAlert(items, on: on, now: now)) item.id],
          ['prices-null', 'gazettes-energy'],
        );
      },
    );
  });

  group('notifications', () {
    test('a payload names its item', () {
      expect(itemIdFrom(itemPayload('gazette-2510-20')), 'gazette-2510-20');
      expect(itemIdFrom(null), isNull);
      expect(itemIdFrom('other'), isNull);
    });

    test('IDs stay the same for an item and differ between items', () {
      expect(
        notificationId('gazette-2510-20'),
        notificationId('gazette-2510-20'),
      );
      expect(
        notificationId('gazette-2510-20'),
        isNot(notificationId('gazette-2510-21')),
      );
      expect(notificationId('x'), greaterThan(0));
    });

    test('the body shows key numbers, or who published the item', () {
      final fuel = feedItem(
        'prices',
        numbers: const [
          KeyNumber(
            label: 'Lanka Petrol 92 Octane',
            value: 399,
            unit: 'LKR',
            previous: 414,
          ),
        ],
      );

      expect(notificationBody(fuel), 'Petrol 92 399 (was 414)');
      expect(notificationBody(feedItem('exams')), contains('Issuer'));
    });

    test('pulled down, it shows the whole headline and the numbers', () {
      final fuel = feedItem(
        'prices',
        numbers: const [
          KeyNumber(label: 'Auto Diesel', value: 392, unit: 'LKR'),
        ],
      );

      expect(notificationText(fuel), 'Headline\nDiesel 392');
      expect(notificationText(feedItem('exams')), 'Headline');
    });
  });

  group('background sync', () {
    late AppDatabase database;
    late FakeBranch remote;
    late FakeSources sources;
    late FakeNotifier notifier;
    late DateTime now;

    setUp(() {
      database = memoryDatabase();
      remote = FakeBranch()
        ..putMonth('2026-10', [
          item('gazette-2510-20', '2026-10-12', group: 'labour'),
        ]);
      sources = FakeSources();
      notifier = FakeNotifier();
      now = DateTime(2026, 10, 16, 9);
    });

    tearDown(() => database.close());

    Future<void> sync() => BackgroundSync(
      feed: FeedRepository(
        database: database,
        remote: remote.branch,
        now: () => now,
      ),
      phone: sources.repository(database, now: () => now),
      alerts: fakeAlerts(database, notifier),
      now: () => now,
    ).run();

    /// CEYPETCO's answer with Petrol 92 at [price] from 16 October.
    void petrol92At(num price) {
      final json = jsonDecode(sources.ceypetco) as Map<String, Object?>;
      for (final row in json['data']! as List<Object?>) {
        final fuel = row! as Map<String, Object?>;
        if (fuel['product'] == 'Lanka Petrol 92 Octane') {
          fuel['price'] = price;
          fuel['effectiveDate'] = '2026-10-16T00:00:00.000Z';
        }
      }
      sources.ceypetco = jsonEncode(json);
    }

    test('a change in fuel prices alerts once', () async {
      await sync();
      petrol92At(399);
      now = now.add(const Duration(hours: 3));

      await sync();
      expect(notifier.fuelChanges, ['Petrol 92 399 (was 414)']);

      now = now.add(const Duration(hours: 3));
      await sync();
      expect(notifier.fuelChanges, hasLength(1));
    });

    test('no fuel alert with the Prices switch off', () async {
      await sync();
      await fakeAlerts(database).setSwitch(AlertSwitch.prices, on: false);
      petrol92At(399);
      now = now.add(const Duration(hours: 3));

      await sync();

      expect(notifier.fuelChanges, isEmpty);
    });

    test(
      'a fuel gazette with prices CEYPETCO gave already stays quiet',
      () async {
        await sync();
        petrol92At(399);
        remote.putMonth('2026-10', [
          {
            ...item('gazette-2510-30', '2026-10-15', topic: 'prices'),
            'keyNumbers': [
              {
                'label': 'Lanka Petrol 92 Octane',
                'value': 399,
                'unit': 'LKR',
                'previous': 414,
              },
            ],
          },
          item('gazette-2510-20', '2026-10-12', group: 'labour'),
        ]);
        now = now.add(const Duration(hours: 3));

        await sync();

        expect(notifier.fuelChanges, hasLength(1));
        expect(notifier.shown, isEmpty);
      },
    );

    test("the phone's own USD/LKR move alerts the day it happens", () async {
      await sync();
      // CBSL's rates on the phone run to the 16th, about 331.
      await database.saveRates([const RateRow(day: '2026-10-19', rate: 340)]);
      now = DateTime(2026, 10, 19, 10);

      await sync();

      expect(notifier.shownIds, ['rates-usd-lkr-2026-10-19']);
    });

    test(
      'schedules the holiday reminders from the holidays just read',
      () async {
        remote.files['datasets/holidays.json'] = jsonEncode({
          'schema': 1,
          'holidays': [
            {
              'date': '2026-10-25',
              'name': 'Vap Full Moon Poya Day',
              'tentative': false,
            },
          ],
        });

        await sync();
        expect(notifier.reminders.single.at, DateTime(2026, 10, 24, 19));

        await fakeAlerts(database).setSwitch(AlertSwitch.holidays, on: false);
        await sync();
        expect(notifier.reminders, isEmpty);
      },
    );

    void publishMore() => remote.putMonth('2026-10', [
      item('exam-2480', '2026-10-15', topic: 'exams'),
      item('gazette-2510-22', '2026-10-15', group: 'elections'),
      item('gazette-2510-21', '2026-10-14', group: 'labour'),
      item('gazette-2510-20', '2026-10-12', group: 'labour'),
    ]);

    test('the first sync of a fresh install alerts for nothing', () async {
      await sync();

      expect(notifier.shown, isEmpty);
    });

    test('a later sync alerts for each new item whose switch is on', () async {
      await sync();
      publishMore();
      now = now.add(const Duration(hours: 3));

      await sync();

      expect(notifier.shownIds, ['exam-2480', 'gazette-2510-21']);
    });

    test('nothing alerts while the app is in front', () async {
      await sync();
      publishMore();
      now = now.add(const Duration(hours: 3));
      await fakeAlerts(database).appShown(now);

      await sync();

      expect(notifier.shown, isEmpty);
    });

    test('a switch turned off stays quiet', () async {
      await sync();
      await fakeAlerts(database).setSwitch(AlertSwitch.exams, on: false);
      publishMore();
      now = now.add(const Duration(hours: 3));

      await sync();

      expect(notifier.shownIds, ['gazette-2510-21']);
    });

    test('records when it ran', () async {
      await sync();

      expect(await fakeAlerts(database).lastSync(), now);
    });

    group('in quiet hours', () {
      setUp(() => now = DateTime(2026, 10, 15, 21));

      Future<void> syncInTheNight() async {
        await sync();
        publishMore();
        now = DateTime(2026, 10, 15, 23, 30);
        await sync();
      }

      test('alerts wait for the first sync after the end', () async {
        await syncInTheNight();
        expect(notifier.shown, isEmpty);

        now = DateTime(2026, 10, 16, 6, 40);
        await sync();
        expect(notifier.shownIds, ['exam-2480', 'gazette-2510-21']);

        now = now.add(const Duration(hours: 3));
        await sync();
        expect(notifier.shown, hasLength(1));
      });

      test('opening the app drops what they held', () async {
        await syncInTheNight();
        final alerts = fakeAlerts(database);
        await alerts.appShown(DateTime(2026, 10, 16, 6, 10));
        await alerts.appHidden();

        now = DateTime(2026, 10, 16, 6, 40);
        await sync();

        expect(notifier.shown, isEmpty);
      });

      test('a switch turned off in the night drops what it held', () async {
        await syncInTheNight();
        await fakeAlerts(database).setSwitch(AlertSwitch.exams, on: false);

        now = DateTime(2026, 10, 16, 6, 40);
        await sync();

        expect(notifier.shownIds, ['gazette-2510-21']);
      });

      test('a fuel change waits for the first sync after the end', () async {
        await sync();
        petrol92At(399);
        now = DateTime(2026, 10, 15, 23, 30);
        await sync();
        expect(notifier.fuelChanges, isEmpty);

        now = DateTime(2026, 10, 16, 6, 40);
        await sync();
        expect(notifier.fuelChanges, ['Petrol 92 399 (was 414)']);
      });

      test('alerts go out at once with quiet hours off', () async {
        await fakeAlerts(database).setQuietHours(const QuietHours(on: false));

        await syncInTheNight();

        expect(notifier.shownIds, ['exam-2480', 'gazette-2510-21']);
      });
    });
  });

  group('fuel', () {
    FuelPriceRow price(String product, double value, String effective) =>
        FuelPriceRow(product: product, effective: effective, price: value);

    final before = [
      price('Lanka Petrol 92 Octane', 414, '2026-09-30'),
      price('Lanka Auto Diesel', 392, '2026-09-30'),
      price('Lanka Kerosene', 285, '2026-05-30'),
    ];

    test('a change lists what changed, in the order of the Now card', () {
      final after = [
        ...before,
        price('Lanka Auto Diesel', 380, '2026-10-17'),
        price('Lanka Petrol 92 Octane', 399, '2026-10-17'),
      ];

      expect(
        fuelChanges(before, after),
        'Petrol 92 399 (was 414), Diesel 380 (was 392)',
      );
    });

    test('no change, or the first read, says nothing', () {
      expect(fuelChanges(before, before), isNull);
      expect(fuelChanges(const [], before), isNull);
    });

    test('a fuel gazette adds nothing when the phone has its prices', () {
      KeyNumber petrol92(double value) =>
          KeyNumber(label: 'Lanka Petrol 92 Octane', value: value, unit: 'LKR');

      expect(
        fuelPricesKnown(feedItem('prices', numbers: [petrol92(414)]), before),
        isTrue,
      );
      expect(
        fuelPricesKnown(feedItem('prices', numbers: [petrol92(399)]), before),
        isFalse,
      );
      expect(fuelPricesKnown(feedItem('exams'), before), isFalse);
    });
  });

  group('holiday reminders', () {
    final holidays = [
      HolidayNow(
        day: DateTime(2026, 10, 25),
        name: 'Vap Full Moon Poya Day',
        tamil: 'Tamil name',
      ),
      HolidayNow(
        day: DateTime(2026, 11, 8),
        name: 'Deepavali Festival Day',
        tentative: true,
      ),
    ];

    test('go out at 19:00 the evening before, while that is to come', () {
      expect(
        holidayReminders(holidays, now: DateTime(2026, 10, 24, 18)).first.at,
        DateTime(2026, 10, 24, 19),
      );
      expect(holidayReminders(holidays, now: DateTime(2026, 10, 24, 19, 30)), [
        HolidayReminder(holidays[1]),
      ]);
    });

    test('name the holiday, mark a tentative date, then the Tamil name', () {
      expect(HolidayReminder(holidays[0]).body, '''
Vap Full Moon Poya Day
Tamil name''');
      expect(
        HolidayReminder(holidays[1]).body,
        'Deepavali Festival Day (tentative)',
      );
    });
  });

  group('quiet hours', () {
    test('hold alerts from the start, across midnight, up to the end', () {
      const quiet = QuietHours();

      expect(quiet.holds(DateTime(2026, 10, 16, 21, 59)), isFalse);
      expect(quiet.holds(DateTime(2026, 10, 16, 22)), isTrue);
      expect(quiet.holds(DateTime(2026, 10, 17, 3)), isTrue);
      expect(quiet.holds(DateTime(2026, 10, 17, 5, 59)), isTrue);
      expect(quiet.holds(DateTime(2026, 10, 17, 6)), isFalse);
    });

    test('also within a day, and never when off or empty', () {
      const afternoon = QuietHours(start: 13 * 60, end: 15 * 60);

      expect(afternoon.holds(DateTime(2026, 10, 16, 14)), isTrue);
      expect(afternoon.holds(DateTime(2026, 10, 16, 15)), isFalse);
      expect(afternoon.holds(DateTime(2026, 10, 16, 12)), isFalse);
      expect(
        const QuietHours(on: false).holds(DateTime(2026, 10, 16, 23)),
        isFalse,
      );
      expect(
        const QuietHours(start: 600, end: 600).holds(DateTime(2026, 10, 16)),
        isFalse,
      );
    });
  });

  group('alerts repository', () {
    late AppDatabase database;

    setUp(() => database = memoryDatabase());
    tearDown(() => database.close());

    test(
      'the in-front mark goes when the app hides, or when it is old',
      () async {
        final alerts = fakeAlerts(database);
        final now = DateTime(2026, 10, 16, 9);

        await alerts.appShown(now);
        expect(await alerts.appInFront(now), isTrue);
        expect(
          await alerts.appInFront(now.add(const Duration(hours: 13))),
          isFalse,
        );

        await alerts.appHidden();
        expect(await alerts.appInFront(now), isFalse);
      },
    );

    test('asks for the permission once', () async {
      final notifier = FakeNotifier();
      final alerts = fakeAlerts(database, notifier);

      await alerts.askPermissionOnce();
      await alerts.askPermissionOnce();

      expect(notifier.permissionRequests, 1);
    });

    test('quiet hours start on, 22:00 to 06:00, and keep a change', () async {
      final alerts = fakeAlerts(database);
      expect(await alerts.quietHours(), const QuietHours());

      const change = QuietHours(on: false, start: 23 * 60 + 30, end: 7 * 60);
      await alerts.setQuietHours(change);

      expect(await alerts.quietHours(), change);
    });

    test('holds items once each, until cleared', () async {
      final alerts = fakeAlerts(database);

      await alerts.hold(['a', 'b']);
      await alerts.hold(['b', 'c']);
      expect(await alerts.held(), ['a', 'b', 'c']);

      await alerts.clearHeld();
      expect(await alerts.held(), isEmpty);
    });
  });
}
