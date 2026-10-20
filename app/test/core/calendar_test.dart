import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/calendar.dart';

void main() {
  test("an all-day event fills the calendar app's new-event screen", () {
    final intent = calendarIntent(
      CalendarEvent(
        title: 'O/L 2026',
        first: DateTime(2026, 12, 8),
        last: DateTime(2026, 12, 17),
        description: 'G.C.E. O/L 2026 timetable',
      ),
    );

    expect(intent.action, 'android.intent.action.INSERT');
    expect(intent.data, 'content://com.android.calendar/events');
    expect(intent.arguments, {
      'title': 'O/L 2026',
      'description': 'G.C.E. O/L 2026 timetable',
      'allDay': true,
      'beginTime': DateTime.utc(2026, 12, 8).millisecondsSinceEpoch,
      'endTime': DateTime.utc(2026, 12, 18).millisecondsSinceEpoch,
    });
  });

  test('a timed event, such as a power cut, keeps its times', () {
    final start = DateTime(2026, 10, 20, 19, 30);
    final end = DateTime(2026, 10, 20, 20, 30);
    final intent = calendarIntent(
      CalendarEvent(
        title: 'Load shedding (Group V) at Home',
        first: start,
        last: end,
        allDay: false,
      ),
    );

    expect(intent.arguments!['allDay'], isFalse);
    expect(intent.arguments!['beginTime'], start.millisecondsSinceEpoch);
    expect(intent.arguments!['endTime'], end.millisecondsSinceEpoch);
  });

  test('an event without a description leaves it out', () {
    final day = DateTime(2026, 10, 25);
    final intent = calendarIntent(
      CalendarEvent(title: 'Vap Full Moon Poya Day', first: day, last: day),
    );

    expect(intent.arguments!.containsKey('description'), isFalse);
    expect(
      intent.arguments!['endTime'],
      DateTime.utc(2026, 10, 26).millisecondsSinceEpoch,
    );
  });
}
