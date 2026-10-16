import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';

/// One background run: the same refresh as opening the app, then a
/// notification for each item stored for the first time that should alert.
/// Nothing alerts for a fresh install's history or while the app is in front,
/// and what is found in quiet hours goes out with the first run after them.
class BackgroundSync {
  BackgroundSync({
    required this._feed,
    required this._phone,
    required this._alerts,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final FeedRepository _feed;
  final NowRepository _phone;
  final AlertsRepository _alerts;
  final DateTime Function() _now;

  Future<void> run() async {
    final start = _now();
    // Recorded first, so the Alerts screen shows that Android ran it even when
    // the refresh fails.
    await _alerts.syncRan(start);
    final hadFeed = await _feed.lastRefresh() != null;
    // The phone's own sources record their failures; the feed's throw, so
    // WorkManager tries again later.
    await _phone.refresh();
    await _feed.refresh();
    if (!hadFeed || await _alerts.appInFront(start)) {
      return;
    }
    final on = await _alerts.switchesOn();
    final fresh = itemsToAlert(
      await _feed.itemsSeenSince(start),
      on: on,
      now: start,
    );
    if ((await _alerts.quietHours()).holds(start)) {
      await _alerts.hold([for (final item in fresh) item.id]);
      return;
    }
    // Held items go out only if their switch is still on.
    final held = itemsToAlert(
      await _feed.items(await _alerts.held()),
      on: on,
      now: start,
    );
    await _alerts.clearHeld();
    final all = [...held, ...fresh];
    if (all.isNotEmpty) {
      await _alerts.notifier.showItems(all);
    }
  }
}
