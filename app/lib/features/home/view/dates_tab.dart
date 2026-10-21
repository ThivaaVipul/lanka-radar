import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/calendar.dart';
import 'package:lanka_radar/core/data/dates_ahead.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/card_lines.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/outages.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/widgets/month_calendar.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/home/widgets/week_strip.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';

/// Dates: the load shedding ahead at the places watched, the school exams
/// ahead (their days read from the timetables), the weekly gazette's
/// applications still open, the long weekends and the year's remaining
/// holidays, each with a countdown and a way into the phone's calendar.
class DatesTab extends StatelessWidget {
  const DatesTab({this.addToCalendar = addToPhoneCalendar, super.key});

  final AddToCalendar addToCalendar;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        final now = state.nowCard;
        if (now == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final today = DateTime.now();
        final day = DateTime(today.year, today.month, today.day);
        final exams = upcomingExams(state.items ?? const <FeedItem>[], day);
        final closing = applicationsClosing(
          state.items ?? const <FeedItem>[],
          day,
        );
        final weekends = longWeekends(now.holidays, day);
        final cuts = cutsAhead(now.power);
        Future<void> add(CalendarEvent event) async {
          final messenger = ScaffoldMessenger.of(context);
          if (!await addToCalendar(event)) {
            messenger.showSnackBar(
              const SnackBar(content: Text('No calendar app found')),
            );
          }
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            MonthCalendar(
              today: day,
              events: dayEvents(
                holidays: now.holidays,
                exams: exams,
                closing: closing,
                cuts: cuts,
              ),
              weekends: weekends,
            ),
            const _Key(),
            if (cuts.isNotEmpty)
              Section(
                title: 'Power cuts ahead',
                children: [
                  for (final (place, cut) in cuts)
                    _DateRow(
                      first: cut.start,
                      last: cut.end,
                      today: day,
                      title: '${cut.name} at ${place.name}',
                      subtitle: [
                        cutHours(cut),
                        if (cut.group case final group?) 'group $group',
                      ].join(', '),
                      onAdd: () => add(
                        CalendarEvent(
                          title: '${cut.name} at ${place.name}',
                          first: cut.start,
                          last: cut.end,
                          description: switch (cut.group) {
                            final group? => 'Group $group',
                            null => null,
                          },
                          allDay: false,
                        ),
                      ),
                    ),
                ],
              ),
            if (exams.isNotEmpty)
              Section(
                title: 'Exams',
                children: [
                  for (final exam in exams)
                    _DateRow(
                      first: exam.first,
                      last: exam.last,
                      today: day,
                      title: exam.name,
                      subtitle: exam.days.length > 1
                          ? '${exam.days.length} days, to '
                                '${weekdayDate(exam.last)}'
                          : null,
                      onTap: () =>
                          Navigator.of(context).push(ItemPage.route(exam.item)),
                      onAdd: () => add(
                        CalendarEvent(
                          title: exam.name,
                          first: exam.first,
                          last: exam.last,
                          description: exam.item.headlineEn,
                        ),
                      ),
                    ),
                ],
              ),
            if (closing.isNotEmpty)
              Section(
                title: 'Applications closing',
                children: [
                  for (final item in closing)
                    _DateRow(
                      first: item.closes!,
                      last: item.closes!,
                      today: day,
                      title: cardTitle(item),
                      subtitle: item.issuer,
                      onTap: () =>
                          Navigator.of(context).push(ItemPage.route(item)),
                      onAdd: () => add(
                        CalendarEvent(
                          title: 'Applications close: ${cardTitle(item)}',
                          first: item.closes!,
                          last: item.closes!,
                          description: item.issuer,
                        ),
                      ),
                    ),
                ],
              ),
            if (weekends.isNotEmpty)
              Section(
                title: 'Long weekends',
                children: [
                  for (final weekend in weekends)
                    _DateRow(
                      first: weekend.first,
                      last: weekend.last,
                      today: day,
                      title:
                          '${weekend.length} days, to '
                          '${weekdayDate(weekend.last)}',
                      subtitle: [
                        for (final holiday in weekend.holidays) holiday.name,
                      ].join(dot),
                      tentative: weekend.tentative,
                      onAdd: () => add(
                        CalendarEvent(
                          title: 'Long weekend',
                          first: weekend.first,
                          last: weekend.last,
                          description: [
                            for (final holiday in weekend.holidays)
                              holiday.name,
                          ].join(', '),
                        ),
                      ),
                    ),
                ],
              ),
            Section(
              title: 'Holidays',
              children: [
                if (now.holidays.isEmpty)
                  const ListTile(title: Text('Not yet')),
                for (final holiday in now.holidays)
                  _DateRow(
                    first: holiday.day,
                    last: holiday.day,
                    today: day,
                    title: holiday.name,
                    subtitle: holiday.tamil,
                    tentative: holiday.tentative,
                    onAdd: () => add(
                      CalendarEvent(
                        title: holiday.name,
                        first: holiday.day,
                        last: holiday.day,
                        description: holiday.tamil,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// What the calendar's marks mean.
class _Key extends StatelessWidget {
  const _Key();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final (mark, label) in const [
            (DayMark.holiday, 'Holiday'),
            (DayMark.exam, 'Exam'),
            (DayMark.closing, 'Applications close'),
            (DayMark.cut, 'Power cut'),
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DayMarkDot(mark, size: 7),
                const SizedBox(width: 5),
                Text(label, style: style),
              ],
            ),
        ],
      ),
    );
  }
}

/// A day (or a run of days) led by its date, large, with what it is, its
/// countdown, and a button that adds it to the phone's calendar.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.first,
    required this.last,
    required this.today,
    required this.title,
    required this.onAdd,
    this.subtitle,
    this.tentative = false,
    this.onTap,
  });

  final DateTime first;
  final DateTime last;
  final DateTime today;
  final String title;
  final String? subtitle;

  /// The date isn't fixed yet.
  final bool tentative;
  final VoidCallback onAdd;
  final VoidCallback? onTap;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final day = DateTime(first.year, first.month, first.day);
    final lastDay = DateTime(last.year, last.month, last.day);
    // Only a run of days is "on now"; a day is "today".
    final going =
        lastDay != day && !today.isBefore(day) && !today.isAfter(lastDay);
    final soon = going || day == today;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: soon
                    ? colors.primaryContainer
                    : colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${first.day}',
                    style: bigNumber(
                      context,
                      size: 20,
                    ).copyWith(color: soon ? colors.onPrimaryContainer : null),
                  ),
                  Text(
                    _months[first.month - 1],
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: soon
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tentative ? '$title (tentative)' : title,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle case final subtitle? when subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    going ? 'on now' : inDays(first, today: today),
                    style: muted?.copyWith(color: soon ? colors.primary : null),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onAdd,
              tooltip: 'Add to calendar',
              icon: Icon(
                Icons.edit_calendar_outlined,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
