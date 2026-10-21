import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';

import '../../../helpers/fake_branch.dart';
import '../../../helpers/fake_home_widget.dart';
import '../../../helpers/fake_notifier.dart';
import '../../../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeBranch remote;
  late DateTime now;
  late FeedRepository feed;
  late HomeCubit cubit;
  late FakeNotifier notifier;
  late FakeHomeScreenWidget homeWidget;

  setUp(() {
    database = memoryDatabase();
    remote = FakeBranch()
      ..putMonth('2026-10', [
        item('gazette-2510-20', '2026-10-12'),
        item('exam-2479', '2026-10-01', topic: 'exams'),
      ]);
    now = DateTime(2026, 10, 16, 9);
    feed = FeedRepository(
      database: database,
      remote: remote.branch,
      now: () => now,
    );
    notifier = FakeNotifier();
    homeWidget = FakeHomeScreenWidget();
    cubit = HomeCubit(
      feed,
      FakeSources().repository(database, now: () => now),
      fakeAlerts(database, notifier),
      homeWidget,
      now: () => now,
    );
  });

  tearDown(() async {
    await cubit.close();
    await database.close();
  });

  List<String> visible() => [
    for (final item in cubit.state.visibleItems!) item.id,
  ];

  test('watching refreshes a stale feed and shows its items', () async {
    await cubit.watch();

    expect(cubit.state.failed, isFalse);
    expect(visible(), ['gazette-2510-20', 'exam-2479']);
  });

  test('load shedding reminders are set from what the app shows', () async {
    await storePowerSetup(FakeSources().repository(database));

    await cubit.watch();

    expect(
      [for (final reminder in notifier.cutReminders) reminder.at],
      [DateTime(2026, 10, 20, 19), DateTime(2026, 10, 21, 16)],
    );
  });

  test(
    'the home-screen widget gets the numbers, again only when they change',
    () async {
      await cubit.watch();
      final shown = homeWidget.shown.length;

      expect(homeWidget.shown.last, cubit.state.nowCard);
      await cubit.reloadNow();
      expect(homeWidget.shown, hasLength(shown));
    },
  );

  test('a failed refresh keeps the items already shown', () async {
    await cubit.watch();
    remote.offline = true;

    await cubit.refresh();

    expect(cubit.state.failed, isTrue);
    expect(cubit.state.refreshing, isFalse);
    expect(cubit.state.items, hasLength(2));
  });

  test('a first refresh that fails leaves an empty, failed feed', () async {
    remote.offline = true;

    await cubit.watch();

    expect(cubit.state.failed, isTrue);
    expect(cubit.state.items, isEmpty);
  });

  test('a topic chip shows only that topic', () async {
    await cubit.watch();

    cubit.showTopic('exams');
    expect(visible(), ['exam-2479']);

    cubit.showTopic(null);
    expect(visible(), ['gazette-2510-20', 'exam-2479']);
  });

  test('a fresh install marks nothing new', () async {
    await cubit.watch();

    expect(cubit.state.items!.where(cubit.state.isNew), isEmpty);
  });

  test('items that arrived since the last visit are new, history is not, and '
      'leaving clears them', () async {
    await cubit.watch();
    now = now.add(const Duration(hours: 1));
    await cubit.leave();
    remote.putMonth('2026-10', [
      item('gazette-2510-21', '2026-10-15'),
      item('gazette-2510-20', '2026-10-12'),
      item('exam-2479', '2026-10-01', topic: 'exams'),
    ]);
    remote.putMonth('2026-02', [item('gazette-2477-45', '2026-02-28')]);
    now = now.add(const Duration(hours: 3));

    await cubit.resume();

    final fresh = [
      for (final item in cubit.state.items!)
        if (cubit.state.isNew(item)) item.id,
    ];
    expect(fresh, ['gazette-2510-21']);

    now = now.add(const Duration(minutes: 5));
    await cubit.leave();
    await cubit.resume();
    expect(cubit.state.items!.where(cubit.state.isNew), isEmpty);
  });

  test('asks for the notification permission once, after a refresh that '
      'brings the feed', () async {
    remote.offline = true;
    await cubit.watch();
    expect(notifier.permissionRequests, 0);

    remote.offline = false;
    await cubit.refresh();
    await cubit.refresh();

    expect(notifier.permissionRequests, 1);
  });

  test('coming back shows items a background sync stored', () async {
    // The background sync opens the same file through its own connection,
    // whose writes the app's queries don't see by themselves.
    final folder = await Directory.systemTemp.createTemp('lanka_radar_');
    final path = '${folder.path}/lanka_radar.sqlite';
    final app = AppDatabase(NativeDatabase(File(path)));
    final background = AppDatabase(NativeDatabase(File(path)));
    final home = HomeCubit(
      FeedRepository(database: app, remote: remote.branch, now: () => now),
      FakeSources().repository(app, now: () => now),
      fakeAlerts(app),
      FakeHomeScreenWidget(),
      now: () => now,
    );
    addTearDown(() async {
      await home.close();
      await app.close();
      await background.close();
      await folder.delete(recursive: true);
    });
    await home.watch();
    await home.leave();
    remote.putMonth('2026-10', [
      item('gazette-2510-21', '2026-10-15'),
      item('gazette-2510-20', '2026-10-12'),
      item('exam-2479', '2026-10-01', topic: 'exams'),
    ]);
    now = now.add(const Duration(hours: 3));
    await FeedRepository(
      database: background,
      remote: remote.branch,
      now: () => now,
    ).refresh();

    await home.resume();
    await pumpEventQueue();

    expect(home.state.items, hasLength(3));
  });

  test('Today lists what is new, else the latest, never election or weekly '
      'gazette notices', () async {
    final october = [
      item('gazette-2510-20', '2026-10-12'),
      item('gazette-2510-19', '2026-10-11', group: 'elections'),
      item('exam-2479', '2026-10-01', topic: 'exams'),
    ];
    remote.putMonth('2026-10', october);
    List<String> today() => [
      for (final item in cubit.state.todayItems) item.id,
    ];

    await cubit.watch();
    expect(cubit.state.todayHasNew, isFalse);
    expect(today(), ['gazette-2510-20', 'exam-2479']);

    now = now.add(const Duration(hours: 1));
    await cubit.leave();
    remote.putMonth('2026-10', [
      item('gazette-2510-22', '2026-10-15', group: 'elections'),
      item('gazette-2510-21', '2026-10-15'),
      notice('weekly-2510-a', '2026-10-09'),
      ...october,
    ]);
    now = now.add(const Duration(hours: 3));
    await cubit.resume();

    expect(cubit.state.todayHasNew, isTrue);
    expect(today(), ['gazette-2510-21']);
  });
}
