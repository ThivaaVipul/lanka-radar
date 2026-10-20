import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/share.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/market_prices.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/format/share_texts.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/prices/cubit/price_chart_cubit.dart';
import 'package:lanka_radar/features/prices/view/price_chart_page.dart';

/// Prices: CEYPETCO's fuel prices, USD/LKR, the Central Bank's market prices,
/// Litro's LP gas list and the latest price orders.
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
        final goods = goodsHistory(state.items ?? const <FeedItem>[]);
        final setBy = goodsOrders(state.items ?? const <FeedItem>[]);
        void chart(ChartSubject subject) =>
            Navigator.of(context).push(PriceChartPage.route(subject));
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
                      share: fuelShare(
                        price,
                        asOf: now.fuelAsOf ?? today,
                        fromGazette: now.fuelFromGazette,
                      ),
                      onTap: () => chart(FuelChart(price.name)),
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
                  if (rates.isNotEmpty)
                    _RateNow(
                      rates: rates,
                      share: rateShare(rates, backup: now.ratesFromBackup),
                      onTap: () => chart(const RateChart()),
                    ),
                  for (final rate in rates.skip(1).take(4))
                    _PriceRow(
                      name: weekdayDate(rate.day),
                      value: rate.rate,
                      quiet: true,
                      onTap: () => chart(const RateChart()),
                    ),
                ],
              ),
              if (now.market.quotes.isNotEmpty)
                _MarketSection(
                  market: now.market,
                  today: today,
                  onChart: (name) => chart(MarketChart(name)),
                ),
              if (goods.isNotEmpty)
                Section(
                  title: 'Controlled prices',
                  note: 'maximum retail',
                  children: [
                    for (final MapEntry(key: name, value: history)
                        in goods.entries)
                      _PriceRow(
                        name: name,
                        value: history.last.value,
                        before: history.length > 1
                            ? history[history.length - 2].value
                            : null,
                        note:
                            'since ${cardDate(history.last.day, today: today)}',
                        share: switch (setBy[name]) {
                          final order? => goodShare(name, history, order),
                          null => null,
                        },
                        onTap: () => chart(GoodChart(name)),
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
                    onLongPress: gas == null
                        ? null
                        : () => shareText(context, noticeShare(gas)),
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

/// The Central Bank's daily retail prices, a section of the report at a time.
class _MarketSection extends StatefulWidget {
  const _MarketSection({
    required this.market,
    required this.today,
    required this.onChart,
  });

  final MarketPrices market;
  final DateTime today;
  final ValueChanged<String> onChart;

  @override
  State<_MarketSection> createState() => _MarketSectionState();
}

class _MarketSectionState extends State<_MarketSection> {
  String _section = marketSections.first;

  @override
  Widget build(BuildContext context) {
    final quotes = widget.market.quotes;
    final sections = [
      for (final section in marketSections)
        if (quotes.any((quote) => quote.good.section == section)) section,
    ];
    final shown = sections.contains(_section) ? _section : sections.first;
    return Section(
      title: 'Market',
      note:
          '${marketOrder.first}, '
          '${cardDate(widget.market.latest!, today: widget.today)}',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              for (final section in sections) ...[
                if (section != sections.first) const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(section),
                  selected: section == shown,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _section = section),
                ),
              ],
            ],
          ),
        ),
        for (final quote in quotes)
          if (quote.good.section == shown)
            _PriceRow(
              name: quote.good.name,
              value: quote.price,
              before: quote.before,
              note: [
                quote.good.perUnit,
                if (quote.market != marketOrder.first) quote.market,
              ].join(dot),
              share: marketShare(quote, day: widget.market.latest!),
              onTap: () => widget.onChart(quote.good.name),
            ),
      ],
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
    this.share,
    this.onTap,
  });

  final String name;
  final double value;
  final double? before;
  final String? note;

  /// What a long press shares.
  final String? share;

  /// Opens the chart.
  final VoidCallback? onTap;

  /// A plain row, such as an earlier day's rate.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final before = this.before;
    final share = this.share;
    return InkWell(
      onTap: onTap,
      onLongPress: share == null ? null : () => shareText(context, share),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
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
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Today's rate, large, with the week's move.
class _RateNow extends StatelessWidget {
  const _RateNow({required this.rates, required this.share, this.onTap});

  final List<RateNow> rates;

  /// What a long press shares.
  final String share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = rates.first;
    final move = weekMove(rates);
    return InkWell(
      onTap: onTap,
      onLongPress: () => shareText(context, share),
      child: Padding(
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
      ),
    );
  }
}
