import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lanka_radar/core/alerts/holiday_reminders.dart';
import 'package:lanka_radar/core/alerts/power_alerts.dart';
import 'package:lanka_radar/core/alerts/weekly_alerts.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/card_lines.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:timezone/data/latest_10y.dart' as time_zones;
import 'package:timezone/timezone.dart' as tz;

/// Posts the app's notifications.
abstract interface class Notifier {
  /// One notification per item, stacked under the app; tapping one opens it.
  Future<void> showItems(List<FeedItem> items);

  /// One notification for each weekly gazette's vacancies and examinations.
  Future<void> showWeekly(List<WeeklyAlert> alerts);

  /// A change in CEYPETCO's fuel prices; a later change replaces it, and
  /// tapping it opens the fuel prices.
  Future<void> showFuelChange(String changes);

  /// Replaces the scheduled holiday reminders with [reminders]; tapping one
  /// opens the holidays.
  Future<void> scheduleHolidays(List<HolidayReminder> reminders);

  /// Power cuts at the places watched and load shedding first seen; a later
  /// one about the same replaces it, and tapping one opens Power.
  Future<void> showPowerAlerts(List<PowerAlert> alerts);

  /// Replaces the scheduled load shedding reminders with [reminders]; tapping
  /// one opens Power.
  Future<void> scheduleCutReminders(List<CutReminder> reminders);

  /// Asks Android (13 and later) to let the app post notifications.
  Future<void> requestPermission();

  /// Whether Android lets the app post notifications.
  Future<bool> enabled();
}

/// The payloads of the fuel, holiday and power cut notifications.
const fuelPayload = 'fuel';
const holidaysPayload = 'holidays';
const powerPayload = 'power';

/// The payload a tapped item notification carries.
String itemPayload(String id) => 'item:$id';

/// The item a notification's payload names, if it names one.
String? itemIdFrom(String? payload) =>
    payload != null && payload.startsWith('item:')
    ? payload.substring('item:'.length)
    : null;

/// What an item's notification says under its headline: its first key numbers
/// (a Litro list's for its district), or the topic and who published it.
String notificationBody(FeedItem item) {
  final district = item.source == 'gas' ? item.data['district'] : null;
  final numbers = [
    for (final number in item.keyNumbers.take(3))
      [
        shortLabel(number.label),
        amount(number.value),
        if (number.previous != null) '(was ${amount(number.previous!)})',
      ].join(' '),
  ];
  if (numbers.isEmpty) {
    return itemMeta(item);
  }
  return [if (district is String) '$district:', numbers.join(', ')].join(' ');
}

/// What an item's notification shows pulled down, under who published it: the
/// whole headline, which the title cuts to a line, then its key numbers.
String notificationText(FeedItem item) => item.keyNumbers.isEmpty
    ? displayHeadline(item)
    : '${displayHeadline(item)}\n${notificationBody(item)}';

/// A notification ID that stays the same for an item or a reminder (FNV-1a over
/// its ID), so posting it again replaces it instead of adding another. 0 and 1
/// are kept for the items' summary and the fuel change.
int notificationId(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash < 2 ? hash + 2 : hash;
}

class LocalNotifier implements Notifier {
  LocalNotifier(this._plugin);

  static const _group = 'app.lankaradar.items';
  static const _channel = 'items';
  static const _channelName = 'New items';
  static const _channelText =
      'New gazettes, prices, exam notices, jobs and rates';

  /// The summary that stacks the item notifications.
  static const _summaryId = 0;
  static const _fuelId = 1;

  static const _fuel = AndroidNotificationDetails(
    'fuel',
    'Fuel prices',
    channelDescription: "Changes in CEYPETCO's fuel prices",
  );
  static const _holidays = AndroidNotificationDetails(
    'holidays',
    'Holiday reminders',
    channelDescription: 'The evening before each public holiday',
  );
  static const _power = AndroidNotificationDetails(
    'power',
    'Power cuts',
    channelDescription: 'Power cuts and load shedding at your places',
  );

