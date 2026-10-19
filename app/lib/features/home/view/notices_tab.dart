import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/topics.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/notice_rows.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/item/widgets/topic_badge.dart';

/// Notices: every item newest first, one list a month, filtered by topic, with
/// each week's election notices folded into one row.
class NoticesTab extends StatefulWidget {
  const NoticesTab({super.key});

  @override
  State<NoticesTab> createState() => _NoticesTabState();
}

class _NoticesTabState extends State<NoticesTab> {
  /// The election weeks opened, by their Monday.
  final _open = <DateTime>{};

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        final items = state.visibleItems;
        if (items == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final months = _byMonth(noticeRows(items));
        return RefreshIndicator(
          onRefresh: context.read<HomeCubit>().refresh,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: months.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _TopicChips(
                  selected: state.topic,
                  empty: months.isEmpty,
                );
              }
              final (month, rows) = months[index - 1];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MonthHeading(month: month),
                  ItemGroup(
                    children: [
                      for (final row in rows) ..._rowTiles(context, state, row),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// A row's tiles: an item, or a folded week with its notices when open.
  List<Widget> _rowTiles(BuildContext context, HomeState state, NoticeRow row) {
    void open(FeedItem item) =>
        Navigator.of(context).push(ItemPage.route(item));
    return switch (row) {
      ItemRow(:final item) => [
        ItemTile(item: item, isNew: state.isNew(item), onTap: () => open(item)),
      ],
      final ElectionWeek week => [
        _ElectionFold(
          week: week,
          open: _open.contains(week.week),
          isNew: week.items.any(state.isNew),
          onToggle: () => setState(() {
            if (!_open.remove(week.week)) {
              _open.add(week.week);
            }
          }),
        ),
        if (_open.contains(week.week))
          for (final item in week.items)
            ItemTile(
              item: item,
              isNew: state.isNew(item),
              onTap: () => open(item),
            ),
      ],
      MonthRow() => const [],
    };
  }

  /// The rows under each month heading.
  static List<(DateTime, List<NoticeRow>)> _byMonth(List<NoticeRow> rows) {
    final months = <(DateTime, List<NoticeRow>)>[];
    for (final row in rows) {
      if (row is MonthRow) {
        months.add((row.month, []));
      } else {
        months.last.$2.add(row);
      }
    }
    return months;
  }
}

/// "Election notices" for a week, with how many, which opens to list them.
class _ElectionFold extends StatelessWidget {
  const _ElectionFold({
    required this.week,
    required this.open,
    required this.isNew,
    required this.onToggle,
  });

  final ElectionWeek week;
  final bool open;
  final bool isNew;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = DateTime.now();
    final newest = week.items.first.published;
    final oldest = week.items.last.published;
    final days = newest == oldest
        ? cardDate(newest, today: today)
        : '${cardDate(oldest, today: today)} to '
              '${cardDate(newest, today: today)}';
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            const TopicBadge(TopicLook.elections),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Election notices',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: isNew ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    days,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${week.items.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicChips extends StatelessWidget {
  const _TopicChips({required this.selected, required this.empty});

  final String? selected;

  /// Nothing in the chosen topic yet.
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HomeCubit>();
    final chips = [
      (null, 'All'),
      for (final MapEntry(:key, :value) in topics.entries) (key, value),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chips.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (topic, label) = chips[index];
              return ChoiceChip(
                label: Text(label),
                selected: selected == topic,
                showCheckmark: false,
                onSelected: (_) => cubit.showTopic(topic),
              );
            },
          ),
        ),
        if (empty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 24, 4, 0),
            child: Text('Nothing yet'),
          ),
      ],
    );
  }
}

class _MonthHeading extends StatelessWidget {
  const _MonthHeading({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        monthHeading(month),
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
