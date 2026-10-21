import 'package:flutter/material.dart';
import 'package:lanka_radar/app/share.dart';
import 'package:lanka_radar/app/viz/sparkline.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/card_lines.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/format/share_texts.dart';
import 'package:lanka_radar/features/item/widgets/highlight.dart';

/// An item as a row of a list: what changed (or the official title) with the
/// date across from it, who published it, and for a notice with a closing date
/// how long is left. Rows
/// sit together in an [ItemGroup]; the item page has the rest.
class ItemTile extends StatelessWidget {
  const ItemTile({
    required this.item,
    this.isNew = false,
    this.onTap,
    this.highlight = const [],
    this.line,
    this.showDate = true,
    super.key,
  });

  final FeedItem item;
  final bool isNew;
  final VoidCallback? onTap;

  /// Words to pick out in the title, from a search.
  final List<String> highlight;

  /// A line of the item's text that a search found its words in.
  final String? line;

  /// Show the date across from the title; off under a day's heading.
  final bool showDate;

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
                      if (showDate || isNew) const SizedBox(width: 12),
                      if (showDate || isNew)
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
                              if (showDate)
                                Text(
                                  cardDate(
                                    item.published,
                                    today: DateTime.now(),
                                  ),
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
                  if (item.issuer case final issuer?
                      when issuer.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      issuer,
                      style: muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (item.closes case final closes?) ...[
                    const SizedBox(height: 8),
                    ClosingBar(opened: item.published, closes: closes),
                  ],
                  if (line case final line? when line.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      highlighted(
                        line,
                        highlight,
                        strong: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.35,
                      ),
                      maxLines: 2,
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

/// How long applications stay open, as a bar running out, with the day they
/// close: ochre in the last week.
class ClosingBar extends StatelessWidget {
  const ClosingBar({required this.opened, required this.closes, super.key});

  final DateTime opened;
  final DateTime closes;

  /// The bar turns ochre this close to the end.
  static const lastWeek = Duration(days: 7);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();
    final end = closes.add(const Duration(days: 1));
    final total = end.difference(opened).inHours;
    final left = end.difference(now).inHours;
    final share = total <= 0 ? 0.0 : (left / total).clamp(0.0, 1.0);
    final soon = left > 0 && end.difference(now) <= lastWeek;
    final color = left <= 0
        ? colors.outline
        : soon
        ? colors.tertiary
        : colors.primary;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: DrawIn(
              builder: (context, drawn) => LinearProgressIndicator(
                value: share * drawn,
                minHeight: 4,
                color: color,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          closingNote(closes, today: now),
          style: theme.textTheme.labelMedium?.copyWith(
            color: soon ? colors.tertiary : colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Rows on one surface, with hairlines between them that start where the text
/// does.
class ItemGroup extends StatelessWidget {
  const ItemGroup({required this.children, super.key});

  /// Where a divider starts: where the text does.
  static const indent = 16.0;

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
