import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/weekly_alerts.dart';
import 'package:lanka_radar/core/data/feed_item.dart';

import '../../helpers/fake_branch.dart';

FeedItem weekly(String id, String week, {String topic = 'jobs'}) =>
    FeedItem.fromJson(notice(id, week, topic: topic));

void main() {
  final now = DateTime(2026, 10, 14, 9);
  final on = {
    for (final alert in AlertSwitch.values)
      if (alert.on) alert,
  };

  test('one alert per gazette counts its vacancies and exams', () {
    final alerts = weeklyAlerts(
      [
        weekly('weekly-2510-a', '2026-10-09'),
        weekly('weekly-2510-b', '2026-10-09'),
        weekly('weekly-2510-c', '2026-10-09', topic: 'exams'),
        weekly('weekly-2509-a', '2026-10-02', topic: 'exams'),
        FeedItem.fromJson(item('gazette-2510-20', '2026-10-12')),
      ],
      on: on,
      now: now,
    );

    expect(alerts, [
      WeeklyAlert(week: DateTime(2026, 10, 2), vacancies: 0, exams: 1),
      WeeklyAlert(week: DateTime(2026, 10, 9), vacancies: 2, exams: 1),
    ]);
    expect(alerts.last.title, 'Gazette of 9 Oct 2026');
    expect(alerts.last.body, '2 vacancies, 1 exam');
    expect(alerts.first.body, '1 exam');
  });

  test('a switch turned off leaves its notices out, and old gazettes say '
      'nothing', () {
    final alerts = weeklyAlerts(
      [
        weekly('weekly-2510-a', '2026-10-09'),
        weekly('weekly-2510-c', '2026-10-09', topic: 'exams'),
        weekly('weekly-2505-a', '2026-09-04'),
      ],
      on: on.difference({AlertSwitch.jobs}),
      now: now,
    );

    expect(alerts, [
      WeeklyAlert(week: DateTime(2026, 10, 9), vacancies: 0, exams: 1),
    ]);
  });

  test('a payload names its gazette', () {
    final payload = weeklyPayload(DateTime(2026, 10, 9));

    expect(payload, 'weekly:2026-10-09');
    expect(weekFrom(payload), DateTime(2026, 10, 9));
    expect(weekFrom('item:weekly-2510-a'), isNull);
    expect(weekFrom(null), isNull);
  });
}
