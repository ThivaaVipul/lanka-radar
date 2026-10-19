import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/headlines.dart';

// Tamil text built from code points, so this file stays plain ASCII.
final tamil = String.fromCharCodes([0x0B9A, 0x0BC1, 0x0B99, 0x0BCD, 0x0B95]);

FeedItem gazette({
  required String headline,
  String issuer = 'Election Commission',
  String? ta,
  String? number = '2510/19',
}) => FeedItem(
  id: 'gazette-2510-19',
  source: 'gazettes',
  topic: 'gazettes',
  issuer: issuer,
  headlineEn: headline,
  headlineTa: ta,
  published: DateTime(2026, 10, 12),
  data: {'number': ?number},
);

void main() {
  group('titleCase', () {
    test('turns a title in capitals into title case', () {
      expect(
        titleCase(
          'FILLING OF A VACANCY IN THE OFFICE OF MEMBER OF THE UDAPALATHA '
          'PRADESHIYA SABHA UNDER SECTION 66A(1)(b) OF THE LOCAL AUTHORITIES '
          'ELECTIONS ORDINANCE (CHAPTER 262)',
        ),
        'Filling of a Vacancy in the Office of Member of the Udapalatha '
        'Pradeshiya Sabha under Section 66A(1)(b) of the Local Authorities '
        'Elections Ordinance (Chapter 262)',
      );
    });

    test('leaves mixed case words, numbers and punctuation as they are', () {
      expect(
        titleCase(
          'CONSUMER AFFAIRS AUTHORITY ACT, No. 9 OF 2003 (Amended) Direction '
          'under Section 12 (2)',
        ),
        'Consumer Affairs Authority Act, No. 9 of 2003 (Amended) Direction '
        'under Section 12 (2)',
      );
      expect(titleCase('Revise the Fuel Price'), 'Revise the Fuel Price');
    });

    test('keeps acronyms and roman numerals, and starts with a capital', () {
      expect(
        titleCase('THE CAA ORDER ON SLS MARKS, PART IV AND LKR PRICES'),
        'The CAA Order on SLS Marks, Part IV and LKR Prices',
      );
      expect(titleCase('INCOME-TAX OF A COMPANY'), 'Income-Tax of a Company');
    });

    test('leaves Tamil alone', () {
      expect(titleCase(tamil), tamil);
    });
  });

  group('displayHeadline', () {
    test('reads line breaks inside a title as spaces', () {
      expect(
        titleCase('Industrial Dispute between\nH.B. Upawansha and Lanka Salt'),
        'Industrial Dispute between H.B. Upawansha and Lanka Salt',
      );
    });

    test("drops the issuer's name the list puts in front", () {
      final item = gazette(
        headline: 'Election Commission - FILLING OF A VACANCY',
        ta: tamil,
      );

      expect(displayHeadline(item), 'Filling of a Vacancy');
      expect(tamilUnderHeadline(item), tamil);
    });

    test('shows the Tamil title when the English one is only the issuer', () {
      final item = gazette(headline: 'Election Commission', ta: tamil);

      expect(displayHeadline(item), tamil);
      expect(tamilUnderHeadline(item), isNull);
    });

    test('falls back to the gazette number', () {
      final item = gazette(
        headline: 'Ministry of Labour',
        issuer: 'Ministry of Labour',
      );

      expect(displayHeadline(item), 'Gazette 2510/19');
    });
  });

  test('the meta line has the topic and the issuer', () {
    final item = gazette(headline: 'X');

    expect(itemMeta(item), 'Gazettes${dot}Election Commission');
  });
}
