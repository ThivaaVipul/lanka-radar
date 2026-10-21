import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// One notification for a weekly gazette's notices: how many vacancies and
/// examinations it brought. The notices don't alert one by one.
final class WeeklyAlert extends Equatable {
  const WeeklyAlert({
    required this.week,
    required this.vacancies,
    required this.exams,
  });

  /// The gazette's date, a Friday.
  final DateTime week;
  final int vacancies;
  final int exams;

  /// "Gazette of 9 Oct 2026".
  String get title => 'Gazette of ${shortDate(week)}';

  /// "6 vacancies, 3 exams".
  String get body => [
    if (vacancies > 0) '$vacancies ${vacancies == 1 ? 'vacancy' : 'vacancies'}',
    if (exams > 0) '$exams ${exams == 1 ? 'exam' : 'exams'}',
  ].join(', ');

  @override
  List<Object?> get props => [week, vacancies, exams];
}

/// The payload of a weekly gazette's notification: its date.
String weeklyPayload(DateTime week) => 'weekly:${isoDay(week)}';

/// The week a notification's payload names, if it names one.
DateTime? weekFrom(String? payload) =>
    payload != null && payload.startsWith('weekly:')
    ? DateTime.tryParse(payload.substring('weekly:'.length))
    : null;

/// The gazette a weekly notice came in.
DateTime weekOf(FeedItem item) => switch (item.data['week']) {
  final String day => DateTime.tryParse(day) ?? item.published,
  _ => item.published,
};

/// One alert per weekly gazette among [seen], counting the notices published
/// recently whose switch (Jobs or Exams) is on; oldest gazette first.
List<WeeklyAlert> weeklyAlerts(
  List<FeedItem> seen, {
  required Set<AlertSwitch> on,
  required DateTime now,
}) {
  final counts = <DateTime, (int, int)>{};
  for (final item in seen) {
    if (item.source != 'weekly' ||
        !item.published.isAfter(now.subtract(alertWithin)) ||
        !on.contains(switchFor(item))) {
      continue;
    }
    final (vacancies, exams) = counts[weekOf(item)] ?? (0, 0);
    counts[weekOf(item)] = item.topic == 'jobs'
        ? (vacancies + 1, exams)
        : (vacancies, exams + 1);
  }
  return [
    for (final MapEntry(key: week, value: (vacancies, exams)) in counts.entries)
      WeeklyAlert(week: week, vacancies: vacancies, exams: exams),
  ]..sort((a, b) => a.week.compareTo(b.week));
}
