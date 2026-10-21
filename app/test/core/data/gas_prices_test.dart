import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/gas_prices.dart';

import '../../helpers/fake_branch.dart';

void main() {
  final september = FeedItem.fromJson(
    gasList('2026-09-01', {
      'Colombo': [4100, 1650, 770],
      'Jaffna': [4500, 1880, 950],
    }),
  );
  final october = FeedItem.fromJson(
    gasList('2026-10-06', {
      'Colombo': [4365, 1750, 815],
      'Jaffna': [4748.84, 1977.13, 999.25],
    }),
  );
  // A list the workflow couldn't read: a link to its image only.
  final unread = FeedItem(
    id: 'gas-litro-2026-10-20',
    source: 'gas',
    topic: 'prices',
    headlineEn: 'Litro gas prices from 20 Oct 2026',
    published: DateTime(2026, 10, 20),
  );

  test("a district's prices in the latest list read, against the one "
      'before', () {
    final prices = gasPrices([unread, october, september], 'Jaffna')!;

    expect(prices.list, october);
    expect(prices.prices, const [
      GasPrice(size: '12.5 kg', price: 4748.84, before: 4500),
      GasPrice(size: '5 kg', price: 1977.13, before: 1880),
      GasPrice(size: '2.3 kg', price: 999.25, before: 950),
    ]);
  });

  test('nothing before the first list, and nothing for a district not in '
      'it', () {
    expect(
      gasPrices([october], 'Colombo')!.prices.first,
      const GasPrice(size: '12.5 kg', price: 4365),
    );
    expect(gasPrices([october], 'Kandy'), isNull);
    expect(gasPrices([unread], 'Colombo'), isNull);
  });

  test("a list alerts with the district's prices", () {
    final item = forDistrict(october, [october, september], 'Jaffna');

    expect(item.data['district'], 'Jaffna');
    expect(
      notificationBody(item),
      'Jaffna: 12.5 kg 4,748.84 (was 4,500), 5 kg 1,977.13 (was 1,880), '
      '2.3 kg 999.25 (was 950)',
    );
    // An older list, or an unknown district, keeps the workflow's numbers.
    expect(forDistrict(september, [october, september], 'Jaffna'), september);
    expect(forDistrict(october, [october], 'Kandy'), october);
  });
}
