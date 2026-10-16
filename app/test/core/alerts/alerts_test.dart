import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/background_sync.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
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
  });
}
