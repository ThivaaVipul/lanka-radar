import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';

/// Prices: CEYPETCO's fuel prices, USD/LKR, Litro's LP gas list and the latest
/// price orders.
class PricesTab extends StatelessWidget {
  const PricesTab({this.open = openExternally, super.key});

  /// How many recent price orders are listed.
  static const orders = 5;

  final OpenLink open;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        final now = state.nowCard;
        if (now == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final today = DateTime.now();
        final rates = now.rates;
        final gas = now.gas;
        final priceOrders = [
          for (final item in state.items ?? const <FeedItem>[])
            if (item.topic == 'prices' && item.source != 'gas') item,
        ].take(orders);
        return RefreshIndicator(
          onRefresh: context.read<HomeCubit>().refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Section(
                title: 'Fuel',
                note: now.fuelFromGazette
                    ? fuelNote(now, today: today)
                    : 'CEYPETCO, ${fuelNote(now, today: today)}',
                children: [
                  if (now.fuel.isEmpty) const ListTile(title: Text('Not yet')),
                  for (final price in now.fuel)
                    _PriceRow(
                      name: price.name,
                      value: price.price,
                      before: price.was,
                      note: 'since ${cardDate(price.since, today: today)}',
                    ),
                ],
              ),
              Section(
                title: 'USD/LKR',
                note: now.ratesFromBackup
                    ? 'backup copy'
                    : 'Central Bank of Sri Lanka',
                children: [
                  if (rates.isEmpty) const ListTile(title: Text('Not yet')),
                  if (rates.isNotEmpty) _RateNow(rates: rates),
                  for (final rate in rates.skip(1).take(6))
                    _PriceRow(
                      name: weekdayDate(rate.day),
                      value: rate.rate,
                      quiet: true,
                    ),
                ],
              ),
              Section(
                title: 'LP gas',
                children: [
                  ListTile(
                    title: const Text('Litro price list'),
                    subtitle: gas == null
                        ? const Text('Not yet')
                        : Text(
                            'from '
                            '${cardDate(gas.effective ?? gas.published, today: today)}',
                          ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: gas?.links['image'] == null
                        ? null
                        : () => open(Uri.parse(gas!.links['image']!)),
                  ),
                ],
              ),
              if (priceOrders.isNotEmpty)
                Section(
                  title: 'Price orders',
                  card: false,
                  children: [
                    ItemGroup(
                      children: [
                        for (final item in priceOrders)
                          ItemTile(
                            item: item,
                            isNew: state.isNew(item),
                            onTap: () => Navigator.of(
                              context,
                            ).push(ItemPage.route(item)),
                          ),
                      ],
                    ),
                  ],
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => open(Uri.parse(Ceypetco.page)),
                  child: const Text('CEYPETCO prices'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A name and its price, with which way it moved since [before].
class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.name,
    required this.value,
    this.before,
    this.note,
    this.quiet = false,
  });

  final String name;
  final double value;
  final double? before;
  final String? note;

  /// A plain row, such as an earlier day's rate.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final before = this.before;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: quiet
                      ? theme.textTheme.bodyMedium
                      : theme.textTheme.bodyLarge,
                ),
                if (note case final note?) Text(note, style: muted),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount(value),
                style: quiet
                    ? theme.textTheme.bodyMedium
                    : theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
              ),
              if (before != null && before != value)
                Trend(change: value - before, text: 'was ${amount(before)}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Today's rate, large, with the week's move.
class _RateNow extends StatelessWidget {
  const _RateNow({required this.rates});

  final List<RateNow> rates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = rates.first;
    final move = weekMove(rates);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amount(latest.rate),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  weekdayDate(latest.day),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (move != null)
            Trend(
              change: move,
              text: '${move.abs().toStringAsFixed(1)}% in a week',
            ),
        ],
      ),
    );
  }
}
