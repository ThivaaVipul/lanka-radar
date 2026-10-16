import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';

import '../../helpers/fake_branch.dart';

void main() {
  late AppDatabase database;
  late FakeBranch remote;
  late DateTime now;
  late FeedRepository feed;

  setUp(() {
    database = memoryDatabase();
    remote = FakeBranch()
      ..putMonth('2026-10', [
        item('gazette-2510-20', '2026-10-12'),
        item('exam-2479', '2026-10-01', topic: 'exams'),
      ])
      ..putMonth('2026-09', [item('gazette-2509-59', '2026-09-08')]);
    now = DateTime(2026, 10, 16, 9);
    feed = FeedRepository(
      database: database,
      remote: remote.branch,
      now: () => now,
    );
  });

  tearDown(() => database.close());

  Future<List<String>> ids() async => [
    for (final item in await feed.watchItems().first) item.id,
  ];

  test('a first refresh stores every month, newest item first', () async {
    await feed.refresh();

    expect(await ids(), ['gazette-2510-20', 'exam-2479', 'gazette-2509-59']);
    expect(remote.requests, [
      'months/index.json',
      'months/2026-10.json',
      'months/2026-09.json',
      ...FeedRepository.documents,
    ]);
    expect(await feed.lastRefresh(), now);
  });

  test('a second refresh downloads nothing that is unchanged', () async {
    await feed.refresh();
    remote.requests.clear();

    await feed.refresh();

    expect(remote.requests, ['months/index.json', ...FeedRepository.documents]);
    expect(remote.unchanged, remote.requests);
  });

  test('only a changed month is downloaded, and items keep when they were '
      'first seen', () async {
    await feed.refresh();
    final firstSeen = now;
    remote.putMonth('2026-10', [
      item('gazette-2510-21', '2026-10-13'),
      item('gazette-2510-20', '2026-10-12', headline: 'Corrected'),
    ]);
    now = now.add(const Duration(hours: 3));
    remote.requests.clear();

    await feed.refresh();

    expect(remote.requests.where((path) => path.startsWith('months/20')), [
      'months/2026-10.json',
    ]);
    expect(await ids(), [
      'gazette-2510-21',
      'gazette-2510-20',
      'gazette-2509-59',
    ]);
    final rows = {
      for (final row in await database.select(database.items).get())
        row.id: row,
    };
    expect(rows['gazette-2510-20']!.firstSeen, firstSeen);
    expect(rows['gazette-2510-21']!.firstSeen, now);
    final items = await feed.watchItems().first;
    expect(items[1].headlineEn, 'Corrected');
  });

  test('a month gone from the index loses its items', () async {
    await feed.refresh();
    remote.dropMonth('2026-09');

    await feed.refresh();

    expect(await ids(), ['gazette-2510-20', 'exam-2479']);
    expect(await database.monthHashes(), contains('2026-10'));
    expect(await database.monthHashes(), isNot(contains('2026-09')));
  });

  test('a failed download keeps what is stored, and the next refresh asks '
      'for the index again', () async {
    await feed.refresh();
    final before = await feed.lastRefresh();
    remote
      ..putMonth('2026-10', [item('gazette-2510-21', '2026-10-13')])
      ..files.remove('months/2026-10.json');
    now = now.add(const Duration(hours: 3));

    await expectLater(feed.refresh(), throwsA(isA<Exception>()));

    expect(await ids(), ['gazette-2510-20', 'exam-2479', 'gazette-2509-59']);
    expect(await feed.lastRefresh(), before);

    remote.putMonth('2026-10', [item('gazette-2510-21', '2026-10-13')]);
    await feed.refresh();

    expect(await ids(), ['gazette-2510-21', 'gazette-2509-59']);
  });

  test('refreshIfStale waits until the last refresh is old enough', () async {
    const maxAge = Duration(minutes: 15);

    expect(await feed.refreshIfStale(maxAge), isTrue);
    now = now.add(const Duration(minutes: 10));
    expect(await feed.refreshIfStale(maxAge), isFalse);
    now = now.add(const Duration(minutes: 10));
    expect(await feed.refreshIfStale(maxAge), isTrue);
  });

  test('stores search text in lower case, Tamil included', () async {
    remote.putMonth('2026-10', [
      item(
        'gazette-2510-20',
        '2026-10-12',
        headline: 'FILLING OF A VACANCY',
        tamil: 'TA',
        number: '2510/20',
      ),
    ]);

    await feed.refresh();

    final row = await (database.select(
      database.items,
    )..where((row) => row.id.equals('gazette-2510-20'))).getSingle();
    expect(
      row.search,
      'filling of a vacancy\nta\nelection commission\n2510/20',
    );
  });
}
