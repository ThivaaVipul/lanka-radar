import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/alerts/power_alerts.dart';
import 'package:lanka_radar/core/alerts/quiet_hours.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';

import '../../helpers/fake_sources.dart';

void main() {
  final now = DateTime(2026, 10, 20, 12);
  final slots = parseSchedule(fixture('edlcare_load_shedding.json'));
  // Group V: today 19:30 to 20:30, tomorrow 16:30 to 17:30.
  final tonight = slots[1];
  final tomorrow = slots[2];
  const family = Place(
    id: 'family',
    name: 'Family',
    area: gampaha,
    point: (lat: 7.09, lon: 79.99),
  );
  final breakdown = outagesAt(
    parseOutages(fixture('edlcare_outages_49.json')),
    gampahaHome,
  );

  PowerNow power({
    List<Outage> cuts = const [],
    List<PlannedCut> ahead = const [],
    bool both = false,
  }) => PowerNow(
    places: [
      PlaceCuts(place: home, outages: cuts, ahead: ahead),
      if (both) PlaceCuts(place: family, ahead: ahead),
    ],
  );

  group('alerts', () {
    test('load shedding first seen comes in one alert for its places', () {
      final alerts = powerAlerts(
        power(ahead: [tonight, tomorrow], both: true),
        const {},
        now: now,
      );

      expect(alerts.single.title, 'Load shedding at Home and Family');
      expect(
        alerts.single.body,
        'Today 19:30 to 20:30, Tomorrow 16:30 to 17:30',
      );
    });

    test('what was seen does not alert again', () {
      final seen = power(ahead: [tonight]);

      expect(powerAlerts(seen, powerKeys(seen), now: now), isEmpty);
      final more = power(ahead: [tonight, tomorrow]);
      expect(
        powerAlerts(more, powerKeys(seen), now: now).single.body,
        'Tomorrow 16:30 to 17:30',
      );
    });

    test('a cut on now at a place alerts with what it is', () {
      final alert = powerAlerts(
        power(cuts: breakdown),
        const {},
        now: now,
      ).single;

      expect(alert.title, 'Power cut at Home');
      expect(alert.body, 'A breakdown since 09:24');
    });

    test('load shedding that starts does not alert as a power cut', () {
      final before = power(ahead: [tonight]);
      final started = power(cuts: [tonight.asOutage]);

      expect(powerAlerts(started, powerKeys(before), now: now), isEmpty);
    });
  });

  group('reminders', () {
    const quiet = QuietHours();

    test('go out 30 minutes before, for the places the slot is at', () {
      final reminders = cutReminders(
        power(ahead: [tonight, tomorrow], both: true),
        now: now,
        quiet: quiet,
      );

      expect(
        [for (final reminder in reminders) reminder.at],
        [DateTime(2026, 10, 20, 19), DateTime(2026, 10, 21, 16)],
      );
      expect(
        reminders.first.title,
        'Load shedding at Home and Family at 19:30',
      );
      expect(reminders.first.body, 'Until 20:30');
    });

    test('none once that time has passed, or in quiet hours', () {
      expect(
        cutReminders(
          power(ahead: [tonight]),
          now: DateTime(2026, 10, 20, 19, 5),
          quiet: quiet,
        ),
        isEmpty,
      );
      expect(
        cutReminders(
          power(ahead: [tonight]),
          now: now,
          quiet: const QuietHours(start: 18 * 60, end: 6 * 60),
        ),
        isEmpty,
      );
    });
  });
}
