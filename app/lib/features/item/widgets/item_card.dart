import 'package:flutter/material.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';

/// An item in a list: topic and issuer with the date, the headline, and for
/// price items the first few key numbers with the price before.
class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.item,
    this.isNew = false,
    this.onTap,
    super.key,
  });

  /// Key numbers shown on a card; the item screen has them all.
  static const maxNumbers = 3;

  final FeedItem item;
  final bool isNew;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quiet = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final numbers = item.keyNumbers;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isNew) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      itemMeta(item),
                      style: quiet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    cardDate(item.published, today: DateTime.now()),
                    style: quiet,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                displayHeadline(item),
                style: theme.textTheme.titleMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (numbers.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final number in numbers.take(maxNumbers))
                  KeyNumberRow(number: number),
                if (numbers.length > maxNumbers)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '+${numbers.length - maxNumbers} more',
                      style: quiet,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A key number on one line: the label, then the value with the one before.
class KeyNumberRow extends StatelessWidget {
  const KeyNumberRow({required this.number, super.key});

  final KeyNumber number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    final previous = number.previous;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shortLabel(number.label),
              style: body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount(number.value),
            style: body?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (previous != null)
            Text(
              ' (was ${amount(previous)})',
              style: body?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
