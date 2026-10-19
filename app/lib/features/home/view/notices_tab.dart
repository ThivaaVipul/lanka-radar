import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/topics.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/notice_rows.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/item/widgets/topic_badge.dart';

/// Notices: every item newest first under month headings, filtered by topic,
/// with each week's election notices folded into one row.
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
        final rows = noticeRows(items);
        return RefreshIndicator(
          onRefresh: context.read<HomeCubit>().refresh,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _TopicChips(selected: state.topic, empty: rows.isEmpty);
              }
              return switch (rows[index - 1]) {
                MonthRow(:final month) => _MonthHeading(month: month),
                ItemRow(:final item) => _Padded(
                  child: ItemCard(
                    item: item,
                    isNew: state.isNew(item),
                    onTap: () =>
                        Navigator.of(context).push(ItemPage.route(item)),
                  ),
                ),
                final ElectionWeek week => _Padded(
                  child: _ElectionFold(
                    week: week,
                    open: _open.contains(week.week),
                    isNew: week.items.any(state.isNew),
                    onToggle: () => setState(() {
                      if (!_open.remove(week.week)) {
                        _open.add(week.week);
                      }
                    }),
                    isItemNew: state.isNew,
                  ),
                ),
              };
            },
          ),
        );
      },
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: child,
  );
}

/// "Election notices (7)" for a week, which opens to list them.
class _ElectionFold extends StatelessWidget {
  const _ElectionFold({
    required this.week,
    required this.open,
    required this.isNew,
    required this.onToggle,
    required this.isItemNew,
  });

  final ElectionWeek week;
  final bool open;
  final bool isNew;
  final VoidCallback onToggle;
  final bool Function(FeedItem item) isItemNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = DateTime.now();
    final newest = week.items.first.published;
    final oldest = week.items.last.published;
    final days = newest == oldest
        ? cardDate(newest, today: today)
        : '${cardDate(oldest, today: today)} to ${cardDate(newest, today: today)}';
    return Column(
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  const TopicBadge(TopicLook.elections),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Election notices (${week.items.length})',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ['Election Commission', days].join(dot),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isNew)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open)
          for (final item in week.items)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, top: 8),
              child: ItemCard(
                item: item,
                isNew: isItemNew(item),
                onTap: () => Navigator.of(context).push(ItemPage.route(item)),
              ),
            ),
      ],
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        monthHeading(month),
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
