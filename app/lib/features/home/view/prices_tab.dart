import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/app/share.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/app/viz/marks.dart';
import 'package:lanka_radar/app/viz/sparkline.dart';
import 'package:lanka_radar/app/viz/underline_tabs.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/gas_prices.dart';
import 'package:lanka_radar/core/data/harti_bulletin.dart';
import 'package:lanka_radar/core/data/market_prices.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/data/wholesale_prices.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/format/share_texts.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/prices/cubit/price_chart_cubit.dart';
import 'package:lanka_radar/features/prices/view/price_chart_page.dart';
import 'package:lanka_radar/features/prices/widgets/price_chart.dart';

/// Prices: fuel, USD/LKR, LP gas, the Central Bank's market prices, HARTI's
/// wholesale prices and the controlled prices, with a row of their names
/// pinned on top that jumps to each and follows the scroll.
class PricesTab extends StatefulWidget {
  const PricesTab({this.open = openExternally, super.key});

  /// How many recent price orders are listed.
  static const orders = 5;

  /// The sections, in the order they come.
  static const sections = [
    'Fuel',
    'USD/LKR',
    'LP gas',
    'Market',
    'Wholesale',
    'Controlled',
  ];

  final OpenLink open;

  @override
  State<PricesTab> createState() => _PricesTabState();
}

class _PricesTabState extends State<PricesTab> {
  final _scroll = ScrollController();
  final _view = GlobalKey();
  final _keys = [for (final _ in PricesTab.sections) GlobalKey()];
  int _shown = 0;

