import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/app.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';

import '../helpers/fake_branch.dart';

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
    await tester.pumpWidget(LankaRadarApp(feed: feed));
    // The database and the fake branch answer on the next turns of the loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the feed after the first refresh', (tester) async {
    remote.putMonth('2026-10', [
      item('gazette-2510-20', '2026-10-12', headline: 'Filling of a Vacancy'),
    ]);

    await open(tester);

    expect(find.text('Lanka Radar'), findsOneWidget);
    expect(find.text('Filling of a Vacancy'), findsOneWidget);
    expect(find.text('Election Commission, 12 Oct 2026'), findsOneWidget);
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
