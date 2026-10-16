import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/system_settings.dart';
import 'package:lanka_radar/features/alerts/view/alerts_page.dart';

import '../../helpers/fake_branch.dart';
import '../../helpers/fake_notifier.dart';

/// Records which of the app's settings pages would have opened.
class FakeSystemSettings implements SystemSettings {
  final opened = <String>[];

  @override
  Future<void> openApp() async => opened.add('app');

  @override
  Future<void> openNotifications() async => opened.add('notifications');
}

void main() {
  late AppDatabase database;
  late FakeNotifier notifier;
  late AlertsRepository alerts;
  late FakeSystemSettings settings;

  setUp(() {
    database = memoryDatabase();
    notifier = FakeNotifier();
    alerts = fakeAlerts(database, notifier);
    settings = FakeSystemSettings();
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: alerts,
        child: MaterialApp(
          theme: AppTheme.light,
          home: AlertsPage(settings: settings),
        ),
      ),
    );
    await settle(tester);
  }

  bool switchOn(WidgetTester tester, String label) => tester
      .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, label))
      .value;

  testWidgets('shows the switches as they start, and keeps a change', (
    tester,
  ) async {
    await open(tester);

    expect(switchOn(tester, 'Prices'), isTrue);
    expect(switchOn(tester, 'Wages and labour'), isTrue);
    expect(switchOn(tester, 'Elections'), isFalse);
    expect(find.text('Notifications are off'), findsNothing);

    await tester.tap(find.text('Elections'));
    await settle(tester);

    expect(switchOn(tester, 'Elections'), isTrue);
    expect(
      await tester.runAsync(alerts.switchesOn),
      contains(AlertSwitch.elections),
    );
  });

  testWidgets('quiet hours run 22:00 to 06:00 and can be turned off', (
    tester,
  ) async {
    await open(tester);

    expect(switchOn(tester, 'Hold alerts'), isTrue);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('06:00'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Hold alerts'), 100);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hold alerts'));
    await settle(tester);

    expect((await tester.runAsync(alerts.quietHours))!.on, isFalse);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Start')).enabled,
      isFalse,
    );
  });

  testWidgets('a time picked for the start of quiet hours is kept', (
    tester,
  ) async {
    await open(tester);

    await tester.scrollUntilVisible(find.text('Start'), 100);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '23');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(find.text('23:30'), findsOneWidget);
    expect((await tester.runAsync(alerts.quietHours))!.start, 23 * 60 + 30);
  });

  testWidgets('says when notifications are off, and opens their settings', (
    tester,
  ) async {
    notifier.allowed = false;
    await open(tester);

    await tester.tap(find.text('Notifications are off'));

    expect(settings.opened, ['notifications']);
  });

  testWidgets('the battery row shows the last sync and opens app info', (
    tester,
  ) async {
    await tester.runAsync(
      () => alerts.syncRan(DateTime.now().subtract(const Duration(hours: 1))),
    );
    await open(tester);

    await tester.scrollUntilVisible(find.text('Battery'), 100);
    await tester.pumpAndSettle();
    expect(find.textContaining('Last sync'), findsOneWidget);

    await tester.tap(find.text('Battery'));

    expect(settings.opened, ['app']);
  });

  testWidgets('before any background sync, the battery row says so', (
    tester,
  ) async {
    await open(tester);

    await tester.scrollUntilVisible(find.text('Battery'), 100);
    await tester.pumpAndSettle();
    expect(find.text('No background sync yet'), findsOneWidget);
  });
}
