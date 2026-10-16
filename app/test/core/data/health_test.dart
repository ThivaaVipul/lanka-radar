import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/health.dart';

final now = DateTime(2026, 10, 16, 15);

String statusJson({
  String checked = '2026-10-16T09:09:23Z',
  String? gazettes,
}) => jsonEncode({
  'schema': 1,
  'checked': checked,
  'sources': {
    'holidays': {
      'lastRun': checked,
      'lastSuccess': checked,
      'lastError': null,
      'failures': 0,
    },
    'gazettes': {
      'lastRun': checked,
      'lastSuccess': gazettes ?? checked,
      'lastError': gazettes == null ? null : 'ReadTimeout: timed out',
      'failures': gazettes == null ? 0 : 3,
    },
  },
});

void main() {
  test("reads the workflow's status in the app's order, in local time", () {
    final status = parseWorkflowStatus(statusJson());

    expect(status.ran, DateTime.utc(2026, 10, 16, 9, 9, 23).toLocal());
    expect(
      [for (final source in status.sources) source.name],
      ['Gazettes', 'Holidays'],
    );
    expect(parseWorkflowStatus(null).sources, isEmpty);
  });

  test('a source is stale after a day without success, once it has run', () {
    final fresh = SourceHealth(
      name: 'Fuel prices',
      lastRun: now,
      lastSuccess: now.subtract(const Duration(hours: 20)),
    );
    final stale = SourceHealth(
      name: 'Fuel prices',
      lastRun: now,
      lastSuccess: now.subtract(const Duration(hours: 30)),
    );
    final never = SourceHealth(name: 'USD/LKR', lastRun: now);
    const untried = SourceHealth(name: 'USD/LKR');

    expect(fresh.isStale(now), isFalse);
    expect(stale.isStale(now), isTrue);
    expect(never.isStale(now), isTrue);
    expect(untried.isStale(now), isFalse);
  });

  test('needs a look when the workflow or any source has gone quiet', () {
    final quiet = parseWorkflowStatus(
      statusJson(gazettes: '2026-10-14T09:00:00Z'),
    );
    final old = parseWorkflowStatus(
      statusJson(checked: '2026-10-14T09:00:00Z'),
    );
    final fine = parseWorkflowStatus(statusJson());

    expect(
      Health(workflowRan: fine.ran, github: fine.sources).needsALook(now),
      isFalse,
    );
    expect(
      Health(workflowRan: quiet.ran, github: quiet.sources).needsALook(now),
      isTrue,
    );
    expect(Health(workflowRan: old.ran).needsALook(now), isTrue);
  });
}
