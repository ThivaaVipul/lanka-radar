import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/app/viz/underline_tabs.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/topics.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/notice_rows.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/notices/view/week_page.dart';

/// Notices: every item newest first on a timeline, a day at a time, filtered
/// by topic; each week's election notices fold into one row and each weekly
/// gazette's notices into another.
class NoticesTab extends StatefulWidget {
  const NoticesTab({super.key});

  @override
  State<NoticesTab> createState() => _NoticesTabState();
}

/// What the timeline lists: a month heading, or a day with its rows.
typedef _Block = ({DateTime? month, DateTime? day, List<NoticeRow> rows});

class _NoticesTabState extends State<NoticesTab> {
  /// The election weeks opened, by their Monday.
  final _open = <DateTime>{};

  static final _topics = [null, ...topics.keys];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        final items = state.visibleItems;
        if (items == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final blocks = _blocks(noticeRows(items));
        final cubit = context.read<HomeCubit>();
        return Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: UnderlineTabs(
                labels: [for (final topic in _topics) _label(topic)],
                selected: _topics.indexOf(state.topic),
                onSelected: (index) => cubit.showTopic(_topics[index]),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: cubit.refresh,
                child: blocks.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Nothing yet'),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: blocks.length,
                        itemBuilder: (context, index) {
                          final block = blocks[index];
                          final last = index == blocks.length - 1;
                          if (block.month case final month?) {
                            return _MonthMark(month: month, first: index == 0);
                          }
                          return _Day(
                            day: block.day!,
                            last: last,
                            isNew: block.rows.any(
                              (row) => _rowItems(row).any(state.isNew),
                            ),
                            rows: [
                              for (final row in block.rows)
                                ..._rowTiles(context, state, row),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _label(String? topic) => topic == null ? 'All' : topics[topic]!;

  static List<FeedItem> _rowItems(NoticeRow row) => switch (row) {
    ItemRow(:final item) => [item],
    ElectionWeek(:final items) || WeeklyGazette(:final items) => items,
    MonthRow() || DayRow() => const [],
  };

  /// A row's tiles: an item, a weekly gazette, or a folded week of election
  /// notices with its notices when open.
  List<Widget> _rowTiles(BuildContext context, HomeState state, NoticeRow row) {
    void open(FeedItem item) =>
        Navigator.of(context).push(ItemPage.route(item));
    return switch (row) {
      ItemRow(:final item) => [
        ItemTile(
          item: item,
          isNew: state.isNew(item),
          showDate: false,
          onTap: () => open(item),
        ),
      ],
      WeeklyGazette(:final week, :final items) => [
        _Fold(
          title: 'Gazette of ${cardDate(week, today: DateTime.now())}',
          note: _weeklyNote(items),
          count: items.length,
          isNew: items.any(state.isNew),
          trailing: Icons.chevron_right,
          onTap: () => Navigator.of(context).push(WeekPage.route(week)),
        ),
      ],
      final ElectionWeek week => [
        _Fold(
          title: 'Election notices',
          note: _span(week.items),
          count: week.items.length,
          isNew: week.items.any(state.isNew),
          trailing: _open.contains(week.week)
              ? Icons.expand_less
              : Icons.expand_more,
          onTap: () => setState(() {
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
      MonthRow() || DayRow() => const [],
    };
  }

  /// "6 vacancies, 3 exams".
  static String _weeklyNote(List<FeedItem> items) {
    final jobs = items.where((item) => item.topic == 'jobs').length;
    final exams = items.length - jobs;
    return [
      if (jobs > 0) '$jobs ${jobs == 1 ? 'vacancy' : 'vacancies'}',
      if (exams > 0) '$exams ${exams == 1 ? 'exam' : 'exams'}',
    ].join(', ');
  }

  /// The days a folded week's notices came out on.
  static String _span(List<FeedItem> items) {
    final today = DateTime.now();
    final newest = items.first.published;
    final oldest = items.last.published;
    return newest == oldest
        ? cardDate(newest, today: today)
        : '${cardDate(oldest, today: today)} to '
              '${cardDate(newest, today: today)}';
  }

  /// The rows as month headings and days.
  static List<_Block> _blocks(List<NoticeRow> rows) {
    final blocks = <_Block>[];
    for (final row in rows) {
      switch (row) {
        case MonthRow(:final month):
          blocks.add((month: month, day: null, rows: []));
        case DayRow(:final day):
          blocks.add((month: null, day: day, rows: []));
        default:
          blocks.last.rows.add(row);
      }
    }
    return blocks;
  }
}

/// Where the timeline's rail runs, from the left.
const _rail = 7.0;

/// The rail's width with the room after it.
const _gutter = 26.0;

/// A month on the timeline: its name, large, on the rail.
class _MonthMark extends StatelessWidget {
  const _MonthMark({required this.month, required this.first});

  final DateTime month;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        if (!first)
          Positioned(
            left: _rail,
            top: 0,
            bottom: 0,
            child: Container(width: 2, color: theme.colorScheme.outlineVariant),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(0, first ? 12 : 20, 0, 4),
          child: Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              monthHeading(month),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
      ],
    );
  }
}

/// A day on the timeline: a node on the rail with the day beside it, then
/// the day's rows in one group.
class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.rows,
    required this.isNew,
    required this.last,
  });

  final DateTime day;
  final List<Widget> rows;

  /// Something on the day arrived since the last visit.
  final bool isNew;

  /// The rail stops at the last day's node.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = DateTime.now();
    final date = DateTime(today.year, today.month, today.day);
    final label = switch (date.difference(day).inDays) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => weekdayDate(day),
    };
    return Stack(
      children: [
        Positioned(
          left: _rail,
          top: 0,
          bottom: last ? null : 0,
          height: last ? 22 : null,
          child: Container(width: 2, color: colors.outlineVariant),
        ),
        Positioned(
          left: _rail - 4,
          top: 17,
          child: _Node(isNew: isNew),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _gutter, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isNew ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ),
              ItemGroup(children: rows),
            ],
          ),
        ),
      ],
    );
  }
}

/// A day's node on the rail: teal and ringed when the day has something new.
class _Node extends StatelessWidget {
  const _Node({required this.isNew});

  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isNew ? colors.primary : colors.surface,
        border: Border.all(
          color: isNew ? colors.primary : colors.outline,
          width: 2,
        ),
        boxShadow: isNew
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Notices folded into one row: a weekly gazette (opens its page) or a week
/// of election notices (opens in place).
class _Fold extends StatelessWidget {
  const _Fold({
    required this.title,
    required this.note,
    required this.count,
    required this.isNew,
    required this.trailing,
    required this.onTap,
  });

  final String title;
  final String note;
  final int count;
  final bool isNew;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: isNew ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(note, style: muted),
                ],
              ),
            ),
            Text('$count', style: muted),
            const SizedBox(width: 2),
            Icon(trailing, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
