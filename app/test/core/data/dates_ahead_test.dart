import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/dates_ahead.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';

import '../../helpers/fake_branch.dart';

FeedItem exam(String id, String title, String published, List<String> days) =>
    FeedItem(
      id: id,
      source: 'exams',
      topic: 'exams',
      headlineEn: title,
      published: DateTime.parse(published),
      data: {'kind': 'timetable', 'days': days},
    );

HolidayNow holiday(String day, String name, {bool tentative = false}) =>
    HolidayNow(day: DateTime.parse(day), name: name, tentative: tentative);

void main() {
  group('upcomingExams', () {
    final today = DateTime(2026, 10, 20);

    test('lists the exams ahead by their first day, with short names', () {
      final exams = upcomingExams([
        exam(
          'exam-2479',
          'G.C.E. (Ordinary Level) Examination - 2026 Time Table',
          '2026-10-12',
          ['2026-12-09', '2026-12-08'],
        ),
        exam(
          'exam-2465',
          'General Information Technology Examination - 2026',
          '2026-09-18',
          ['2026-10-24'],
        ),
      ], today);

      expect([for (final exam in exams) exam.name], ['GIT 2026', 'O/L 2026']);
      expect(exams.last.first, DateTime(2026, 12, 8));
      expect(exams.last.last, DateTime(2026, 12, 9));
    });

    test('an amended timetable takes the place of the one before', () {
      final exams = upcomingExams([
        exam(
          'exam-2',
          'Advanced Level Examination - 2027 (Amended)',
          '2026-09-01',
          ['2027-08-11'],
        ),
        exam('exam-1', 'Advanced Level Examination - 2027', '2026-06-01', [
          '2027-08-10',
        ]),
      ], today);

      expect(exams.single.item.id, 'exam-2');
    });

    test('leaves out exams that are over and items without days', () {
      final exams = upcomingExams([
        exam('exam-2421', 'Advanced Level Examination - 2026', '2026-08-07', [
          '2026-08-10',
          '2026-09-05',
        ]),
        exam(
          'exam-9',
          'Ordinary Level Examination - 2026 Notice',
          '2026-10-01',
          [],
        ),
      ], today);

      expect(exams, isEmpty);
    });

    test('an exam on now is still listed', () {
      final exams = upcomingExams([
        exam('exam-1', 'Ordinary Level Examination - 2026', '2026-10-01', [
          '2026-10-19',
          '2026-10-21',
        ]),
      ], today);

      expect(exams, hasLength(1));
    });
  });

  group('longWeekends', () {
    final today = DateTime(2026, 1, 1);

    test('a holiday on a Friday or Monday makes three days', () {
      final weekends = longWeekends([
        holiday('2026-04-03', 'Good Friday'),
        holiday('2026-06-29', 'Poson Full Moon Poya Day'),
      ], today);

      expect(
        [for (final weekend in weekends) (weekend.first, weekend.length)],
        [(DateTime(2026, 4, 3), 3), (DateTime(2026, 6, 27), 3)],
      );
    });

    test('holidays side by side run on into the weekend', () {
      final weekends = longWeekends([
        holiday('2026-04-13', 'Day prior to Sinhala and Tamil New Year Day'),
        holiday('2026-04-14', 'Sinhala and Tamil New Year Day'),
      ], today);

      expect(weekends.single.first, DateTime(2026, 4, 11));
      expect(weekends.single.last, DateTime(2026, 4, 14));
      expect(weekends.single.holidays, hasLength(2));
    });

    test('a holiday on a weekend day or midweek makes none', () {
      final weekends = longWeekends([
        holiday('2026-10-25', 'Vap Full Moon Poya Day'),
        holiday('2026-11-11', 'Midweek holiday'),
      ], today);

      expect(weekends, isEmpty);
    });

    test('a tentative holiday makes a tentative long weekend, and past ones '
        'go', () {
      final weekends = longWeekends([
        holiday('2026-04-03', 'Good Friday'),
        holiday('2026-11-09', 'Deepavali', tentative: true),
      ], DateTime(2026, 10, 20));

      expect(weekends.single.first, DateTime(2026, 11, 7));
      expect(weekends.single.tentative, isTrue);
    });
  });

  test("the weekly gazette's applications still open, soonest to close "
      'first', () {
    final items = [
      for (final json in [
        notice('weekly-2510-a', '2026-10-09', closes: '2026-11-09'),
        notice('weekly-2510-b', '2026-10-09', closes: '2026-10-30'),
        notice('weekly-2509-a', '2026-10-02', closes: '2026-10-16'),
        notice('weekly-2510-c', '2026-10-09'),
        item('gazette-2510-20', '2026-10-12'),
      ])
        FeedItem.fromJson(json),
    ];

    expect(
      [
        for (final item in applicationsClosing(items, DateTime(2026, 10, 20)))
          item.id,
      ],
      ['weekly-2510-b', 'weekly-2510-a'],
    );
  });
}
