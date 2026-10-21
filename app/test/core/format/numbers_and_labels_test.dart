import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';

void main() {
  test('amounts: whole numbers grouped, others with two decimals', () {
    expect(amount(399), '399');
    expect(amount(2150), '2,150');
    expect(amount(1250000), '1,250,000');
    expect(amount(336.3944), '336.39');
    expect(amount(4748.84), '4,748.84');
    expect(amount(-1250.5), '-1,250.50');
  });

  test('fuel names shorten to their common names', () {
    expect(shortLabel('Lanka Petrol 92 Octane'), 'Petrol 92');
    expect(shortLabel('Lanka Petrol 95 Octane Euro 4'), 'Petrol 95');
    expect(shortLabel('Lanka Auto Diesel'), 'Diesel');
    expect(shortLabel('Lanka Super Diesel 4 Star Euro 4'), 'Super Diesel');
    expect(shortLabel('Lanka Kerosene'), 'Kerosene');
    expect(shortLabel('Lanka Industrial Kerosene'), 'Industrial kerosene');
    expect(shortLabel('Tuna 155g'), 'Tuna 155g');
  });

  test('card dates leave out the current year', () {
    final today = DateTime(2026, 10, 16);

    expect(cardDate(DateTime(2026, 10, 12), today: today), '12 Oct');
    expect(cardDate(DateTime(2025, 12, 31), today: today), '31 Dec 2025');
    expect(monthHeading(DateTime(2026, 9, 8)), 'September 2026');
  });
}