  /// Scrolling to a section the user picked: the bar keeps their pick.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_follow);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Picks the section at the top of the screen.
  void _follow() {
    final view = _view.currentContext?.findRenderObject() as RenderBox?;
    if (_jumping || view == null) {
      return;
    }
    var shown = 0;
    for (final (index, key) in _keys.indexed) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          box.localToGlobal(Offset.zero, ancestor: view).dy <= 96) {
        shown = index;
      }
    }
    if (_scroll.position.extentAfter < 8) {
      shown = _keys.length - 1;
    }
    if (shown != _shown) {
      setState(() => _shown = shown);
    }
  }

  Future<void> _jump(int index) async {
    final target = _keys[index].currentContext;
    if (target == null) {
      return;
    }
    setState(() {
      _shown = index;
      _jumping = true;
    });
    await Scrollable.ensureVisible(
      target,
      duration: Motion.of(context, Motion.long),
      curve: Motion.standard,
    );
    _jumping = false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        final now = state.nowCard;
        if (now == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final today = DateTime.now();
        final items = state.items ?? const <FeedItem>[];
        final priceOrders = [
          for (final item in items)
            if (item.topic == 'prices' && !isGasList(item)) item,
        ].take(PricesTab.orders);
        final goods = goodsHistory(items);
        final setBy = goodsOrders(items);
        void chart(ChartSubject subject) =>
            Navigator.of(context).push(PriceChartPage.route(subject));
        Widget keyed(int index, Widget section) =>
            KeyedSubtree(key: _keys[index], child: section);
        return Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: UnderlineTabs(
                labels: PricesTab.sections,
                selected: _shown,
                onSelected: (index) => unawaited(_jump(index)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: context.read<HomeCubit>().refresh,
                child: SingleChildScrollView(
                  key: _view,
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      keyed(
                        0,
                        Section(
                          title: 'Fuel',
                          note: now.fuelFromGazette
                              ? fuelNote(now, today: today)
                              : 'CEYPETCO, ${fuelNote(now, today: today)}',
                          children: [
                            if (now.fuel.isEmpty)
                              const ListTile(title: Text('Not yet')),
                            for (final price in now.fuel)
                              _PriceRow(
                                name: price.name,
                                note:
                                    'since ${cardDate(price.since, today: today)}',
                                value: amount(price.price),
                                trend: _trend(price.price, price.was),
                                graphic: Sparkline(
                                  points: since(
                                    now.fuelHistories[price.name] ?? const [],
                                    DateTime(today.year - 1, today.month),
                                  ),
                                  steps: true,
                                  until: today,
                                  height: 26,
                                ),
                                share: fuelShare(
                                  price,
                                  asOf: now.fuelAsOf ?? today,
                                  fromGazette: now.fuelFromGazette,
                                ),
                                onTap: () => chart(FuelChart(price.name)),
                              ),
                          ],
                        ),
                      ),
                      keyed(
                        1,
                        Section(
                          title: 'USD/LKR',
                          note: now.ratesFromBackup
                              ? 'backup copy'
                              : 'Central Bank',
                          children: [
                            if (now.rates.isEmpty)
                              const ListTile(title: Text('Not yet'))
                            else
                              _RateNow(
                                rates: now.rates,
                                share: rateShare(
                                  now.rates,
                                  backup: now.ratesFromBackup,
                                ),
                                onTap: () => chart(const RateChart()),
                              ),
                          ],
                        ),
                      ),
                      keyed(
                        2,
                        _GasSection(
                          gas: now.gas,
                          litro: gasPrices(items, state.gasDistrict),
                          laugfs: now.laugfs?.at(state.gasDistrict),
                          district: state.gasDistrict,
                          today: today,
                          open: widget.open,
                        ),
                      ),
                      keyed(
                        3,
                        _MarketSection(
                          market: now.market,
                          today: today,
                          onChart: (name) => chart(MarketChart(name)),
                        ),
                      ),
                      keyed(
                        4,
                        _WholesaleSection(
                          wholesale: now.wholesale,
                          centre: state.wholesaleCentre,
                          today: today,
                          onChart: (name, market) =>
                              chart(WholesaleChart(name, market)),
                        ),
                      ),
                      keyed(
                        5,
                        Section(
                          title: 'Controlled',
                          note: 'maximum retail',
                          children: [
                            if (goods.isEmpty)
                              const ListTile(title: Text('Not yet')),
                            for (final MapEntry(key: name, value: history)
                                in goods.entries)
                              _PriceRow(
                                name: name,
                                note:
                                    'since ${cardDate(history.last.day, today: today)}',
                                value: amount(history.last.value),
                                trend: _trend(
                                  history.last.value,
                                  history.length > 1
                                      ? history[history.length - 2].value
                                      : null,
                                ),
                                graphic: Sparkline(
                                  points: history,
                                  steps: true,
                                  until: today,
                                  height: 26,
                                ),
                                share: switch (setBy[name]) {
                                  final order? => goodShare(
                                    name,
                                    history,
                                    order,
                                  ),
                                  null => null,
                                },
                                onTap: () => chart(GoodChart(name)),
                              ),
                          ],
                        ),
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
                          onPressed: () =>
                              widget.open(Uri.parse(Ceypetco.page)),
                          child: const Text('CEYPETCO prices'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Which way [value] moved from [before], by how much; nothing when it
/// didn't.
Widget? _trend(double value, double? before) =>
    before == null || before == value
    ? null
    : Trend(change: value - before, text: amount((value - before).abs()));

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
      action: _PickButton(label: district, onTap: () => _pick(context)),
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

/// What a section is shown for, such as a district or a centre; a tap picks
/// another.
class _PickButton extends StatelessWidget {
  const _PickButton({required this.label, required this.onTap});

  final String label;
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
              label,
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
                                fontFeatures: tabular,
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

/// The Central Bank's daily retail prices, a section of the report at a time,
/// each good with a bar for its change since the report before.
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
    final latest = widget.market.latest;
    final sections = [
      for (final section in marketSections)
        if (quotes.any((quote) => quote.good.section == section)) section,
    ];
    if (latest == null || sections.isEmpty) {
      return const Section(
        title: 'Market',
        children: [ListTile(title: Text('Not yet'))],
      );
    }
    final shown = sections.contains(_section) ? _section : sections.first;
    return Section(
      title: 'Market',
      note: '${marketOrder.first}, ${cardDate(latest, today: widget.today)}',
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: UnderlineTabs(
              labels: sections,
              selected: sections.indexOf(shown),
              onSelected: (index) => setState(() => _section = sections[index]),
              dense: true,
            ),
          ),
        ),
        for (final quote in quotes)
          if (quote.good.section == shown)
            _PriceRow(
              name: quote.good.name,
              note: quote.market == marketOrder.first
                  ? quote.good.perUnit
                  : '${quote.good.perUnit}, ${quote.market}',
              value: amount(quote.price),
              trend: switch (quote.before) {
                final before? when before != quote.price && before > 0 => Trend(
                  change: quote.price - before,
                  text: '${_percent((quote.price - before) / before)}%',
                ),
                _ => null,
              },
              graphic: switch (quote.before) {
                final before? when before > 0 => ChangeBar(
                  change: (quote.price - before) / before,
                ),
                _ => null,
              },
              share: marketShare(quote, day: latest),
              onTap: () => widget.onChart(quote.good.name),
            ),
      ],
    );
  }

  static String _percent(double change) {
    final percent = (change * 100).abs();
    return percent < 10
        ? percent.toStringAsFixed(1)
        : percent.round().toString();
  }
}

/// HARTI's wholesale prices, a group at a time: vegetables at the centre
/// picked (across from the title), rice and dried foods at Pettah. Each
/// range sits on a track from the cheapest centre to the dearest that day.
class _WholesaleSection extends StatefulWidget {
  const _WholesaleSection({
    required this.wholesale,
    required this.centre,
    required this.today,
    required this.onChart,
  });

  final WholesalePrices wholesale;
  final String centre;
  final DateTime today;
  final void Function(String name, String market) onChart;

  @override
  State<_WholesaleSection> createState() => _WholesaleSectionState();
}

class _WholesaleSectionState extends State<_WholesaleSection> {
  /// Rows listed before "Show all": the vegetables are thirty or so.
  static const atFirst = 8;

  String _group = wholesaleGroups.first;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final group in wholesaleGroups)
        if (widget.wholesale.goods.any((good) => good.group == group)) group,
    ];
    final latest = widget.wholesale.latest;
    if (groups.isEmpty || latest == null) {
      return const Section(
        title: 'Wholesale',
        children: [ListTile(title: Text('Not yet'))],
      );
    }
    final shown = groups.contains(_group) ? _group : groups.first;
    final vegetables = shown == 'Vegetables';
    final quotes = widget.wholesale.quotes(shown, centre: widget.centre);
    final day = cardDate(latest, today: widget.today);
    return Section(
      title: 'Wholesale',
      // Where and when, as Market's "Narahenpita, 20 Oct"; the centre is
      // picked there.
      note: vegetables ? null : '$foodsMarket, $day',
      action: vegetables
          ? _PickButton(
              label: '${widget.centre}, $day',
              onTap: () => _pickCentre(context),
            )
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: UnderlineTabs(
              labels: [
                for (final group in groups)
                  group == 'Other' ? 'Other foods' : group,
              ],
              selected: groups.indexOf(shown),
              onSelected: (index) => setState(() => _group = groups[index]),
              dense: true,
            ),
          ),
        ),
        if (quotes.isEmpty)
          const ListTile(title: Text('No prices there that day'))
        else
          _TrackKey(market: quotes.first.market),
        for (final quote in _all ? quotes : quotes.take(atFirst))
          _PriceRow(
            name: quote.good.name,
            note: quote.good.perUnit,
            value: rangeText(quote.now.low, quote.now.high),
            valueWidth: 92,
            trend: switch (quote.before) {
              final before? => _trend(quote.now.middle, before.middle),
              null => null,
            },
            graphic: switch (_span(quote.good, latest)) {
              (final min, final max) when max > min => RangeTrack(
                min: min,
                max: max,
                low: quote.now.low,
                high: quote.now.high,
                width: 64,
              ),
              _ => null,
            },
            onTap: () => widget.onChart(quote.good.name, quote.market),
          ),
        if (quotes.length > atFirst)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Show fewer' : 'Show all ${quotes.length}'),
          ),
      ],
    );
  }

  /// The cheapest and dearest prices of [good] at any centre on [day].
  static (double, double)? _span(WholesaleGood good, DateTime day) {
    double? min;
    double? max;
    for (final column in good.prices.values) {
      for (final point in column) {
        if (point.day == day) {
          min = min == null || point.low < min ? point.low : min;
          max = max == null || point.high > max ? point.high : max;
        }
      }
    }
    return min == null || max == null ? null : (min, max);
  }

  Future<void> _pickCentre(BuildContext context) async {
    final cubit = context.read<HomeCubit>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final name in wholesaleCentres)
            ListTile(
              title: Text(name),
              trailing: name == widget.centre ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(name),
            ),
        ],
      ),
    );
    if (picked != null && picked != widget.centre) {
      await cubit.setWholesaleCentre(picked);
    }
  }
}

