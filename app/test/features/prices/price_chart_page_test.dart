import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/features/prices/cubit/price_chart_cubit.dart';
import 'package:lanka_radar/features/prices/view/price_chart_page.dart';
import 'package:lanka_radar/features/prices/widgets/price_chart.dart';

import '../../helpers/fake_branch.dart';
import '../../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeBranch remote;
  late FeedRepository feed;
  late NowRepository phone;

  setUp(() {
    database = memoryDatabase();
    remote = FakeBranch()
      ..putMonth('2026-08', [
        {
          ...item('gazette-2501-55', '2026-08-31', topic: 'prices'),
          'keyNumbers': [
            {
              'label': 'Lanka Petrol 92 Octane',
              'value': 399,
              'unit': 'LKR',
              'previous': 414,
            },
          ],
        },
      ]);
    feed = FeedRepository(database: database, remote: remote.branch);
    phone = FakeSources().repository(database);
  });

  tearDown(() => database.close());

  Future<void> show(WidgetTester tester, ChartSubject subject) async {
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
          home: PriceChartPage(subject: subject),
        ),
      ),
    );
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  testWidgets("a fuel's chart has its price now and each change", (
    tester,
  ) async {
    await show(tester, const FuelChart('Petrol 92'));

    expect(find.byType(PriceChart), findsOneWidget);
    expect(find.text('CEYPETCO and fuel price gazettes'), findsOneWidget);
    expect(find.text('414'), findsWidgets);
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('399'), findsOneWidget);
  });

  testWidgets('the rate chart offers ranges and its high and low', (
    tester,
  ) async {
    await show(tester, const RateChart());

    expect(find.text('1M'), findsOneWidget);
    expect(find.text('Since Jan'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);

    await tester.tap(find.text('1M'));
    await tester.pumpAndSettle();
    expect(find.byType(PriceChart), findsOneWidget);
  });

  testWidgets("a market good's chart compares its markets", (tester) async {
    remote.files[FeedRepository.marketPath] = marketDataset;
    await show(tester, const MarketChart('Beans'));

    expect(find.text('Narahenpita${dot}per kg'), findsOneWidget);
    expect(find.text('700'), findsWidgets);
    final dambulla = find.text('Dambulla');
    await tester.ensureVisible(dambulla);
    await tester.pumpAndSettle();
    expect(find.text('Markets'), findsOneWidget);

    await tester.tap(dambulla);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('Dambulla${dot}per kg'), findsOneWidget);
    expect(find.text('430'), findsWidgets);
  });

  test('value lines fall on round numbers', () {
    final (prices, priceStep) = valueTicks(290, 440);
    expect(prices, [300, 350, 400]);
    expect(priceStep, 50);
    final (rates, rateStep) = valueTicks(330.4, 331.6);
    expect(rates, [330.5, 331, 331.5]);
    expect(rateStep, 0.5);
  });

  testWidgets('touching the chart reads out a point', (tester) async {
    await show(tester, const RateChart());

    final chart = tester.getRect(find.byType(PriceChart));
    final gesture = await tester.startGesture(chart.center);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pump();
  });
}
