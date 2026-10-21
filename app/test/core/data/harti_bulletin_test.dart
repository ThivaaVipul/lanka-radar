import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/harti_bulletin.dart';

import '../../helpers/fake_sources.dart';

void main() {
  test('the listing names each day once, newest first, weekends too', () {
    final listed = listedBulletins(
      utf8.decode(fixtureBytes('harti_listing.html'), allowMalformed: true),
    );

    expect(listed.length, greaterThan(50));
    expect(listed.take(3).toList(), [
      (
        DateTime(2026, 10, 20),
        'assets/pdf/food_price/daily/eng/2026/October/'
            'Vegetable Pricenew ex1(2026.10.20).pdf',
      ),
      (
        DateTime(2026, 10, 19),
        'assets/pdf/food_price/daily/eng/2026/October/'
            'Vegetable Pricenew ex1(2026.10.19).pdf',
      ),
      (
        DateTime(2026, 10, 18),
        'assets/pdf/food_price/daily/eng/2026/October/'
            'Vegetables Wholesale Prices (2026.10.18).pdf',
      ),
    ]);
  });

  group("a weekday's bulletin", () {
    late List<WholesaleRow> rows;

    setUpAll(() async {
      rows = parseBulletin(
        await readBulletin(
          Uint8List.fromList(fixtureBytes('harti_2026-10-20.pdf')),
        ),
      );
    });

    WholesaleRow named(String name) =>
        rows.singleWhere((row) => row.name == name);

    test('has the vegetables at each centre that had a price', () {
      final beans = named('Beans');

      expect(beans.group, 'Vegetables');
      expect(beans.prices['Peliyagoda'], (low: 500.0, high: 600.0));
      expect(beans.prices['Dambulla'], (low: 350.0, high: 450.0));
      expect(beans.prices['Thambuththegama'], (low: 400.0, high: 480.0));
      // Keppetipola and Norochchole printed no prices.
      expect(beans.prices.containsKey('Keppetipola'), isFalse);
      expect(beans.prices.length, 8);
      expect(named('Cabbage (Nuwara Eliya)').prices.keys, [
        'Kandy',
        'Meegoda',
        'Nuwaraeliya',
        'Bandarawela',
      ]);
      expect(rows.where((row) => row.group == 'Vegetables').length, 31);
    });

    test('has rice and dried foods at Pettah, named by their group', () {
      expect(named('Samba 1').group, 'Rice');
      expect(named('Samba 1').prices, {'Pettah': (low: 225.0, high: 230.0)});
      expect(named('Ponni samba (imported)').group, 'Rice');
      expect(named('Red onion (Vedalan)').prices['Pettah'], (
        low: 400.0,
        high: 450.0,
      ));
      expect(named('Dried chillies (imported)').prices['Pettah'], (
        low: 1050.0,
        high: 1200.0,
      ));
      expect(named('Eggs (brown)').unit, 'egg');
      expect(named('Red dhal').group, 'Other');
      // A variety with no price that day is not a heading.
      expect(rows.any((row) => row.name.startsWith('Sinnan')), isFalse);
    });
  });

  test('a page without the tables is not a bulletin', () {
    expect(() => parseBulletin(const [[]]), throwsFormatException);
  });
}
