import 'dart:convert';

import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/alerts/quiet_hours.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// The alert switches, quiet hours, and the bookkeeping alerts need, kept in the
/// settings table: whether the app is in front (nothing alerts then), what quiet
/// hours are holding back, when the background sync last ran, and whether the
/// notification permission has been asked for.
class AlertsRepository {
  AlertsRepository({required AppDatabase database, required this.notifier})
    : _db = database;

  static const _inFrontSince = 'app.inFrontSince';
  static const _asked = 'alerts.permissionAsked';
  static const _held = 'alerts.held';
  static const _quietOn = 'quiet.on';
  static const _quietStart = 'quiet.start';
  static const _quietEnd = 'quiet.end';
  static const _lastSync = 'sync.lastRun';

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

  Future<QuietHours> quietHours() async {
    const start = QuietHours();
    return QuietHours(
      on: await _db.setting(_quietOn) != 'off',
      start: _minutes(await _db.setting(_quietStart)) ?? start.start,
      end: _minutes(await _db.setting(_quietEnd)) ?? start.end,
    );
  }

  Future<void> setQuietHours(QuietHours quiet) async {
    await _db.saveSetting(_quietOn, quiet.on ? 'on' : 'off');
    await _db.saveSetting(_quietStart, clock(quiet.start));
    await _db.saveSetting(_quietEnd, clock(quiet.end));
  }

  /// The IDs of the items quiet hours are holding back.
  Future<List<String>> held() async {
    final value = await _db.setting(_held);
    return value == null
        ? const []
        : [...(jsonDecode(value) as List<Object?>).whereType<String>()];
  }

  /// Holds [ids] back, with those held already, until quiet hours end.
  Future<void> hold(Iterable<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final all = {...await held(), ...ids};
    await _db.saveSetting(_held, jsonEncode(all.toList()));
  }

  Future<void> clearHeld() => _db.deleteSetting(_held);

  /// When the background sync last ran, if it ever has.
  Future<DateTime?> lastSync() async {
    final value = await _db.setting(_lastSync);
    return value == null ? null : DateTime.parse(value);
  }

  Future<void> syncRan(DateTime time) =>
      _db.saveSetting(_lastSync, time.toIso8601String());

  /// The app is on screen: background syncs post nothing, and what quiet hours
  /// held is on the feed, marked new, so it no longer alerts.
  Future<void> appShown(DateTime now) async {
    await _db.saveSetting(_inFrontSince, now.toIso8601String());
    await clearHeld();
  }

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

  /// Minutes after midnight from 22:00, as quiet hours are stored.
  static int? _minutes(String? value) {
    final parts = value?.split(':');
    if (parts == null || parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    return hour == null || minute == null ? null : hour * 60 + minute;
  }
}
