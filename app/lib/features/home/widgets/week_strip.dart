import 'package:flutter/material.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/dates_ahead.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// A day's marker: a dot in the day's colour, a bolt for a power cut.
class DayMarkDot extends StatelessWidget {
  const DayMarkDot(this.mark, {this.size = 6, super.key});

  final DayMark mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (mark == DayMark.cut) {
      return Icon(Icons.bolt, size: size * 2.2, color: colors.tertiary);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: markColor(context, mark),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// The colour that marks [mark] on a calendar.
Color markColor(BuildContext context, DayMark mark) {
  final marks = Marks.of(context);
  return switch (mark) {
    DayMark.holiday => marks.holiday,
    DayMark.exam => marks.exam,
    DayMark.closing => marks.closing,
    DayMark.cut => Theme.of(context).colorScheme.tertiary,
  };
}

/// The next seven days, each with its markers, and under them what the
/// markers are: holidays, exams, closing dates and power cuts this week.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    required this.today,
    required this.events,
    this.onDay,
    super.key,
  });

  /// Midnight today.
  final DateTime today;
  final Map<DateTime, List<DayEvent>> events;
  final ValueChanged<DateTime>? onDay;

  /// Lines under the strip, at most.
  static const lines = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final days = [
      for (var index = 0; index < 7; index++)
        DateTime(today.year, today.month, today.day + index),
    ];
    final week = [
      for (final day in days)
        if (_summary(events[day]) case final summary when summary.isNotEmpty)
          for (final event in summary) (day, event),
    ];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final day in days)
                  Expanded(
                    child: _Day(
                      day: day,
                      today: day == today,
                      off:
                          day.weekday >= DateTime.saturday ||
                          (events[day]?.any(
                                (event) => event.mark == DayMark.holiday,
                              ) ??
                              false),
                      marks: {
                        for (final event in events[day] ?? const <DayEvent>[])
                          event.mark,
                      },
                      onTap: onDay == null ? null : () => onDay!(day),
                    ),
                  ),
              ],
            ),
            if (week.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Divider(height: 1, color: colors.outlineVariant),
              ),
              for (final (day, event) in week.take(lines))
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        child: Center(child: DayMarkDot(event.mark, size: 7)),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 56,
                        child: Text(
                          day == today
                              ? 'Today'
                              : weekdayDate(day).split(' ').take(2).join(' '),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
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
              if (week.length > lines)
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 2, 8, 6),
                  child: Text(
                    '${week.length - lines} more',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// A day's events as lines: closing dates counted into one.
  static List<DayEvent> _summary(List<DayEvent>? events) {
    if (events == null) {
      return const [];
    }
    final closing = events.where((event) => event.mark == DayMark.closing);
    return [
      for (final event in events)
        if (event.mark != DayMark.closing) event,
      if (closing.isNotEmpty)
        (
          mark: DayMark.closing,
          name: closing.length == 1
              ? 'An application closes'
              : '${closing.length} applications close',
        ),
    ]..sort((a, b) => a.mark.index.compareTo(b.mark.index));
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.today,
    required this.off,
    required this.marks,
    this.onTap,
  });

  final DateTime day;
  final bool today;

  /// A weekend or a holiday.
  final bool off;
  final Set<DayMark> marks;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final weekday = weekdayDate(day).substring(0, 3);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Text(
              weekday,
              style: theme.textTheme.labelSmall?.copyWith(
                color: off ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: today ? colors.primary : null,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: today ? colors.onPrimary : colors.onSurface,
                  fontFeatures: tabular,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final (index, mark)
                      in (marks.toList()
                            ..sort((a, b) => a.index.compareTo(b.index)))
                          .indexed) ...[
                    if (index > 0) const SizedBox(width: 3),
                    DayMarkDot(mark),
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
