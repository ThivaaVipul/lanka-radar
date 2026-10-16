import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/app.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/search/view/search_page.dart';

import '../helpers/fake_branch.dart';
import '../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeBranch remote;

  setUp(() {
    database = memoryDatabase();
    remote = FakeBranch();
  });

  tearDown(() => database.close());

  Future<void> open(WidgetTester tester) async {
    final feed = FeedRepository(database: database, remote: remote.branch);
    final now = FakeSources().repository(database);
    await tester.pumpWidget(LankaRadarApp(feed: feed, now: now));
    await settle(tester);
  }

  testWidgets('shows the feed under month headings, in title case', (
    tester,
  ) async {
    remote
      ..putMonth('2026-10', [
        item(
          'gazette-2510-20',
          '2026-10-12',
          headline: 'FILLING OF A VACANCY IN THE OFFICE OF MEMBER',
        ),
      ])
      ..putMonth('2026-09', [
        item(
          'exam-2479',
          '2026-09-28',
          topic: 'exams',
          headline: 'G.C.E. (O/L) Time Table',
          issuer: 'Department of Examinations',
        ),
      ]);

    await open(tester);

    expect(find.text('Lanka Radar'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(
      find.text('Filling of a Vacancy in the Office of Member'),
      findsOneWidget,
    );
    expect(
      find.text(cardDate(DateTime(2026, 10, 12), today: DateTime.now())),
      findsOneWidget,
    );
  });

  testWidgets('a topic chip filters the feed', (tester) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', headline: 'A gazette'),
      item('exam-2479', '2026-10-01', topic: 'exams', headline: 'An exam'),
    ]);
    await open(tester);

    await tester.tap(find.text('Exams'));
    await tester.pumpAndSettle();

    expect(find.text('An exam'), findsOneWidget);
    expect(find.text('A gazette'), findsNothing);
  });

  testWidgets('a card opens its item', (tester) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', headline: 'A gazette'),
    ]);
    await open(tester);

    await tester.tap(find.text('A gazette'));
    await tester.pumpAndSettle();

    expect(find.byType(ItemPage), findsOneWidget);
  });

  testWidgets('search finds stored items as you type', (tester) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', headline: 'Udapalatha vacancy'),
      item('exam-2479', '2026-10-01', topic: 'exams', headline: 'An exam'),
    ]);
    await open(tester);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'udapalatha');
    await settle(tester);
    expect(find.text('Udapalatha vacancy'), findsOneWidget);
    expect(find.text('An exam'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing like this');
    await settle(tester);
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('says so when there is nothing yet', (tester) async {
    await open(tester);

    expect(find.text('Nothing yet'), findsOneWidget);
  });

  testWidgets('offers to try again when the first refresh fails', (
    tester,
  ) async {
    remote.offline = true;

    await open(tester);

    expect(find.text("Couldn't load the feed"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

/// Lets the database and the fake branch answer, then the screen catch up.
Future<void> settle(WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}
