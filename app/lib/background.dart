import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/alerts/background_sync.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/data_branch.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:workmanager/workmanager.dart';

const _syncTask = 'lanka-radar-sync';

/// How often Android runs the background sync, roughly: it may wait longer to
/// save battery, especially on Xiaomi phones.
const syncEvery = Duration(hours: 3);

/// WorkManager's entry point: runs in its own Flutter engine, so it opens its
/// own database connection and notification plugin.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    final database = AppDatabase();
    try {
      final notifier = await LocalNotifier.start();
      await BackgroundSync(
        feed: FeedRepository(database: database, remote: DataBranch()),
        phone: NowRepository(
          database: database,
          ceypetco: Ceypetco(),
          cbsl: Cbsl(),
        ),
        alerts: AlertsRepository(database: database, notifier: notifier),
      ).run();
      return true;
    } on Exception {
      return false;
    } finally {
      await database.close();
    }
  });
}

/// Starts the background sync on any network; a schedule already there is
/// kept, so opening the app doesn't push the next run back. The first run
/// waits a full period, as opening the app has just refreshed.
Future<void> scheduleBackgroundSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _syncTask,
    _syncTask,
    frequency: syncEvery,
    initialDelay: syncEvery,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
