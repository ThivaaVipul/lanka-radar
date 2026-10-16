import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';

/// Records what would have been posted, instead of posting it.
class FakeNotifier implements Notifier {
  final shown = <List<FeedItem>>[];
  var permissionRequests = 0;
  var allowed = true;

  List<String> get shownIds => [
    for (final batch in shown)
      for (final item in batch) item.id,
  ];

  @override
  Future<void> showItems(List<FeedItem> items) async => shown.add(items);

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<bool> enabled() async => allowed;
}

AlertsRepository fakeAlerts(AppDatabase database, [FakeNotifier? notifier]) =>
    AlertsRepository(database: database, notifier: notifier ?? FakeNotifier());