  /// Holiday reminders keep Sri Lanka's time, whatever the phone is set to.
  static final tz.Location _sriLanka = () {
    time_zones.initializeTimeZones();
    return tz.getLocation('Asia/Colombo');
  }();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Sets the plugin up; [onTap] gets the payload of a notification tapped
  /// while the app is running.
  static Future<LocalNotifier> start({
    void Function(String? payload)? onTap,
  }) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        // White on transparent, as Android's status bar needs.
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
      onDidReceiveNotificationResponse: onTap == null
          ? null
          : (response) => onTap(response.payload),
    );
    return LocalNotifier(plugin);
  }

  /// The payload of the notification that started the app, if one did.
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return (details?.didNotificationLaunchApp ?? false)
        ? details?.notificationResponse?.payload
        : null;
  }

  @override
  Future<void> showItems(List<FeedItem> items) async {
    for (final item in items) {
      final body = notificationBody(item);
      await _plugin.show(
        id: notificationId(item.id),
        title: cardTitle(item),
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel,
            _channelName,
            channelDescription: _channelText,
            groupKey: _group,
            styleInformation: BigTextStyleInformation(
              notificationText(item),
              contentTitle: itemMeta(item),
            ),
          ),
        ),
        payload: itemPayload(item.id),
      );
    }
    if (items.length > 1) {
      await _plugin.show(
        id: _summaryId,
        title: 'Lanka Radar',
        body: '${items.length} new',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channel,
            _channelName,
            channelDescription: _channelText,
            groupKey: _group,
            setAsGroupSummary: true,
          ),
        ),
      );
    }
  }

  @override
  Future<void> showWeekly(List<WeeklyAlert> alerts) async {
    for (final alert in alerts) {
      await _plugin.show(
        id: notificationId(weeklyPayload(alert.week)),
        title: alert.title,
        body: alert.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channel,
            _channelName,
            channelDescription: _channelText,
            groupKey: _group,
          ),
        ),
        payload: weeklyPayload(alert.week),
      );
    }
  }

  @override
  Future<void> showFuelChange(String changes) => _plugin.show(
    id: _fuelId,
    title: 'Fuel prices changed',
    body: changes,
    notificationDetails: NotificationDetails(
      android: _withText(_fuel, changes),
    ),
    payload: fuelPayload,
  );

  @override
  Future<void> scheduleHolidays(List<HolidayReminder> reminders) async {
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.payload == holidaysPayload) {
        await _plugin.cancel(id: pending.id);
      }
    }
    for (final reminder in reminders) {
      final at = reminder.at;
      await _plugin.zonedSchedule(
        id: notificationId(reminder.key),
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime(
          _sriLanka,
          at.year,
          at.month,
          at.day,
          at.hour,
        ),
        notificationDetails: NotificationDetails(
          android: _withText(_holidays, reminder.body),
        ),
        // Inexact, so no exact-alarm permission: Android may wait a little.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: holidaysPayload,
      );
    }
  }

  @override
  Future<void> showPowerAlerts(List<PowerAlert> alerts) async {
    for (final alert in alerts) {
      await _plugin.show(
        id: notificationId(alert.key),
        title: alert.title,
        body: alert.body,
        notificationDetails: NotificationDetails(
          android: _withText(_power, alert.body),
        ),
        payload: powerPayload,
      );
    }
  }

  @override
  Future<void> scheduleCutReminders(List<CutReminder> reminders) async {
    // Only scheduled ones are pending, so posted alerts stay.
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.payload == powerPayload) {
        await _plugin.cancel(id: pending.id);
      }
    }
    // Exact, so a reminder 30 minutes before isn't up to an hour late;
    // inexact where Android doesn't allow exact alarms.
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    for (final reminder in reminders) {
      final at = reminder.at;
      await _plugin.zonedSchedule(
        id: notificationId(reminder.key),
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime(
          _sriLanka,
          at.year,
          at.month,
          at.day,
          at.hour,
          at.minute,
        ),
        notificationDetails: NotificationDetails(
          android: _withText(_power, reminder.body),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: powerPayload,
      );
    }
  }

  @override
  Future<void> requestPermission() async {
    await _android?.requestNotificationsPermission();
  }

  @override
  Future<bool> enabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  /// [channel] with [text] shown in full when the notification is pulled down.
  static AndroidNotificationDetails _withText(
    AndroidNotificationDetails channel,
    String text,
  ) => AndroidNotificationDetails(
    channel.channelId,
    channel.channelName,
    channelDescription: channel.channelDescription,
    styleInformation: BigTextStyleInformation(text),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
}
