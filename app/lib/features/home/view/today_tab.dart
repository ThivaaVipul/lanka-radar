import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/app/segments.dart';
import 'package:lanka_radar/app/share.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/app/viz/marks.dart';
import 'package:lanka_radar/app/viz/press.dart';
import 'package:lanka_radar/app/viz/sparkline.dart';
import 'package:lanka_radar/core/data/dates_ahead.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/format/outages.dart';
import 'package:lanka_radar/core/format/share_texts.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/widgets/cut_tile.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/home/widgets/week_strip.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';

/// Today: the power cut at a place watched, if one is due or on; the pulse
/// (fuel, the rupee and the next holiday, each with its history); the week
/// ahead; then what is new since the last visit (or the latest few), never
/// election notices.
class TodayTab extends StatelessWidget {
  const TodayTab({required this.open, super.key});

  /// Switches to another tab.
  final ValueChanged<HomeTab> open;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        final items = state.items;
        if (items == null || (items.isEmpty && state.refreshing)) {
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty) {
          return state.failed
              ? const LoadFailed()
              : const Center(child: Text('Nothing yet'));
        }
        final now = state.nowCard;
        final clock = DateTime.now();
        final today = DateTime(clock.year, clock.month, clock.day);
        final fresh = state.todayItems;
        return RefreshIndicator(
          onRefresh: context.read<HomeCubit>().refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final cuts in now?.power?.cut ?? const <PlaceCuts>[])
                _CutNow(
                  cuts: cuts,
                  checked: now?.power?.checked,
                  onTap: () => open(HomeTab.power),
                ),
              if (cutsAhead(
                    now?.power,
                    before: DateTime(today.year, today.month, today.day + 2),
                  ).firstOrNull
                  case (final place, final next))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CutTile(
                    title: '${next.name} at ${place.name}',
                    time: _at(next.start),
                    rest: 'to ${_at(next.end)}',
                    start: next.start,
                    end: next.end,
                    onTap: () => open(HomeTab.power),
                  ),
                ),
              if (now != null) _Pulse(now: now, today: today, open: open),
              if (now != null)
                Section(
                  title: 'This week',
                  card: false,
                  children: [
                    WeekStrip(
                      today: today,
                      events: dayEvents(
                        holidays: now.holidays,
                        exams: upcomingExams(items, today),
                        closing: applicationsClosing(items, today),
                        cuts: cutsAhead(now.power),
                      ),
                      onDay: (_) => open(HomeTab.dates),
                    ),
                  ],
                ),
              Section(
                title: state.todayHasNew ? 'New' : 'Latest',
                note: state.todayHasNew ? '${fresh.length}' : null,
                card: false,
                children: [
                  ItemGroup(
                    children: [
                      for (final item in fresh)
                        ItemTile(
                          item: item,
                          isNew: state.isNew(item),
                          onTap: () =>
                              Navigator.of(context).push(ItemPage.route(item)),
                        ),
                    ],
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => open(HomeTab.notices),
                  child: const Text('All notices'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _at(DateTime time) => clock(time.hour * 60 + time.minute);
}

/// Petrol 92, Diesel, USD/LKR and the next holiday, in one block two by two:
/// each number over its history, the holiday in a ring that fills as it
/// nears.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.now, required this.today, required this.open});

  final NowData now;
  final DateTime today;
  final ValueChanged<HomeTab> open;

  @override
  Widget build(BuildContext context) {
    FuelNow? fuel(String name) =>
        now.fuel.where((price) => price.name == name).firstOrNull;
    Widget fuelCell(String name, int column) {
      final price = fuel(name);
      final was = price?.was;
      return _Cell(
        shape: gridSegmentShape(0, column, 2, 2),
        label: name,
        value: price == null ? '-' : amount(price.price),
        trend: price == null || was == null
            ? null
            : Trend(
                change: price.price - was,
                text: amount((price.price - was).abs()),
              ),
        chart: Sparkline(
          points: _thisYear(now.fuelHistories[name] ?? const []),
          steps: true,
          until: today,
        ),
        onTap: () => open(HomeTab.prices),
        onLongPress: price == null
            ? null
            : () => shareText(
                context,
                fuelShare(
                  price,
                  asOf: now.fuelAsOf ?? today,
                  fromGazette: now.fuelFromGazette,
                ),
              ),
      );
    }

    final rate = now.rates.firstOrNull;
    final move = weekMove(now.rates);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: fuelCell('Petrol 92', 0)),
              const SizedBox(width: 3),
              Expanded(child: fuelCell('Diesel', 1)),
            ],
          ),
          const SizedBox(height: 3),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Cell(
                    shape: gridSegmentShape(1, 0, 2, 2),
                    label: 'USD/LKR',
                    value: rate == null ? '-' : amount(rate.rate),
                    trend: move == null
                        ? null
                        : Trend(
                            change: move,
                            text: '${move.abs().toStringAsFixed(1)}%',
                          ),
                    chart: Sparkline(
                      points: [
                        for (final rate in now.rates.reversed)
                          PricePoint(rate.day, rate.rate),
                      ],
                      area: true,
                    ),
                    onTap: () => open(HomeTab.prices),
                    onLongPress: rate == null
                        ? null
                        : () => shareText(
                            context,
                            rateShare(now.rates, backup: now.ratesFromBackup),
                          ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: _HolidayCell(
                    holiday: now.holidays.firstOrNull,
                    today: today,
                    onTap: () => open(HomeTab.dates),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A year of steps is enough to see the trend.
  List<PricePoint> _thisYear(List<PricePoint> points) =>
      since(points, DateTime(today.year - 1, today.month, today.day));
}

/// One segment of the pulse: what, the number large with its change, and its
/// history under it.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.shape,
    required this.label,
    required this.value,
    required this.chart,
    this.trend,
    this.onTap,
    this.onLongPress,
  });

  final ShapeBorder shape;
  final String label;
  final String value;
  final Widget? trend;
  final Widget chart;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Press(
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: bigNumber(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (trend case final trend?) ...[
                      const SizedBox(width: 8),
                      trend,
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                chart,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The next holiday: its name, its day, and a ring of the days left that
/// fills over the last month before it.
class _HolidayCell extends StatelessWidget {
  const _HolidayCell({
    required this.holiday,
    required this.today,
    required this.onTap,
  });

  final HolidayNow? holiday;
  final DateTime today;
  final VoidCallback onTap;

  /// The ring is empty this many days before a holiday.
  static const span = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final holiday = this.holiday;
    final days = holiday == null
        ? null
        : DateTime.utc(
            holiday.day.year,
            holiday.day.month,
            holiday.day.day,
          ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    return Press(
      child: Material(
        color: colors.surfaceContainerLowest,
        shape: gridSegmentShape(1, 1, 2, 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Next holiday',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (days != null)
                      CountdownRing(
                        progress: 1 - days / span,
                        size: 46,
                        color: Marks.of(context).holiday,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              days == 0 ? 'Now' : '$days',
                              style: bigNumber(context, size: 17),
                            ),
                            if (days > 0)
                              Text(
                                days == 1 ? 'day' : 'days',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9,
                                  height: 1,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  holiday?.name ?? '-',
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (holiday != null)
                  Text(
                    weekdayDate(holiday.day),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A cut on now at a place, as an ochre tile: load shedding with its hours
/// and how long is left, a breakdown since when.
class _CutNow extends StatelessWidget {
  const _CutNow({
    required this.cuts,
    required this.checked,
    required this.onTap,
  });

  final PlaceCuts cuts;
  final DateTime? checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final place = cuts.place;
    final outages = cuts.outages;
    final first = outages.first;
    final from = first.from;
    final until = first.kind == OutageKind.maintenance ? first.time : null;
    String at(DateTime time) => clock(time.hour * 60 + time.minute);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CutTile(
        on: true,
        title: outages.length == 1 && from != null && first.reason != null
            ? '${first.reason} at ${place.name}'
            : powerCutsTitle(outages.length, place.name),
        time: from != null && until != null
            ? at(from)
            : outageWhen(first) ?? 'Now',
        rest: from != null && until != null ? 'to ${at(until)}' : null,
        start: until == null ? null : from,
        end: until,
        onTap: onTap,
        onLongPress: () => shareText(context, cutShare(cuts, checked: checked)),
      ),
    );
  }
}

class LoadFailed extends StatelessWidget {
  const LoadFailed({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text("Couldn't load the feed", style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: context.read<HomeCubit>().refresh,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
