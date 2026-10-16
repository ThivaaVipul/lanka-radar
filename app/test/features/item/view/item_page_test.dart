import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';

// Tamil text built from code points, so this file stays plain ASCII.
final tamil = String.fromCharCodes([0x0B9A, 0x0BC1, 0x0B99, 0x0BCD, 0x0B95]);

const page = 'https://documents.gov.lk/web/extra_gazettes';
const english = 'https://documents.gov.lk/e.pdf';
const tamilPdf = 'https://documents.gov.lk/t.pdf';
const sinhala = 'https://documents.gov.lk/s.pdf';

FeedItem fuelRevision({Map<String, String>? links}) => FeedItem(
  id: 'gazette-2504-03',
  source: 'gazettes',
  topic: 'prices',
  issuer: 'Ministry of Energy',
  headlineEn: 'Ministry of Energy - Revise the Fuel Price',
  headlineTa: tamil,
  published: DateTime(2026, 8, 31),
  effective: DateTime(2026, 9, 1),
  keyNumbers: const [
    KeyNumber(
      label: 'Lanka Petrol 92 Octane',
      value: 399,
      unit: 'LKR',
      previous: 414,
    ),
  ],
  links:
      links ??
      const {
        'page': page,
        'pdf_en': english,
        'pdf_ta': tamilPdf,
        'pdf_si': sinhala,
      },
  data: const {'number': '2504/03'},
);

void main() {
  late List<Uri> opened;

  Future<void> show(WidgetTester tester, FeedItem item) async {
    opened = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ItemPage(
          item: item,
          open: (link) async {
            opened.add(link);
            return true;
          },
        ),
      ),
    );
  }

  testWidgets('shows the headline with the Tamil one under it, the numbers '
      'and the details', (tester) async {
    await show(tester, fuelRevision());

    expect(find.text('Revise the Fuel Price'), findsOneWidget);
    expect(find.text(tamil), findsOneWidget);
    expect(find.text('Petrol 92'), findsOneWidget);
    expect(find.text('399'), findsOneWidget);
    expect(find.text(' (was 414)'), findsOneWidget);
    expect(find.textContaining('No. 2504/03'), findsOneWidget);
    expect(find.textContaining('Effective 1 Sep 2026'), findsOneWidget);
  });

  testWidgets('offers the English and Tamil PDFs, not the Sinhala one, and '
      'opens them', (tester) async {
    await show(tester, fuelRevision());

    expect(find.text('English PDF'), findsOneWidget);
    expect(find.text('Tamil PDF'), findsOneWidget);
    expect(find.text('Sinhala PDF'), findsNothing);

    await tester.tap(find.text('Tamil PDF'));
    await tester.tap(find.text('Official page'));
    expect(opened, [Uri.parse(tamilPdf), Uri.parse(page)]);
  });

  testWidgets('offers the Sinhala PDF when it is the only one', (tester) async {
    await show(
      tester,
      fuelRevision(links: const {'page': page, 'pdf_si': sinhala}),
    );

    expect(find.text('Sinhala PDF'), findsOneWidget);
    expect(find.text('English PDF'), findsNothing);
  });

  test('a price list item offers its image', () {
    final gas = FeedItem(
      id: 'gas-litro-2026-10-06',
      source: 'gas',
      topic: 'prices',
      headlineEn: 'Litro gas prices from 6 Oct 2026',
      published: DateTime(2026, 10, 6),
      links: const {
        'image': 'https://litro/list.webp',
        'page': 'https://litro',
      },
    );

    expect(ItemPage.buttonsFor(gas), [
      ('Price list', 'https://litro/list.webp'),
    ]);
  });
}
