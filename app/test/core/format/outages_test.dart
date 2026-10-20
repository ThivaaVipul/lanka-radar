import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/outages.dart';

void main() {
  final now = DateTime(2026, 10, 20, 12);

  PlannedCut cut(DateTime start, DateTime end) =>
      PlannedCut(id: '1', start: start, end: end);

  test('a cut to come says its day and hours', () {
    final tonight = cut(
      DateTime(2026, 10, 20, 19, 30),
      DateTime(2026, 10, 20, 20, 30),
    );

    expect(cutDay(tonight, now: now), 'Today');
    expect(cutHours(tonight), '19:30 to 20:30');
    expect(cutTimes(tonight, now: now), 'Today 19:30 to 20:30');
    expect(
      cutDay(
        cut(DateTime(2026, 10, 21, 16, 30), DateTime(2026, 10, 21, 17, 30)),
        now: now,
      ),
      'Tomorrow',
    );
    expect(
      cutTimes(
        cut(DateTime(2026, 10, 25, 9), DateTime(2026, 10, 25, 17)),
        now: now,
      ),
      'Sun 25 Oct 09:00 to 17:00',
    );
  });

  test('a cut across midnight starts on its day', () {
    expect(
      cutTimes(
        cut(DateTime(2026, 10, 20, 22), DateTime(2026, 10, 21, 2)),
        now: now,
      ),
      'Today 22:00 to 02:00',
    );
  });
}
