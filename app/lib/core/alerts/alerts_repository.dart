import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/database.dart';

/// The alert switches and the bookkeeping alerts need, kept in the settings
/// table: whether the app is in front (nothing alerts then) and whether the
/// notification permission has been asked for.
class AlertsRepository {
  AlertsRepository({required AppDatabase database, required this.notifier})
    : _db = database;

  static const _inFrontSince = 'app.inFrontSince';
  static const _asked = 'alerts.permissionAsked';

  /// A mark older than this is from an app that stopped while in front.
  static const inFrontFor = Duration(hours: 12);

  final AppDatabase _db;
  final Notifier notifier;

  /// The switches that are on.
  Future<Set<AlertSwitch>> switchesOn() async => {
    for (final alert in AlertSwitch.values)
      if (await _isOn(alert)) alert,
  };

  Future<void> setSwitch(AlertSwitch alert, {required bool on}) =>
      _db.saveSetting(alert.key, on ? 'on' : 'off');

  Future<void> appShown(DateTime now) =>
      _db.saveSetting(_inFrontSince, now.toIso8601String());

  Future<void> appHidden() => _db.deleteSetting(_inFrontSince);

  /// Whether the app is on screen: a background sync then posts nothing.
  Future<bool> appInFront(DateTime now) async {
    final since = await _db.setting(_inFrontSince);
    return since != null && now.difference(DateTime.parse(since)) < inFrontFor;
  }

  /// Asks for the notification permission the first time it is called, and
  /// never again.
  Future<void> askPermissionOnce() async {
    if (await _db.setting(_asked) != null) {
      return;
    }
    await _db.saveSetting(_asked, 'yes');
    await notifier.requestPermission();
  }

  Future<bool> _isOn(AlertSwitch alert) async {
    final value = await _db.setting(alert.key);
    return value == null ? alert.on : value == 'on';
  }
}
