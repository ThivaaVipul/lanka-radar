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
import 'package:lanka_radar/features/home/widgets/cut_tile.dart';
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
                    time: clock(next.start.hour * 60 + next.start.minute),
                    rest: 'to ${clock(next.end.hour * 60 + next.end.minute)}',
                    start: next.start,
                    end: next.end,
                    onTap: () => open(HomeTab.power),
                  ),
                ),
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

/// A cut on now at a place, as an ochre tile: a cut from its account's
/// calendar with its hours and how long is left, a breakdown since when.
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
