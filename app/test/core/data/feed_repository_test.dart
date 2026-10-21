import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/rate_moves.dart';

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
      FeedRepository.textsIndexPath,
      ...FeedRepository.documents,
    ]);
    expect(await feed.lastRefresh(), now);
  });

  test(
    "a dataset the workflow hasn't written yet doesn't stop a refresh",
    () async {
      const path = 'datasets/holidays.json';
      final holidays = remote.files.remove(path)!;
      await feed.refresh();

      expect(remote.requests.last, 'status.json');
      expect(await database.file(path), isNull);

      remote.files[path] = holidays;
      await feed.refresh();
      expect((await database.file(path))?.body, holidays);
    },
  );

  test('a second refresh downloads nothing that is unchanged', () async {
    await feed.refresh();
    remote.requests.clear();

    await feed.refresh();

    expect(remote.requests, [
      'months/index.json',
      FeedRepository.textsIndexPath,
      ...FeedRepository.documents,
    ]);
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
      ' filling of a vacancy ta election commission gazettes gazette 2510/20',
    );
  });

  group('search', () {
    setUp(() async {
      remote.putMonth('2026-10', [
        item(
          'gazette-2510-20',
          '2026-10-12',
          headline: 'FILLING OF A VACANCY IN UDAPALATHA',
          tamil: 'ABCD',
          number: '2510/20',
        ),
        item(
          'exam-2479',
          '2026-10-01',
          topic: 'exams',
          headline: 'G.C.E. (O/L) 100% Time Table',
          issuer: 'Department of Examinations',
        ),
      ]);
      await feed.refresh();
    });

    Future<List<String>> found(String query) async => [
      for (final item in await feed.search(query)) item.id,
    ];

    test('matches every word, in any case, in headlines, issuer and '
        'number', () async {
      expect(await found('vacancy udapalatha'), ['gazette-2510-20']);
      expect(await found('EXAMINATIONS'), ['exam-2479']);
      expect(await found('2510/20'), ['gazette-2510-20']);
      expect(await found('abc'), ['gazette-2510-20']);
      expect(await found('vacancy examinations'), isEmpty);
    });

    test('finds what the cards show and other ways of writing it', () async {
      remote.putMonth('2026-09', [
        {
          ...item('gazette-2509-31', '2026-09-30', topic: 'prices'),
          'keyNumbers': [
            {
              'label': 'Lanka Auto Diesel',
              'value': 392,
              'unit': 'LKR',
              'previous': 400,
            },
          ],
        },
      ]);
      await feed.refresh();

      expect(await found('diesel'), ['gazette-2509-31']);
      expect(await found('fuel'), ['gazette-2509-31']);
      expect(await found('prices'), ['gazette-2509-31']);
      expect(await found('timetable'), ['exam-2479']);
      expect(await found('exams'), ['exam-2479']);
      expect(await found('gazette 2510/20'), ['gazette-2510-20']);
    });

    test(
      'items stored before search learned the cards are found too',
      () async {
        await database.customStatement("UPDATE items SET search = 'old'");
        expect(await found('timetable'), isEmpty);

        await database.reindexSearch();

        expect(await found('timetable'), ['exam-2479']);
      },
    );

    test(
      "a query's punctuation is not a word, and finds nothing alone",
      () async {
        expect(await found('100%'), ['exam-2479']);
        expect(await found('(o/l)'), ['exam-2479']);
        expect(await found('%'), isEmpty);
        expect(await found('_'), isEmpty);
      },
    );

    test('words match from their start, so rice is not price', () async {
      remote.putMonth('2026-09', [
        item('gazette-2509-40', '2026-09-20', headline: 'Maximum Retail Price'),
      ]);
      await feed.refresh();

      expect(await found('rice'), isEmpty);
      expect(await found('pri'), ['gazette-2509-40']);
      expect(await found('table'), ['exam-2479']);
    });

    test('an empty query finds nothing', () async {
      expect(await found('   '), isEmpty);
    });
  });

  test('remembers when the feed was last left', () async {
    expect(await feed.lastVisit(), isNull);

    await feed.saveVisit(DateTime(2026, 10, 16, 10, 30));

    expect(await feed.lastVisit(), DateTime(2026, 10, 16, 10, 30));
  });

  test('keeps the last searches, newest first, once each', () async {
    for (final query in ['tuna', 'poya', 'Tuna', 'a', 'b', 'c', 'd']) {
      await feed.rememberSearch(query);
    }
    expect(await feed.recentSearches(), ['d', 'c', 'b', 'a', 'Tuna']);

    await feed.forgetSearch('b');
    expect(await feed.recentSearches(), ['d', 'c', 'a', 'Tuna']);
  });

  test('items carry when the phone first saw them', () async {
    await feed.refresh();

    final items = await feed.watchItems().first;
    expect(items.map((item) => item.firstSeen), everyElement(now));
  });

  group("the phone's own USD/LKR moves", () {
    const move = 'rates-usd-lkr-2026-10-19';

    void workflowRates(Map<String, double> rates) =>
        remote.files[FeedRepository.usdLkrPath] = jsonEncode({
          'source': 'frankfurter',
          'rates': [
            for (final MapEntry(key: day, value: rate) in rates.entries)
              {'date': day, 'rate': rate},
          ],
        });

    // The workflow's rates reach 9 October; CBSL's on the phone go on to the
    // 19th, which jumps 2.7% on a week before.
    setUp(() async {
      workflowRates({
        for (final day in ['2026-10-05', '2026-10-06', '2026-10-09']) day: 331,
      });
      await database.saveRates([
        for (final day in ['2026-10-12', '2026-10-13', '2026-10-14'])
          RateRow(day: day, rate: 331),
        const RateRow(day: '2026-10-19', rate: 340),
      ]);
      await feed.refresh();
      await feed.updatePhoneItems();
    });

    test('are made for the days the workflow has not reached', () async {
      final item = await feed.item(move);

      expect(item?.headlineEn, 'USD/LKR up 2.7% in a week, to 340.00');
      expect(item?.firstSeen, now);
      expect(await ids(), hasLength(4));
    });

    test('stay through a refresh of their month, as first seen', () async {
      final seen = now;
      now = now.add(const Duration(hours: 3));
      remote.putMonth('2026-10', [item('gazette-2510-21', '2026-10-14')]);

      await feed.refresh();
      await feed.updatePhoneItems();

      expect(await ids(), contains('gazette-2510-21'));
      // Made again, it would alert again.
      expect((await feed.item(move))?.firstSeen, seen);
    });

    test("give way to the workflow's copy, which keeps when the phone saw it "
        'first', () async {
      final seen = now;
      now = now.add(const Duration(hours: 3));
      workflowRates({'2026-10-12': 331, '2026-10-19': 340.5});
      remote.putMonth('2026-10', [
        moveItem(const RateMove(day: '2026-10-19', rate: 340.5, weekAgo: 331)),
      ]);

      await feed.refresh();
      await feed.updatePhoneItems();

      final item = await feed.item(move);
      expect(item?.keyNumbers.single.value, 340.5);
      expect(item?.firstSeen, seen);
    });

    test("go once the workflow's rates show no move that day", () async {
      workflowRates({'2026-10-12': 331, '2026-10-19': 332});

      await feed.refresh();
      await feed.updatePhoneItems();

      expect(await feed.item(move), isNull);
    });
  });

  group("the gazettes' text", () {
    setUp(() {
      remote.putTexts('2026-10', {
        'gazette-2510-20':
            'By virtue of the powers vested in me, the import of rice from '
            'Kilinochchi is exempted from the special commodity levy.',
        'exam-2479': 'A Headline for the examination at Kilinochchi.',
      });
    });

    test('is stored, and finds what titles do not', () async {
      await feed.refresh();

      final hits = await feed.searchInside('kilinochchi rice');
      expect([for (final hit in hits) hit.item.id], ['gazette-2510-20']);
      expect(hits.single.line, contains('import of rice from Kilinochchi'));
      expect(await feed.searchInside('levy'), hasLength(1));
      expect(await feed.searchInside('evy'), isEmpty);
    });

    test('leaves out what the title search found', () async {
      await feed.refresh();

      final hits = await feed.searchInside(
        'kilinochchi',
        excluding: {'exam-2479'},
      );

      expect([for (final hit in hits) hit.item.id], ['gazette-2510-20']);
    });

    test('only a changed month is downloaded, and a month gone goes', () async {
      await feed.refresh();
      remote.requests.clear();

      await feed.refresh();
      expect(
        remote.requests.where((path) => path.startsWith('texts/20')),
        isEmpty,
      );

      remote
        ..putTexts('2026-09', {'gazette-2509-59': 'Kandy council vacancy.'})
        ..files.remove('texts/2026-10.json');
      final index =
          jsonDecode(remote.files['texts/index.json']!) as Map<String, Object?>;
      remote.files['texts/index.json'] = jsonEncode({
        ...index,
        'months': [
          for (final month in index['months']! as List<Object?>)
            if ((month! as Map<String, Object?>)['month'] != '2026-10') month,
        ],
      });
      await feed.refresh();

      expect(await feed.searchInside('kilinochchi'), isEmpty);
      expect(await feed.searchInside('kandy'), hasLength(1));
    });
  });
}
