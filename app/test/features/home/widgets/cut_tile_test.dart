import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/features/home/widgets/cut_tile.dart';

void main() {
  Future<void> show(WidgetTester tester, CutTile tile) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: tile)));
    await tester.pump();
  }

  testWidgets('a cut to come says how long until it starts', (tester) async {
    final start = DateTime.now().add(const Duration(hours: 3, minutes: 58));
    await show(
      tester,
      CutTile(
        title: 'Load shedding at Home',
        time: '19:30',
        rest: 'to 20:30',
        start: start.add(const Duration(seconds: 30)),
        end: start.add(const Duration(hours: 1)),
      ),
    );

    expect(find.text('Load shedding at Home'), findsOneWidget);
    expect(find.text('in 3 h 58 m'), findsOneWidget);
    expect(find.text('19:30  to 20:30'), findsOneWidget);
  });

  testWidgets("tomorrow's cut says tomorrow", (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1, 16, 30);
    await show(
      tester,
      CutTile(
        title: 'Load shedding at Home',
        time: '16:30',
        start: start,
        end: start.add(const Duration(hours: 1)),
      ),
    );

    expect(find.text('tomorrow'), findsOneWidget);
  });

  testWidgets('a cut on now says how long is left', (tester) async {
    final now = DateTime.now();
    await show(
      tester,
      CutTile(
        on: true,
        title: 'Load shedding at Home',
        time: '19:30',
        start: now.subtract(const Duration(minutes: 15)),
        end: now.add(const Duration(minutes: 45, seconds: 30)),
      ),
    );

    expect(find.text('ends in 45 m'), findsOneWidget);
  });

  testWidgets('a breakdown has no end, so no countdown or line', (
    tester,
  ) async {
    await show(
      tester,
      const CutTile(on: true, title: 'Power cut at Home', time: 'since 09:24'),
    );

    expect(find.text('since 09:24'), findsOneWidget);
    expect(find.textContaining('ends in'), findsNothing);
  });
}
