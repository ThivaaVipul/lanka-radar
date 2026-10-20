import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/app/share.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/format/outages.dart';
import 'package:lanka_radar/core/format/share_texts.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';

/// Today: the power cuts at a place watched, if any, the numbers that matter
/// at a glance, then what is new since the last visit (or the latest few),
/// never election notices.
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
        final today = DateTime.now();
        return RefreshIndicator(
          onRefresh: context.read<HomeCubit>().refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final cuts in now?.power?.cut ?? const <PlaceCuts>[])
                _PowerCut(
                  cuts: cuts,
                  checked: now?.power?.checked,
                  onTap: () => open(HomeTab.power),
                ),
              if (cutsAhead(
                    now?.power,
                    before: DateTime(today.year, today.month, today.day + 2),
                  )
                  case final soon when soon.isNotEmpty)
                _CutsAhead(cuts: soon, onTap: () => open(HomeTab.power)),
              if (now != null) _Numbers(now: now, open: open),
              Section(
                title: state.todayHasNew
                    ? 'New since your last visit'
                    : 'Latest',
                card: false,
                children: [
                  ItemGroup(
                    children: [
                      for (final item in state.todayItems)
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
}

/// Petrol 92, Diesel, USD/LKR and the next holiday, two by two.
class _Numbers extends StatelessWidget {
  const _Numbers({required this.now, required this.open});

  final NowData now;
  final ValueChanged<HomeTab> open;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    FuelNow? fuel(String name) =>
        now.fuel.where((price) => price.name == name).firstOrNull;
    Widget fuelTile(String name) {
      final price = fuel(name);
      final was = price?.was;
      return NumberTile(
        label: name,
        value: price == null ? '-' : amount(price.price),
        trend: price == null || was == null
            ? null
            : Trend(
                change: price.price - was,
                text: amount((price.price - was).abs()),
              ),
        note: price == null
            ? null
            : 'since ${cardDate(price.since, today: today)}',
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
    final holiday = now.holidays.firstOrNull;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: fuelTile('Petrol 92')),
            const SizedBox(width: 8),
            Expanded(child: fuelTile('Diesel')),
          ],
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: NumberTile(
                  label: 'USD/LKR',
                  value: rate == null ? '-' : amount(rate.rate),
                  trend: move == null
                      ? null
                      : Trend(
                          change: move,
                          text: '${move.abs().toStringAsFixed(1)}%',
                        ),
                  note: move == null ? null : 'in a week',
                  onTap: () => open(HomeTab.prices),
                  onLongPress: rate == null
                      ? null
                      : () => shareText(
                          context,
                          rateShare(now.rates, backup: now.ratesFromBackup),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberTile(
                  label: 'Next holiday',
                  value: holiday?.name ?? '-',
                  valueLines: 2,
                  note: holiday == null
                      ? null
                      : '${weekdayDate(holiday.day)}, '
                            '${inDays(holiday.day, today: today)}',
                  onTap: () => open(HomeTab.dates),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The power cuts at a place: what each is and when.
class _PowerCut extends StatelessWidget {
  const _PowerCut({
    required this.cuts,
    required this.checked,
    required this.onTap,
  });

  /// How many cuts are listed.
  static const shown = 3;

  final PlaceCuts cuts;
  final DateTime? checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final checked = this.checked;
    final place = cuts.place;
    final ink = colors.onTertiaryContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: () =>
              shareText(context, cutShare(cuts, checked: this.checked)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.tertiary,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.flash_off_rounded,
                      size: 22,
                      color: colors.onTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        powerCutsTitle(cuts.outages.length, place.name),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final outage in cuts.outages.take(shown))
                        Text(
                          outageLine(outage),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ink,
                          ),
                        ),
                      if (checked != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${place.area!.name}, checked '
                          '${dayTime(checked, today: DateTime.now())}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: ink.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The cuts due today and tomorrow, in one quiet card: what and where once,
/// then a line for each, day and hours.
class _CutsAhead extends StatelessWidget {
  const _CutsAhead({required this.cuts, required this.onTap});

  final List<(Place, AccountCut)> cuts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final now = DateTime.now();
    String what((Place, AccountCut) entry) =>
        '${entry.$2.name} at ${entry.$1.name}';
    // One heading when every cut is the same thing at the same place.
    final same = cuts.every((entry) => what(entry) == what(cuts.first));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule, size: 20, color: colors.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        same ? what(cuts.first) : 'Power cuts ahead',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      for (final entry in cuts)
                        Text(
                          [
                            cutTimes(entry.$2, now: now),
                            if (!same) what(entry),
                          ].join(', '),
                          style: muted,
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
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
