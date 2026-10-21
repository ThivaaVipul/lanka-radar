import 'package:flutter/material.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/card_lines.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/pdf/view/pdf_page.dart';

/// One item: the headline with the Tamil one under it, the key numbers, and the
/// official PDFs, which open in the app (a weekly gazette notice's English one
/// at its page), and the official page and price-list image, which open in
/// the browser.
class ItemPage extends StatelessWidget {
  const ItemPage({required this.item, this.open = openExternally, super.key});

  static Route<void> route(FeedItem item) =>
      MaterialPageRoute(builder: (context) => ItemPage(item: item));

  final FeedItem item;
  final OpenLink open;

  /// The item's buttons in order: the English and Tamil PDFs (the Sinhala one
  /// only when it is the only PDF) and a price-list image, with their links.
  static List<(String, String)> buttonsFor(FeedItem item) {
    final links = item.links;
    final english = links['pdf_en'];
    final tamil = links['pdf_ta'];
    final sinhala = links['pdf_si'];
    final image = links['image'];
    return [
      if (english != null) ('English PDF', english),
      if (tamil != null) ('Tamil PDF', tamil),
      if (sinhala != null && english == null && tamil == null)
        ('Sinhala PDF', sinhala),
      if (image != null) ('Price list', image),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final tamil = tamilUnderHeadline(item);
    final page = item.links['page'];
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            itemMeta(item),
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(displayHeadline(item), style: theme.textTheme.headlineSmall),
          if (tamil != null) ...[
            const SizedBox(height: 12),
            Text(
              tamil,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(_details(), style: quiet),
          if (item.keyNumbers.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  children: [
                    for (final number in item.keyNumbers)
                      KeyNumberRow(number: number),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, link) in buttonsFor(item))
                FilledButton.tonal(
                  onPressed: () => label.endsWith('PDF')
                      ? Navigator.of(context).push(
                          PdfPage.route(
                            link,
                            title: '${cardTitle(item)} ($label)',
                            page: link == item.links['pdf_en'] ? _page : 1,
                            open: open,
                          ),
                        )
                      : _open(context, link),
                  child: Text(label),
                ),
            ],
          ),
          if (page != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => _open(context, page),
                child: const Text('Official page'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A weekly gazette notice's page in the English PDF.
  int get _page => switch (item.data['page']) {
    final int page when page > 0 => page,
    _ => 1,
  };

  /// No. 2509/59 . Published 8 Oct 2026 . Effective 30 Sep 2026, and for a
  /// weekly gazette notice . Closes 30 Oct
  String _details() {
    final number = item.data['number'];
    final effective = item.effective;
    return [
      if (number is String) 'No. $number',
      'Published ${shortDate(item.published)}',
      if (effective != null && effective != item.published)
        'Effective ${shortDate(effective)}',
      if (item.closes case final closes?)
        closingNote(closes, today: DateTime.now()),
    ].join(dot);
  }

  Future<void> _open(BuildContext context, String link) async {
    var opened = false;
    try {
      opened = await open(Uri.parse(link));
    } on Exception {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open the link")));
    }
  }
}
