import 'package:flutter/material.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/card_lines.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/features/item/widgets/topic_badge.dart';

/// An item in a list: its topic's badge, what changed (or the official title),
/// and who published it when. The item page has the rest.
class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.item,
    this.isNew = false,
    this.onTap,
    super.key,
  });

  final FeedItem item;
  final bool isNew;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopicBadge(TopicLook.of(item)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle(item),
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cardMeta(item, today: DateTime.now()),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isNew) ...[
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
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
