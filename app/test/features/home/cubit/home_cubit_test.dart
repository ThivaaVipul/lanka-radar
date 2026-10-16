import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';

import '../../../helpers/fake_branch.dart';

void main() {
  late AppDatabase database;
  late FakeBranch remote;
  late HomeCubit cubit;

  setUp(() {
    database = memoryDatabase();
    remote = FakeBranch()
      ..putMonth('2026-10', [item('gazette-2510-20', '2026-10-12')]);
    cubit = HomeCubit(
      FeedRepository(database: database, remote: remote.branch),
    );
  });

  tearDown(() async {
    await cubit.close();
    await database.close();
  });

  Future<HomeState> settled() => cubit.stream.firstWhere(
    (state) =>
        !state.refreshing && (state.failed || (state.items ?? []).isNotEmpty),
  );

  test('watching refreshes a stale feed and shows its items', () async {
    cubit.watch();

    final state = await settled();

    expect(state.failed, isFalse);
    expect([for (final item in state.items!) item.id], ['gazette-2510-20']);
  });

  test('a failed refresh keeps the items already shown', () async {
    cubit.watch();
    await settled();
    remote.offline = true;

    await cubit.refresh();

    expect(cubit.state.failed, isTrue);
    expect(cubit.state.refreshing, isFalse);
    expect(cubit.state.items, hasLength(1));
  });

  test('a first refresh that fails leaves an empty, failed feed', () async {
    remote.offline = true;
    cubit.watch();

    final state = await settled();

    expect(state.failed, isTrue);
    expect(state.items, isEmpty);
  });
}
