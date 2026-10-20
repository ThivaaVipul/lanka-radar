import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/market_report.dart';

import '../../helpers/fake_sources.dart';

void main() {
  Future<Map<String, ReportRow>> read(String name) async => {
    for (final row in parseReport(
      await readReport(Uint8List.fromList(fixtureBytes(name))),
    ))
      row.name: row,
  };

  test("reads each market's retail price that day", () async {
    final rows = await read('cbsl_price_report_20261019.pdf');

    expect(rows, hasLength(42));
    expect(
      rows['Beans'],
      const ReportRow(
        name: 'Beans',
        unit: 'kg',
        section: 'Vegetables',
        retail: {'Pettah': 600, 'Dambulla': 430, 'Narahenpita': 700},
      ),
    );
    expect(rows['Lime']!.retail['Narahenpita'], 1800);
    expect(rows['Snake gourd']!.retail['Dambulla'], 285);
    expect(rows['Egg (White)']!.unit, 'each');
    expect(rows['Coconut oil']!.unit, 'l');
    expect(rows['Red Onion (Imp)']!.retail['Narahenpita'], isNull);
    expect(rows['Samba']!.section, 'Rice');
  });

  test("fish prices are Negombo's, not Dambulla's", () async {
    final rows = await read('cbsl_price_report_20261019.pdf');

    expect(rows['Kelawalla']!.section, 'Fish');
    expect(rows['Kelawalla']!.retail, {'Negombo': 1760, 'Narahenpita': 2380});
  });

  test(
    'reads a report compared with yesterday, a name above its prices',
    () async {
      final rows = await read('cbsl_price_report_20260102.pdf');

      expect(rows, hasLength(42));
      expect(rows['Beans']!.retail, {
        'Pettah': 500,
        'Dambulla': 680,
        'Narahenpita': 800,
      });
      expect(rows['Tomato']!.retail, {
        'Pettah': 550,
        'Dambulla': 345,
        'Narahenpita': 700,
      });
    },
  );

  test('a page without the table is not a report', () {
    expect(
      () => parseReport([(text: 'A', left: 10, right: 15, bottom: 20)]),
      throwsFormatException,
    );
  });

  test('the listing links the last few weeks, newest first', () {
    final days = listedReportDays(fixture('cbsl_price_report_listing.html'));

    expect(days.first, DateTime(2026, 10, 19));
    expect(days.last, DateTime(2026, 10, 2));
    expect(days, hasLength(12));
    expect(
      MarketReport.of(DateTime(2026, 10, 2)).path,
      endsWith('/pricerpt/price_report_20261002_e.pdf'),
    );
  });
}
