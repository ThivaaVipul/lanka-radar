import 'package:flutter/material.dart';
import 'package:lanka_radar/app/share.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/card_lines.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/format/share_texts.dart';
import 'package:lanka_radar/features/item/widgets/highlight.dart';
import 'package:lanka_radar/features/item/widgets/topic_badge.dart';

/// An item as a row of a list: its topic's icon, what changed (or the
/// official title) with the date across from it, and who published it. Rows
/// sit together in an [ItemGroup]; the item page has the rest.
class ItemTile extends StatelessWidget {
  const ItemTile({
    required this.item,
    this.isNew = false,
    this.onTap,
    this.highlight = const [],
    super.key,
  });

  final FeedItem item;
  final bool isNew;
  final VoidCallback? onTap;

  /// Words to pick out in the title, from a search.
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return InkWell(
      onTap: onTap,
      onLongPress: () => shareText(context, noticeShare(item)),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text.rich(
                          highlighted(
                            cardTitle(item),
                            highlight,
                            strong: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: isNew
                                ? FontWeight.w700
                                : FontWeight.w500,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isNew) ...[
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              cardDate(item.published, today: DateTime.now()),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isNew
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (item.issuer case final issuer?) ...[
                    const SizedBox(height: 3),
                    Text(
                      issuer,
                      style: muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rows on one surface, with hairlines between them that start where the text
/// does.
class ItemGroup extends StatelessWidget {
  const ItemGroup({required this.children, super.key});

  /// Where a divider starts: past a row's icon.
  static const indent = 66.0;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const Divider(height: 1, indent: indent),
            child,
          ],
        ],
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
