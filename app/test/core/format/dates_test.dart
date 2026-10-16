import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/format/dates.dart';

void main() {
  test('short dates have no padding and an English month', () {
    expect(shortDate(DateTime(2026, 10, 2)), '2 Oct 2026');
    expect(shortDate(DateTime(2027, 1, 31)), '31 Jan 2027');
  });

  test('times are on a 24-hour clock', () {
    expect(clock(6 * 60), '06:00');
    expect(clock(23 * 60 + 5), '23:05');
    expect(
      dayTime(DateTime(2026, 10, 16, 9, 30), today: DateTime(2026, 10, 16)),
      '16 Oct, 09:30',
    );
  });
}
