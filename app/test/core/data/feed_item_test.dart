import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/feed_item.dart';

void main() {
  test('reads an item as the workflow publishes it', () {
    final item = FeedItem.fromJson({
      'id': 'gazette-2504-03',
      'source': 'gazettes',
      'topic': 'prices',
      'issuer': 'Ministry of Energy',
      'headline': {'en': 'Revise the Fuel Price', 'ta': null},
      'keyNumbers': [
        {
          'label': 'Lanka Petrol 92 Octane',
          'value': 399.0,
          'unit': 'LKR',
          'previous': 414.0,
        },
        {'label': 'Tuna 155g', 'value': 220, 'unit': 'LKR'},
      ],
      'published': '2026-08-31',
      'effective': null,
      'links': {
        'page': 'https://documents.gov.lk',
        'pdf_en': 'https://x/e.pdf',
      },
      'data': {
        'number': '2504/03',
        'languages': ['en', 'si', 'ta'],
      },
      'alert': true,
    });

    expect(item.headlineEn, 'Revise the Fuel Price');
    expect(item.headlineTa, isNull);
    expect(item.published, DateTime(2026, 8, 31));
    expect(item.effective, isNull);
    expect(item.keyNumbers, [
      const KeyNumber(
        label: 'Lanka Petrol 92 Octane',
        value: 399,
        unit: 'LKR',
        previous: 414,
      ),
      const KeyNumber(label: 'Tuna 155g', value: 220, unit: 'LKR'),
    ]);
    expect(item.links['pdf_en'], 'https://x/e.pdf');
    expect(item.data['number'], '2504/03');
    expect(item.alert, isTrue);
  });
}
