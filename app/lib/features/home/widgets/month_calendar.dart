import 'package:flutter/material.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/dates_ahead.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/home/widgets/week_strip.dart';

/// This month and the next ones, swiped through: each day with its markers,
/// the long weekends as a band behind their days, and under the grid what
/// the day picked holds.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    required this.today,
    required this.events,
    required this.weekends,
    this.months = 3,
    super.key,
  });

  /// Midnight today.
  final DateTime today;
  final Map<DateTime, List<DayEvent>> events;
  final List<LongWeekend> weekends;
  final int months;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  final _pages = PageController();
  late DateTime _picked = widget.today;
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  DateTime _month(int index) =>
      DateTime(widget.today.year, widget.today.month + index);

  /// The rows of weeks a month needs.
  static int _weeks(DateTime month) {
    final lead = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return ((lead + days) / 7).ceil();
  }

  Future<void> _turn(int by) => _pages.animateToPage(
    _page + by,
    duration: Motion.of(context, Motion.medium),
    curve: Motion.standard,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final month = _month(_page);
    final picked = widget.events[_picked] ?? const <DayEvent>[];
    final off = {
      for (final weekend in widget.weekends)
        for (
          var day = weekend.first;
          !day.isAfter(weekend.last);
          day = DateTime(day.year, day.month, day.day + 1)
        )
          day,
    };
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 6),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.medium),
                    transitionBuilder: fadeRise,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [...previous, ?current],
                    ),
                    child: Text(
                      monthHeading(month),
                      key: ValueKey(month),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Month before',
                  onPressed: _page == 0 ? null : () => _turn(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _page == widget.months - 1 ? null : () => _turn(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final (index, day) in const [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun',
                ].indexed)
                  Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: index >= 5
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            AnimatedSize(
              duration: Motion.of(context, Motion.medium),
              curve: Motion.standard,
              child: SizedBox(
                height: _weeks(month) * _DayCell.height,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: widget.months,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) => _Grid(
                    month: _month(index),
                    today: widget.today,
                    picked: _picked,
                    events: widget.events,
                    off: off,
                    onPick: (day) => setState(() => _picked = day),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
              child: Divider(height: 1, color: colors.outlineVariant),
            ),
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.medium),
              transitionBuilder: fadeRise,
              child: Padding(
                key: ValueKey(_picked),
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _picked == widget.today
                          ? 'Today, ${weekdayDate(_picked)}'
                          : weekdayDate(_picked),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    if (picked.isEmpty)
                      Text(
                        off.contains(_picked) ? 'Day off' : 'Nothing on',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    for (final event in picked)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              child: Center(
                                child: DayMarkDot(event.mark, size: 7),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                event.name,
                                style: theme.textTheme.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.month,
    required this.today,
    required this.picked,
    required this.events,
    required this.off,
    required this.onPick,
  });

  final DateTime month;
  final DateTime today;
  final DateTime picked;
  final Map<DateTime, List<DayEvent>> events;

  /// The days of the long weekends.
  final Set<DateTime> off;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final lead = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final weeks = ((lead + days) / 7).ceil();
    // A month with more weeks than the one before is cut, not overflowed,
    // while the grid grows to it.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          for (var week = 0; week < weeks; week++)
            Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: switch (week * 7 + column - lead + 1) {
                      final date when date >= 1 && date <= days => _DayCell(
                        day: DateTime(month.year, month.month, date),
                        today: today,
                        picked: picked,
                        events: events,
                        off: off,
                        onPick: onPick,
                      ),
                      _ => const SizedBox(height: _DayCell.height),
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.picked,
    required this.events,
    required this.off,
    required this.onPick,
  });

  static const height = 50.0;

  final DateTime day;
  final DateTime today;
  final DateTime picked;
  final Map<DateTime, List<DayEvent>> events;
  final Set<DateTime> off;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final marks = Marks.of(context);
    final mine = events[day] ?? const <DayEvent>[];
    final kinds = {for (final event in mine) event.mark}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final holiday = kinds.contains(DayMark.holiday);
    final past = day.isBefore(today);
    final isToday = day == today;
    final isPicked = day == picked;
    final before = DateTime(day.year, day.month, day.day - 1);
    final after = DateTime(day.year, day.month, day.day + 1);
    final band = off.contains(day);
    final bandColor = marks.holiday.withValues(alpha: 0.16);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(day),
      child: SizedBox(
        height: height,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // A long weekend's band runs behind its days, rounded at its ends
            // and at the ends of a row.
            if (band)
              Positioned(
                top: 5,
                height: 32,
                left: off.contains(before) && day.weekday != DateTime.monday
                    ? 0
                    : 4,
                right: off.contains(after) && day.weekday != DateTime.sunday
                    ? 0
                    : 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: bandColor,
                    borderRadius: BorderRadius.horizontal(
                      left:
                          off.contains(before) && day.weekday != DateTime.monday
                          ? Radius.zero
                          : const Radius.circular(16),
                      right:
                          off.contains(after) && day.weekday != DateTime.sunday
                          ? Radius.zero
                          : const Radius.circular(16),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 5,
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.short),
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday
                      ? colors.primary
                      : holiday
                      ? marks.holiday.withValues(alpha: 0.28)
                      : null,
                  border: isPicked && !isToday
                      ? Border.all(color: colors.primary, width: 2)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isToday || holiday
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontFeatures: tabular,
                    color: isToday
                        ? colors.onPrimary
                        : past
                        ? colors.onSurfaceVariant.withValues(alpha: 0.55)
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, kind) in kinds.indexed)
                    if (kind != DayMark.holiday) ...[
                      if (index > 0 && kinds[index - 1] != DayMark.holiday)
                        const SizedBox(width: 3),
                      DayMarkDot(kind, size: 5),
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
