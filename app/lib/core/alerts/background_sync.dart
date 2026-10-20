import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/alerts/fuel_alerts.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/home_screen_widget.dart';

/// One background run: the same refresh as opening the app, then a
/// notification for each item stored for the first time that should alert,
/// and one for a change in CEYPETCO's fuel prices. Nothing alerts for a fresh
/// install's history or while the app is in front, and what is found in quiet
/// hours goes out with the first run after them. Holiday reminders are
/// scheduled again from the holidays just read, and the home-screen widget
/// shows the numbers just read.
class BackgroundSync {
  BackgroundSync({
    required this._feed,
    required this._phone,
    required this._alerts,
    required this._homeWidget,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final FeedRepository _feed;
  final NowRepository _phone;
  final AlertsRepository _alerts;
  final HomeScreenWidget _homeWidget;
  final DateTime Function() _now;

  Future<void> run() async {
    final start = _now();
    // Recorded first, so the Alerts screen shows that Android ran it even when
    // the refresh fails.
    await _alerts.syncRan(start);
    final hadFeed = await _feed.lastRefresh() != null;
    final fuelBefore = await _phone.fuelRows();
    // The phone's own sources record their failures; the feed's throw, so
    // WorkManager tries again later.
    await _phone.refresh();
    await _feed.refresh();
    await _feed.updatePhoneItems();
    try {
      await _alerts.remindHolidays(await _phone.upcomingHolidays(), now: start);
    } on Exception {
      // Reminders that can't be scheduled now are scheduled on the next run;
      // they mustn't stop the alerts.
    }
    try {
      await _homeWidget.show(await _phone.load(await _feed.watchItems().first));
    } on Exception {
      // The widget catches up on the next run.
    }
    if (!hadFeed || await _alerts.appInFront(start)) {
      return;
    }
    final on = await _alerts.switchesOn();
    final fuelNow = await _phone.fuelRows();
    final fuel = on.contains(AlertSwitch.prices)
        ? fuelChanges(fuelBefore, fuelNow)
        : null;
    final fresh = [
      for (final item in itemsToAlert(
        await _feed.itemsSeenSince(start),
        on: on,
        now: start,
      ))
        if (!fuelPricesKnown(item, fuelNow)) item,
    ];
    if ((await _alerts.quietHours()).holds(start)) {
      await _alerts.hold([for (final item in fresh) item.id]);
      if (fuel != null) {
        await _alerts.holdFuel(fuel);
      }
      return;
    }
    // What quiet hours held goes out only if its switch is still on.
    final held = itemsToAlert(
      await _feed.items(await _alerts.held()),
      on: on,
      now: start,
    );
    final heldFuel = on.contains(AlertSwitch.prices)
        ? await _alerts.heldFuel()
        : null;
    await _alerts.clearHeld();
    final changes = fuel ?? heldFuel;
    if (changes != null) {
      await _alerts.notifier.showFuelChange(changes);
    }
    final all = [...held, ...fresh];
    if (all.isNotEmpty) {
      await _alerts.notifier.showItems(all);
    }
  }
}
