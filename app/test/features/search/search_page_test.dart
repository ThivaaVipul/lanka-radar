import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/features/search/view/search_page.dart';

import '../../helpers/fake_branch.dart';
import '../../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeBranch remote;
  late FeedRepository feed;
  late TabSelection tabs;

  setUp(() {
    database = memoryDatabase();
    remote = FakeBranch()
      ..putMonth('2026-10', [
        item(
          'gazette-2509-31',
          '2026-10-07',
          topic: 'prices',
          headline: 'Revise the Fuel Price',
          issuer: 'Ministry of Energy',
        ),
        item('gazette-2510-20', '2026-10-12', headline: 'Udapalatha vacancy'),
      ]);
    feed = FeedRepository(database: database, remote: remote.branch);
    tabs = TabSelection();
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  Future<void> open(WidgetTester tester) async {
    final phone = FakeSources().repository(database);
    await tester.runAsync(() async {
      await feed.refresh();
      await phone.refresh();
    });
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: feed),
          RepositoryProvider.value(value: phone),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(SearchPage.route(tabs)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('offers common searches before typing', (tester) async {
    await open(tester);

    expect(find.widgetWithText(ActionChip, 'Petrol 92'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Poya'), findsOneWidget);
  });

  testWidgets('groups what it finds: the price, then the notice', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), 'fuel');
    await settle(tester);

    expect(find.text('Prices'), findsOneWidget);
    expect(find.text('Notices'), findsOneWidget);
    expect(find.text('Dates'), findsNothing);
    expect(find.text('Diesel'), findsOneWidget);

    await tester.tap(find.text('Only notices'));
    await settle(tester);
    expect(find.text('Prices'), findsNothing);
    expect(find.text('All results'), findsOneWidget);
  });

  testWidgets('a fuel price opens the Prices tab', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Diesel'));
    await settle(tester);
    await tester.tap(find.textContaining('CEYPETCO').first);
    await settle(tester);

    expect(tabs.value, HomeTab.prices);
    expect(find.byType(SearchPage), findsNothing);
  });

  testWidgets('remembers a search and forgets it on request', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), 'udapalatha');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    await tester.tap(find.byTooltip('Clear'));
    await settle(tester);

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('udapalatha'), findsOneWidget);

    await tester.tap(find.byTooltip('Forget'));
    await settle(tester);
    expect(find.text('Recent'), findsNothing);
  });
}
