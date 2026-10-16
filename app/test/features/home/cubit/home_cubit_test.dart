import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';

import '../../../helpers/fake_branch.dart';

void main() {
  late AppDatabase database;
  late FakeBranch remote;
  late DateTime now;
  late FeedRepository feed;
  late HomeCubit cubit;

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
    cubit = HomeCubit(feed, now: () => now);
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
}
