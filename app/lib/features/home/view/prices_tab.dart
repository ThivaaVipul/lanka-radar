import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/share.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/gas_prices.dart';
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
            if (item.topic == 'prices' && !isGasList(item)) item,
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
              _GasSection(
                gas: gas,
                litro: gasPrices(
                  state.items ?? const <FeedItem>[],
                  state.gasDistrict,
                ),
                laugfs: now.laugfs?.at(state.gasDistrict),
                district: state.gasDistrict,
                today: today,
                open: open,
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

/// LP gas prices in the district picked (picked across from the title): a card
/// for each company, Litro's and Laugfs's, with its sizes against the prices
/// before; a tap on a card opens the company's own price list.
class _GasSection extends StatelessWidget {
  const _GasSection({
    required this.gas,
    required this.litro,
    required this.laugfs,
    required this.district,
    required this.today,
    required this.open,
  });

  /// Litro's latest list, read or not.
  final FeedItem? gas;
  final GasPrices? litro;
  final GasPrices? laugfs;
  final String district;
  final DateTime today;
  final OpenLink open;

  @override
  Widget build(BuildContext context) {
    final gas = this.gas;
    final image = gas?.links['image'];
    return Section(
      title: 'LP gas',
      card: false,
      action: _DistrictButton(district: district, onTap: () => _pick(context)),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _GasCard(
                  name: 'Litro',
                  since: gas == null ? null : gas.effective ?? gas.published,
                  prices: litro?.prices,
                  today: today,
                  onTap: image == null ? null : () => open(Uri.parse(image)),
                  onLongPress: gas == null
                      ? null
                      : () => shareText(context, noticeShare(gas)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GasCard(
                  name: 'Laugfs',
                  since: laugfs?.since,
                  prices: laugfs?.prices,
                  today: today,
                  onTap: () => open(Uri.parse(laugfsPage)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<HomeCubit>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            for (final name in gasDistricts)
              ListTile(
                title: Text(name),
                trailing: name == district ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(name),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != district) {
      await cubit.setGasDistrict(picked);
    }
  }
}

/// The district LP gas prices are shown for; a tap picks another.
class _DistrictButton extends StatelessWidget {
  const _DistrictButton({required this.district, required this.onTap});

  final String district;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.place_outlined, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              district,
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
            Icon(Icons.expand_more, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

/// One LP gas company's prices: its name and when they started over its sizes,
/// each against the price before. A tap opens the company's own price list.
class _GasCard extends StatelessWidget {
  const _GasCard({
    required this.name,
    required this.since,
    required this.prices,
    required this.today,
    required this.onTap,
    this.onLongPress,
  });

  final String name;
  final DateTime? since;

  /// Null until the company's prices have been read.
  final List<GasPrice>? prices;
  final DateTime today;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final since = this.since;
    final prices = this.prices;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name, style: theme.textTheme.titleSmall),
                  ),
                  if (onTap != null)
                    Icon(Icons.open_in_new, size: 16, color: muted),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                since == null ? ' ' : cardDate(since, today: today),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 8),
              if (prices == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Not yet',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                )
              else
                for (final price in prices)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          price.size,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              amount(price.price),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (price.before case final before?
                                when before != price.price)
                              Trend(
                                change: price.price - before,
                                text: 'was ${amount(before)}',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
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
