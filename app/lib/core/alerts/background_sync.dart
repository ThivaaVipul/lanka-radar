import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';

/// One background run: the same refresh as opening the app, then a
/// notification for each item stored for the first time that should alert.
/// Nothing alerts for a fresh install's history or while the app is in front.
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
    final hadFeed = await _feed.lastRefresh() != null;
    // The phone's own sources record their failures; the feed's throw, so
    // WorkManager tries again later.
    await _phone.refresh();
    await _feed.refresh();
    if (!hadFeed || await _alerts.appInFront(start)) {
      return;
    }
    final fresh = itemsToAlert(
      await _feed.itemsSeenSince(start),
      on: await _alerts.switchesOn(),
      now: start,
    );
    if (fresh.isNotEmpty) {
      await _alerts.notifier.showItems(fresh);
    }
  }
}
