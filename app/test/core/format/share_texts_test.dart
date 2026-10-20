import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/market_prices.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/format/share_texts.dart';

import '../../helpers/fake_branch.dart';
import '../../helpers/fake_sources.dart';

void main() {
  test('a notice: its title, who and when, then its English PDF', () {
    final notice = FeedItem.fromJson({
      ...item(
        'gazette-2510-20',
        '2026-10-12',
        headline: 'Wages Boards Ordinance',
        issuer: 'Department of Labour',
      ),
      'links': {
        'page': 'https://documents.gov.lk/web/extra_gazettes',
        'pdf_en': 'https://documents.gov.lk/2510-20_E.pdf',
      },
    });

    expect(
      noticeShare(notice),
      'Wages Boards Ordinance\n'
      'Department of Labour, 12 Oct 2026\n'
      'https://documents.gov.lk/2510-20_E.pdf',
    );
  });

  test('a notice without a PDF shares its page', () {
    final notice = FeedItem.fromJson(item('exam-2479', '2026-10-01'));

    expect(
      noticeShare(notice).split('\n').last,
      'https://documents.gov.lk/web/extra_gazettes',
    );
  });

  test('a fuel price: the price, its change and since when', () {
    final price = FuelNow(
      name: 'Petrol 92',
      price: 399,
      since: DateTime(2026, 10, 1),
      was: 412,
    );

    expect(
      fuelShare(price, asOf: DateTime(2026, 10, 20, 9)),
      'Petrol 92: Rs 399, down Rs 13 since 1 Oct\n'
      'CEYPETCO, 20 Oct 2026\n'
      'https://ceypetco.gov.lk/marketing-sales/',
    );
    expect(
      fuelShare(
        price,
        asOf: DateTime(2026, 10, 1),
        fromGazette: true,
      ).split('\n')[1],
      'Fuel price gazette, 1 Oct 2026',
    );
  });

  test("USD/LKR: the rate and the week's move", () {
    final rates = [
      RateNow(day: DateTime(2026, 10, 20), rate: 301.2),
      RateNow(day: DateTime(2026, 10, 13), rate: 300),
    ];

    expect(
      rateShare(rates, backup: false),
      'USD/LKR: 301.20, up 0.4% in a week\n'
      'Central Bank of Sri Lanka, 20 Oct 2026\n'
      'https://www.cbsl.gov.lk/en/rates-and-indicators/exchange-rates',
    );
    expect(rateShare(rates.take(1).toList(), backup: true).split('\n'), [
      'USD/LKR: 301.20',
      'Backup copy, 20 Oct 2026',
      'https://www.cbsl.gov.lk/en/rates-and-indicators/exchange-rates',
    ]);
  });

  test("a market price: where, the change and that day's report", () {
    const quote = MarketQuote(
      good: MarketGood(name: 'Beans', unit: 'kg', section: 'Vegetables'),
      market: 'Narahenpita',
      price: 480,
      before: 460,
    );

    expect(
      marketShare(quote, day: DateTime(2026, 10, 20)),
      'Beans: Rs 480 per kg at Narahenpita, up Rs 20\n'
      'Central Bank of Sri Lanka, 20 Oct 2026\n'
      'https://www.cbsl.gov.lk/sites/default/files/cbslweb_documents/'
      'statistics/pricerpt/price_report_20261020_e.pdf',
    );
  });

  test('a controlled price: the most it may be sold for, and its order', () {
    final order = FeedItem.fromJson({
      ...item(
        'gazette-2504-86',
        '2026-09-02',
        issuer: 'Consumer Affairs Authority',
      ),
      'links': {'pdf_en': 'https://documents.gov.lk/2504-86_E.pdf'},
    });

    expect(
      goodShare('Tuna 155g', [
        PricePoint(DateTime(2026, 5, 1), 500),
        PricePoint(DateTime(2026, 9, 2), 480),
      ], order),
      'Tuna 155g: maximum retail price Rs 480, down Rs 20\n'
      'Consumer Affairs Authority, 2 Sep 2026\n'
      'https://documents.gov.lk/2504-86_E.pdf',
    );
  });

  test('a power cut names the CEB area, not the place or where it is', () {
    final outages = outagesAt(
      parseOutages(fixture('edlcare_outages_49.json')),
      gampahaHome,
    );
    final text = cutShare(
      PlaceCuts(place: home, outages: outages),
      checked: DateTime(2026, 10, 20, 10, 50),
    );

    expect(
      text,
      'Power cut in Gampaha (CEB area): a breakdown since 09:24\n'
      'EDLCare, 20 Oct 2026, 10:50\n'
      'https://edlcare.edl.lk/incognito/outage-map',
    );
    expect(text, isNot(contains('Home')));
    expect(text, isNot(contains('7.09')));
  });
}
