import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/features/home/widgets/now_card.dart';

final today = DateTime.now();
final day = DateTime(today.year, today.month, today.day);

NowData data() => NowData(
  fuel: [
    FuelNow(name: 'Petrol 92', price: 414, since: day, was: 399),
    FuelNow(name: 'Petrol 95', price: 475, since: day),
    FuelNow(name: 'Diesel', price: 392, since: day),
  ],
  fuelAsOf: today,
  rates: [RateNow(day: day, rate: 331.286)],
  holidays: [
    HolidayNow(
      day: day.add(const Duration(days: 23)),
      name: 'Deepavali',
      tamil: 'TA Deepavali',
    ),
  ],
  gas: FeedItem(
    id: 'gas-litro',
    source: 'gas',
    topic: 'prices',
    headlineEn: 'Litro gas prices',
    published: day,
    links: const {'image': 'https://litro/list.webp'},
  ),
);

void main() {
  late List<Uri> opened;

  Future<void> show(WidgetTester tester) async {
    opened = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: NowCard(
              data: data(),
              open: (link) async {
                opened.add(link);
                return true;
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the fuel prices, the rate, the next holiday and LP gas', (
    tester,
  ) async {
    await show(tester);

    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Petrol 92'), findsOneWidget);
    expect(find.text('414'), findsOneWidget);
    expect(find.text('331.29'), findsOneWidget);
    expect(find.text('Deepavali'), findsOneWidget);
    expect(find.textContaining('List from'), findsOneWidget);
    expect(find.text('Exam timetable'), findsOneWidget);
    expect(find.text('Not yet'), findsOneWidget);
  });

  testWidgets('the fuel sheet has each price with the one before', (
    tester,
  ) async {
    await show(tester);

    await tester.tap(find.text('Fuel'));
    await tester.pumpAndSettle();

    expect(find.text('Fuel prices'), findsOneWidget);
    expect(find.text('was 399'), findsOneWidget);
    await tester.tap(find.text('CEYPETCO prices'));
    expect(opened.single.host, 'ceypetco.gov.lk');
  });

  testWidgets('the holiday sheet has the Tamil names', (tester) async {
    await show(tester);

    await tester.tap(find.text('Deepavali'));
    await tester.pumpAndSettle();

    expect(find.text('Holidays'), findsOneWidget);
    expect(find.text('TA Deepavali'), findsOneWidget);
  });

  testWidgets("LP gas opens Litro's price list", (tester) async {
    await show(tester);

    await tester.tap(find.textContaining('List from'));

    expect(opened, [Uri.parse('https://litro/list.webp')]);
  });

  test('the fuel note says when prices changed, or how old they are', () {
    final now = DateTime(2026, 10, 16, 9);
    final fresh = NowData(
      fuel: [
        FuelNow(name: 'Petrol 92', price: 414, since: DateTime(2026, 9, 30)),
      ],
      fuelAsOf: now.subtract(const Duration(hours: 2)),
    );
    final stale = NowData(
      fuel: fresh.fuel,
      fuelAsOf: DateTime(2026, 10, 14, 8),
    );

    expect(fuelNote(fresh, today: now), 'changed 30 Sep');
    expect(fuelNote(stale, today: now), 'as of 14 Oct');
  });
}
