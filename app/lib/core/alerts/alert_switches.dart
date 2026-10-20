import 'package:lanka_radar/core/data/feed_item.dart';

/// The alert switches, in the order the Alerts screen lists them, with what
/// each starts as. Election notices are most gazettes, so they start off.
enum AlertSwitch {
  prices('Prices', on: true),
  exams('Exams', on: true),
  jobs('Jobs', on: true),
  rates('USD/LKR moves', on: true),
  holidays('Holiday reminders', on: true),
  power('Power cuts', on: true),
  taxes('Taxes and imports', on: true),
  energy('Energy and utilities', on: true),
  labour('Wages and labour', on: true),
  elections('Elections', on: false);

  const AlertSwitch(this.label, {required this.on});

  final String label;

  /// Whether the switch starts on.
  final bool on;

  /// The key it is stored under in the settings table.
  String get key => 'alert.$name';
}

/// The Alerts screen's first switches: feed topics, holiday reminders and
/// power cuts at the places watched.
const topicSwitches = [
  AlertSwitch.prices,
  AlertSwitch.exams,
  AlertSwitch.jobs,
  AlertSwitch.rates,
  AlertSwitch.holidays,
  AlertSwitch.power,
];

/// The Alerts screen's switches for gazettes, by group.
const gazetteSwitches = [
  AlertSwitch.taxes,
  AlertSwitch.energy,
  AlertSwitch.labour,
  AlertSwitch.elections,
];

/// The switch an item's alert falls under: its topic, or for a gazette without
/// prices, its group. Null for items that never alert.
AlertSwitch? switchFor(FeedItem item) => switch (item.topic) {
  'prices' => AlertSwitch.prices,
  'exams' => AlertSwitch.exams,
  'jobs' => AlertSwitch.jobs,
  'rates' => AlertSwitch.rates,
  'gazettes' => switch (item.data['group']) {
    'prices-taxes' => AlertSwitch.taxes,
    'energy' => AlertSwitch.energy,
    'labour' => AlertSwitch.labour,
    'elections' => AlertSwitch.elections,
    _ => null,
  },
  _ => null,
};

/// How far back an item may have been published and still alert: history
/// filling in never does.
const alertWithin = Duration(days: 14);

/// The items to alert for among those a sync stored for the first time: marked
/// to alert, recent, and with their switch on.
List<FeedItem> itemsToAlert(
  List<FeedItem> seen, {
  required Set<AlertSwitch> on,
  required DateTime now,
}) => [
  for (final item in seen)
    if (item.alert &&
        item.published.isAfter(now.subtract(alertWithin)) &&
        on.contains(switchFor(item)))
      item,
];
