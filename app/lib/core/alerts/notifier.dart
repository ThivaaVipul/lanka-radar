import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';

/// Posts the app's notifications.
abstract interface class Notifier {
  /// One notification per item, stacked under the app; tapping one opens it.
  Future<void> showItems(List<FeedItem> items);

  /// Asks Android (13 and later) to let the app post notifications.
  Future<void> requestPermission();

  /// Whether Android lets the app post notifications.
  Future<bool> enabled();
}

/// The payload a tapped item notification carries.
String itemPayload(String id) => 'item:$id';

/// The item a notification's payload names, if it names one.
String? itemIdFrom(String? payload) =>
    payload != null && payload.startsWith('item:')
    ? payload.substring('item:'.length)
    : null;

/// What an item's notification says under its headline: its first key numbers,
/// or the topic and who published it.
String notificationBody(FeedItem item) {
  final numbers = [
    for (final number in item.keyNumbers.take(3))
      [
        shortLabel(number.label),
        amount(number.value),
        if (number.previous != null) '(was ${amount(number.previous!)})',
      ].join(' '),
  ];
  return numbers.isEmpty ? itemMeta(item) : numbers.join(', ');
}

/// What an item's notification shows pulled down, under who published it: the
/// whole headline, which the title cuts to a line, then its key numbers.
String notificationText(FeedItem item) => item.keyNumbers.isEmpty
    ? displayHeadline(item)
    : '${displayHeadline(item)}\n${notificationBody(item)}';

/// A notification ID that stays the same for an item (FNV-1a over its ID), so
/// posting it again replaces it instead of adding another.
int notificationId(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

class LocalNotifier implements Notifier {
  LocalNotifier(this._plugin);

  static const _group = 'app.lankaradar.items';
  static const _channel = 'items';
  static const _channelName = 'New items';
  static const _channelText = 'New gazettes, prices, exam notices and rates';

  /// The summary that stacks the item notifications; items never use ID 0.
  static const _summaryId = 0;

  final FlutterLocalNotificationsPlugin _plugin;

  /// Sets the plugin up; [onTap] gets the payload of a notification tapped
  /// while the app is running.
  static Future<LocalNotifier> start({
    void Function(String? payload)? onTap,
  }) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
        title: displayHeadline(item),
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
  Future<void> requestPermission() async {
    await _android?.requestNotificationsPermission();
  }

  @override
  Future<bool> enabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
}