/// What the tracks show: the market's range on the span of every market.
class _TrackKey extends StatelessWidget {
  const _TrackKey({required this.market});

  final String market;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    Widget swatch(Color color, double height) => Container(
      width: 14,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          swatch(colors.primary, 5),
          const SizedBox(width: 6),
          Text(market, style: style),
          const SizedBox(width: 14),
          swatch(colors.surfaceContainerHighest, 4),
          const SizedBox(width: 6),
          Text('Cheapest to dearest centre', style: style),
        ],
      ),
    );
  }
}

/// A name with a note under it, a small drawing of its history or change,
/// and its price with which way it moved.
class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.name,
    required this.value,
    this.note,
    this.trend,
    this.graphic,
    this.valueWidth = 76,
    this.share,
    this.onTap,
  });

  final String name;
  final String? note;
  final String value;
  final Widget? trend;

  /// A sparkline, a change bar or a range track.
  final Widget? graphic;

  /// Room for the price, so the drawings line up down a section.
  final double valueWidth;

  /// What a long press shares.
  final String? share;

  /// Opens the chart.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = this.share;
    final graphic = this.graphic;
    return InkWell(
      onTap: onTap,
      onLongPress: share == null ? null : () => shareText(context, share),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (note case final note?)
                    Text(
                      note,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (graphic != null) ...[
              const SizedBox(width: 12),
              SizedBox(width: 64, child: Center(child: graphic)),
            ],
            const SizedBox(width: 12),
            SizedBox(
              width: valueWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabular,
                    ),
                    maxLines: 1,
                  ),
                  ?trend,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's rate, large, with the week's move, over the last 30 days as a
/// chart to slide a finger along.
class _RateNow extends StatelessWidget {
  const _RateNow({required this.rates, required this.share, this.onTap});

  /// Newest first.
  final List<RateNow> rates;

  /// What a long press shares.
  final String share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = rates.first;
    final move = weekMove(rates);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          onLongPress: () => shareText(context, share),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        amount(latest.rate),
                        style: bigNumber(context, size: 40),
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Trend(
                      change: move,
                      text: '${move.abs().toStringAsFixed(1)}% in a week',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (rates.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            child: PriceChart(
              points: [
                for (final rate in rates.reversed)
                  PricePoint(rate.day, rate.rate),
              ],
              height: 150,
            ),
          ),
      ],
    );
  }
}
