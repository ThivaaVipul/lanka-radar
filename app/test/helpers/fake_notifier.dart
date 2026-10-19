import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/alerts/holiday_reminders.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';

/// Records what would have been posted, instead of posting it.
class FakeNotifier implements Notifier {
  final shown = <List<FeedItem>>[];
  final fuelChanges = <String>[];
  var permissionRequests = 0;
  var allowed = true;

  /// The holiday reminders scheduled now.
  var reminders = <HolidayReminder>[];

  List<String> get shownIds => [
    for (final batch in shown)
      for (final item in batch) item.id,
  ];

  @override
  Future<void> showItems(List<FeedItem> items) async => shown.add(items);

  @override
  Future<void> showFuelChange(String changes) async => fuelChanges.add(changes);

  @override
  Future<void> scheduleHolidays(List<HolidayReminder> reminders) async =>
      this.reminders = reminders;

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<bool> enabled() async => allowed;
}

AlertsRepository fakeAlerts(AppDatabase database, [FakeNotifier? notifier]) =>
    AlertsRepository(database: database, notifier: notifier ?? FakeNotifier());
