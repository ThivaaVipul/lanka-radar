import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/app.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/app/notification_router.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/features/alerts/view/alerts_page.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/power/widgets/osm.dart';
import 'package:lanka_radar/features/power/widgets/place_row.dart';
import 'package:lanka_radar/features/search/view/search_page.dart';

import '../helpers/fake_branch.dart';
import '../helpers/fake_notifier.dart';
import '../helpers/fake_sharing.dart';
import '../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeBranch remote;
  late TabSelection tabs;
  late FakeSharing sharing;

  setUp(() {
    database = memoryDatabase();
    remote = FakeBranch();
    tabs = TabSelection();
    sharing = FakeSharing();
  });

  tearDown(() => database.close());

  Future<void> open(
    WidgetTester tester, {
    NotificationRouter? router,
    DateTime Function()? clock,
  }) async {
    // As with Android's "Remove animations": Power's rings stay still, so the
    // screens settle.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final feed = FeedRepository(database: database, remote: remote.branch);
    final now = FakeSources().repository(database, now: clock);
    await tester.pumpWidget(
      // Map tiles come from the network, which tests don't reach.
      NoMapTiles(
        child: LankaRadarApp(
          feed: feed,
          now: now,
          alerts: fakeAlerts(database),
          tabs: router?.tabs ?? tabs,
          sharing: sharing,
          navigatorKey: router?.navigatorKey,
        ),
      ),
    );
    await settle(tester);
  }

  NotificationRouter router() => NotificationRouter(
    FeedRepository(database: database, remote: remote.branch),
    tabs,
  );

  Future<void> showTab(WidgetTester tester, HomeTab tab) async {
    tabs.value = tab;
    await tester.pumpAndSettle();
  }

  /// A price order with one price and nothing before it.
  Map<String, Object?> tuna() => {
    ...item(
      'gazette-2509-40',
      '2026-10-10',
      topic: 'prices',
      issuer: 'Consumer Affairs Authority',
    ),
    'keyNumbers': [
      {'label': 'Tuna 155g', 'value': 220, 'unit': 'LKR', 'previous': null},
    ],
  };

  testWidgets('Today has the numbers and the latest items, not elections', (
    tester,
  ) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', group: 'elections'),
      tuna(),
    ]);

    await open(tester);

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Petrol 92'), findsOneWidget);
    expect(find.text('414'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Tuna 155g fixed at Rs 220'), findsOneWidget);
    expect(find.textContaining('Election'), findsNothing);
  });

  testWidgets('Notices go under month headings, election notices folded', (
    tester,
  ) async {
    remote
      ..putMonth('2026-10', [
        item(
          'gazette-2510-31',
          '2026-10-14',
          group: 'elections',
          headline: 'VACANCY IN ARANAYAKE',
        ),
        item(
          'gazette-2510-30',
          '2026-10-13',
          group: 'elections',
          headline: 'VACANCY IN UDAPALATHA',
        ),
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

    await showTab(tester, HomeTab.notices);

    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(
      find.text('Filling of a Vacancy in the Office of Member'),
      findsOneWidget,
    );
    expect(find.text('Election notices'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Vacancy in Aranayake'), findsNothing);

    await tester.tap(find.text('Election notices'));
    await tester.pumpAndSettle();
    expect(find.text('Vacancy in Aranayake'), findsOneWidget);
    expect(find.text('Vacancy in Udapalatha'), findsOneWidget);
  });

  testWidgets('a topic chip filters the notices', (tester) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', headline: 'A gazette'),
      item('exam-2479', '2026-10-01', topic: 'exams', headline: 'An exam'),
    ]);
    await open(tester);
    await showTab(tester, HomeTab.notices);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Exams'));
    await tester.pumpAndSettle();

    expect(find.text('An exam'), findsOneWidget);
    expect(find.text('A gazette'), findsNothing);
  });

  testWidgets('Dates counts down to the exams, long weekends and holidays', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime inDays(int days) =>
        DateTime(today.year, today.month, today.day + days);
    // A Friday at least a week away, which makes a long weekend.
    final friday = inDays(7 + (DateTime.friday - today.weekday + 7) % 7);
    remote
      ..files['datasets/holidays.json'] = jsonEncode({
        'schema': 1,
        'holidays': [
          {'date': isoDay(friday), 'name': 'A Friday holiday'},
        ],
      })
      ..putMonth('2026-10', [
        {
          ...item(
            'exam-2479',
            '2026-10-12',
            topic: 'exams',
            headline: 'G.C.E. (Ordinary Level) Examination - 2026 Time Table',
          ),
          'data': {
            'kind': 'timetable',
            'days': [isoDay(inDays(30)), isoDay(inDays(31))],
          },
        },
      ]);
    await open(tester);
    await showTab(tester, HomeTab.dates);

    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('O/L 2026'), findsOneWidget);
    expect(find.text('in 30 days'), findsOneWidget);
    expect(find.text('Long weekends'), findsOneWidget);
    final sunday = DateTime(friday.year, friday.month, friday.day + 2);
    expect(find.text('3 days, to ${weekdayDate(sunday)}'), findsOneWidget);
    expect(find.text('A Friday holiday'), findsWidgets);
    expect(find.byTooltip('Add to calendar'), findsNWidgets(3));

    await tester.tap(find.byTooltip('Add to calendar').first);
    await tester.pumpAndSettle();
    expect(find.text('No calendar app found'), findsNothing);

    await tester.tap(find.text('O/L 2026'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemPage), findsOneWidget);
  });

  testWidgets('Today puts the power cuts at a place first, and opens Power', (
    tester,
  ) async {
    remote.putMonth('2026-10', [item('gazette-2510-20', '2026-10-12')]);
    await tester.runAsync(
      () => storePowerSetup(FakeSources().repository(database)),
    );
    await open(tester);

    expect(find.text('Power cut at Home'), findsOneWidget);
    expect(find.text('Breakdown${dot}since 09:24'), findsOneWidget);

    await tester.tap(find.text('Power cut at Home'));
    await settle(tester);
    expect(tabs.value, HomeTab.power);
    expect(find.byType(PlaceRow), findsOneWidget);
  });

  testWidgets('a long press shares a notice, a price or a cut as text', (
    tester,
  ) async {
    remote.putMonth('2026-10', [item('gazette-2510-20', '2026-10-12')]);
    await tester.runAsync(
      () => storePowerSetup(FakeSources().repository(database)),
    );
    await open(tester);

    await tester.longPress(find.byType(ItemTile).first);
    await tester.longPress(find.text('Petrol 92'));
    await tester.longPress(find.text('Power cut at Home'));

    expect(sharing.shared, hasLength(3));
    expect(
      sharing.shared[0],
      endsWith(
        'Election Commission, 12 Oct 2026\n'
        'https://documents.gov.lk/web/extra_gazettes',
      ),
    );
    expect(sharing.shared[1], startsWith('Petrol 92: Rs '));
    expect(
      sharing.shared[2],
      startsWith('Power cut in Gampaha (CEB area): a breakdown since 09:24'),
    );
  });

  testWidgets('cuts to come show on Today and in Dates', (tester) async {
    remote.putMonth('2026-10', [item('gazette-2510-20', '2026-10-12')]);
    await tester.runAsync(
      () => FakeSources()
          .repository(database)
          .savePowerSetup(const PowerSetup(places: [homeWithAccount])),
    );
    await open(tester, clock: () => DateTime(2026, 10, 20, 12));

    // One card on Today, whichever day the test runs.
    expect(
      find.text('Load shedding at Home').evaluate().length +
          find.text('Power cuts ahead').evaluate().length,
      1,
    );

    await showTab(tester, HomeTab.dates);
    expect(find.text('Power cuts ahead'), findsOneWidget);
    expect(find.text('Load shedding at Home'), findsNWidgets(2));
    expect(find.text('19:30 to 20:30, group V'), findsOneWidget);
    expect(find.text('Maintenance at Home'), findsOneWidget);
  });

  testWidgets('Power starts with adding a place', (tester) async {
    remote.putMonth('2026-10', [item('gazette-2510-20', '2026-10-12')]);
    await open(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Power'));
    await settle(tester);

    expect(find.text('Watch for power cuts'), findsOneWidget);
    expect(find.text('Add a place'), findsOneWidget);
  });

  testWidgets('the bottom bar switches tabs', (tester) async {
    remote.putMonth('2026-10', [tuna()]);
    await open(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Prices'));
    await tester.pumpAndSettle();
    expect(find.text('Fuel'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Price orders'), 200);
    expect(find.text('Litro price list'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Dates'));
    await tester.pumpAndSettle();
    expect(find.text('Holidays'), findsOneWidget);
  });

  testWidgets('Prices lists market prices a section at a time', (tester) async {
    await tester.runAsync(() => storeMarketPrices(database));
    await open(tester);
    await showTab(tester, HomeTab.prices);

    await tester.scrollUntilVisible(
      find.text('Beans'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Samba'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Rice'));
    await tester.pumpAndSettle();
    expect(find.text('Samba'), findsOneWidget);
    expect(find.text('Beans'), findsNothing);
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

  testWidgets('a tapped notification opens its item', (tester) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', headline: 'A gazette'),
    ]);
    final notifications = router();
    await open(tester, router: notifications);

    await tester.runAsync(() => notifications.open('other'));
    await tester.runAsync(
      () => notifications.open(itemPayload('gazette-2510-99')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ItemPage), findsNothing);

    await tester.runAsync(
      () => notifications.open(itemPayload('gazette-2510-20')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ItemPage), findsOneWidget);
  });

  testWidgets('fuel and holiday notifications open Prices and Dates', (
    tester,
  ) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', headline: 'A gazette'),
    ]);
    final notifications = router();
    await open(tester, router: notifications);
    await tester.tap(find.text('A gazette'));
    await tester.pumpAndSettle();

    await tester.runAsync(() => notifications.open(fuelPayload));
    await tester.pumpAndSettle();
    expect(find.byType(ItemPage), findsNothing);
    expect(tabs.value, HomeTab.prices);
    expect(find.text('Fuel'), findsOneWidget);

    await tester.runAsync(() => notifications.open(holidaysPayload));
    await tester.pumpAndSettle();
    expect(tabs.value, HomeTab.dates);
    expect(find.text('Holidays'), findsOneWidget);
  });

  testWidgets('a notification that started the app opens its item once', (
    tester,
  ) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', headline: 'A gazette'),
    ]);
    final notifications = router()..pending = itemPayload('gazette-2510-20');
    await open(tester, router: notifications);

    await tester.runAsync(notifications.openPending);
    await tester.pumpAndSettle();
    expect(find.byType(ItemPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(notifications.openPending);
    await tester.pumpAndSettle();
    expect(find.byType(ItemPage), findsNothing);
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

  testWidgets('the menu opens Sources and About', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sources'));
    await settle(tester);
    expect(find.text('Read by GitHub'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Lanka Radar'), findsOneWidget);
    expect(find.text('Source code'), findsOneWidget);
  });

  testWidgets('the menu opens Alerts', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alerts'));
    await settle(tester);

    expect(find.byType(AlertsPage), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Prices'), findsOneWidget);
  });

  testWidgets('warns in the app bar when the workflow has gone quiet', (
    tester,
  ) async {
    remote.files['status.json'] =
        '{"schema": 1, "checked": "2026-01-01T00:00:00Z", "sources": {}}';

    await open(tester);

    expect(find.byTooltip('A source has gone quiet'), findsOneWidget);
  });
}

/// Lets the database and the fake branch answer, then the screen catch up.
Future<void> settle(WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}
