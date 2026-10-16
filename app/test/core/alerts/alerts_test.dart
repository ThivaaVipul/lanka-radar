import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/background_sync.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/alerts/quiet_hours.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';

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
    late FakeNotifier notifier;
    late DateTime now;

    setUp(() {
      database = memoryDatabase();
      remote = FakeBranch()
        ..putMonth('2026-10', [
          item('gazette-2510-20', '2026-10-12', group: 'labour'),
        ]);
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
      phone: FakeSources().repository(database, now: () => now),
      alerts: fakeAlerts(database, notifier),
      now: () => now,
    ).run();

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

      test('alerts go out at once with quiet hours off', () async {
        await fakeAlerts(database).setQuietHours(const QuietHours(on: false));

        await syncInTheNight();

        expect(notifier.shownIds, ['exam-2480', 'gazette-2510-21']);
      });
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
