import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/labels.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/highlight.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/item/widgets/topic_badge.dart';
import 'package:lanka_radar/features/prices/cubit/price_chart_cubit.dart';
import 'package:lanka_radar/features/prices/view/price_chart_page.dart';
import 'package:lanka_radar/features/search/cubit/search_cubit.dart';
import 'package:lanka_radar/features/search/search_results.dart';

/// One search over everything on the phone, as you type: prices, notices and
/// dates in groups, with suggestions and recent searches before you type.
class SearchPage extends StatelessWidget {
  const SearchPage({required this.tabs, super.key});

  static Route<void> route(TabSelection tabs) =>
      MaterialPageRoute(builder: (context) => SearchPage(tabs: tabs));

  /// Common searches, offered before typing.
  static const suggestions = [
    'Petrol 92',
    'Diesel',
    'USD/LKR',
    'Poya',
    'O/L',
    'A/L',
    'Tax',
    'Jobs',
  ];

  /// Notices listed before "Show all", when every group is shown.
  static const noticesAtFirst = 20;

  final TabSelection tabs;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SearchCubit(context.read(), context.read())..load(),
      child: _SearchView(tabs: tabs),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView({required this.tabs});

  final TabSelection tabs;

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _searchFor(String query) {
    _field
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    unawaited(context.read<SearchCubit>().search(query));
  }

  /// Leaves search for a tab, keeping the query as a recent search.
  void _openTab(HomeTab tab) {
    unawaited(context.read<SearchCubit>().remember());
    Navigator.of(context).pop();
    widget.tabs.value = tab;
  }

  void _openItem(FeedItem item) {
    unawaited(context.read<SearchCubit>().remember());
    unawaited(Navigator.of(context).push(ItemPage.route(item)));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchCubit>();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _field,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search prices, notices and dates',
            border: InputBorder.none,
          ),
          onChanged: (query) {
            setState(() {});
            unawaited(cubit.search(query));
          },
          onSubmitted: (_) => unawaited(cubit.remember()),
        ),
        actions: [
          if (_field.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _searchFor('')),
            ),
        ],
      ),
      body: BlocBuilder<SearchCubit, SearchState>(
        builder: (context, state) {
          final results = state.results;
          if (results == null) {
            return _Suggestions(
              recent: state.recent,
              onSearch: (query) => setState(() => _searchFor(query)),
              onForget: (query) => unawaited(cubit.forget(query)),
            );
          }
          if (results.isEmpty) {
            return const _NoMatches();
          }
          final words = state.words;
          final only = state.only;
          final notices = only == SearchGroup.notices
              ? results.notices
              : results.notices.take(SearchPage.noticesAtFirst).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              for (final group in SearchGroup.values)
                if (results.count(group) > 0 && (only == null || only == group))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _GroupHeader(
                        group: group,
                        count: results.count(group),
                        shownAlone: only == group,
                        onTap: () =>
                            cubit.showOnly(only == group ? null : group),
                      ),
                      ItemGroup(
                        children: switch (group) {
                          SearchGroup.prices => [
                            for (final hit in results.prices)
                              _PriceRow(
                                hit: hit,
                                words: words,
                                onTap: () => switch (hit) {
                                  OrderPriceHit(:final order) => _openItem(
                                    order,
                                  ),
                                  MarketHit(:final quote) =>
                                    Navigator.of(context).push(
                                      PriceChartPage.route(
                                        MarketChart(quote.good.name),
                                      ),
                                    ),
                                  _ => _openTab(HomeTab.prices),
                                },
                              ),
                          ],
                          SearchGroup.notices => [
                            for (final item in notices)
                              ItemTile(
                                item: item,
                                highlight: words,
                                onTap: () => _openItem(item),
                              ),
                          ],
                          SearchGroup.dates => [
                            for (final holiday in results.dates)
                              _DateRow(
                                holiday: holiday,
                                words: words,
                                onTap: () => _openTab(HomeTab.dates),
                              ),
                          ],
                        },
                      ),
                      if (group == SearchGroup.notices &&
                          notices.length < results.notices.length)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: () =>
                                cubit.showOnly(SearchGroup.notices),
                            child: Text(
                              'Show all ${results.notices.length} notices',
                            ),
                          ),
                        ),
                    ],
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// A group's name and count; tapping it shows that group alone, or all again.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.count,
    required this.shownAlone,
    required this.onTap,
  });

  final SearchGroup group;
  final int count;
  final bool shownAlone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = switch (group) {
      SearchGroup.prices => 'Prices',
      SearchGroup.notices => 'Notices',
      SearchGroup.dates => 'Dates',
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: [
            Text(name, style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              shownAlone ? 'All results' : 'Only ${name.toLowerCase()}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A price search found: its name, where it comes from, and the value.
class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.hit,
    required this.words,
    required this.onTap,
  });

  final PriceHit hit;
  final List<String> words;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = DateTime.now();
    final (look, name, note, value, before) = switch (hit) {
      FuelHit(:final fuel) => (
        TopicLook.fuel,
        fuel.name,
        'CEYPETCO, since ${cardDate(fuel.since, today: today)}',
        fuel.price,
        fuel.was,
      ),
      RateHit(:final rate) => (
        TopicLook.rates,
        'USD/LKR',
        weekdayDate(rate.day),
        rate.rate,
        null,
      ),
      GasHit(:final list) => (
        TopicLook.gas,
        'Litro price list',
        'from ${cardDate(list.effective ?? list.published, today: today)}',
        null,
        null,
      ),
      OrderPriceHit(:final order, :final number) => (
        TopicLook.prices,
        shortLabel(number.label),
        [?order.issuer, cardDate(order.published, today: today)].join(dot),
        number.value,
        number.previous,
      ),
      MarketHit(:final quote, :final day) => (
        TopicLook.market,
        quote.good.name,
        [
          quote.market,
          quote.good.perUnit,
          cardDate(day, today: today),
        ].join(dot),
        quote.price,
        quote.before,
      ),
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            TopicBadge(look),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    highlighted(
                      name,
                      words,
                      strong: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    note,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (value == null)
              Icon(Icons.open_in_new, size: 20, color: colors.onSurfaceVariant)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount(value),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (before != null && before != value)
                    Trend(
                      change: value - before,
                      text: 'was ${amount(before)}',
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A holiday search found, with its day and how far off it is.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.holiday,
    required this.words,
    required this.onTap,
  });

  final HolidayNow holiday;
  final List<String> words;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final HolidayNow(:day, :name, :tentative, :tamil) = holiday;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TopicBadge(TopicLook.holiday),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    highlighted(
                      tentative ? '$name (tentative)' : name,
                      words,
                      strong: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (tamil != null)
                    Text(
                      tamil,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    '${weekdayDate(day)}$dot'
                    '${inDays(day, today: DateTime.now())}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Before typing: common searches, and the last ones.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.recent,
    required this.onSearch,
    required this.onForget,
  });

  final List<String> recent;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onForget;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in SearchPage.suggestions)
              ActionChip(
                label: Text(suggestion),
                onPressed: () => onSearch(suggestion),
              ),
          ],
        ),
        if (recent.isNotEmpty)
          Section(
            title: 'Recent',
            card: false,
            children: [
              ItemGroup(
                children: [
                  for (final query in recent)
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(query),
                      trailing: IconButton(
                        tooltip: 'Forget',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => onForget(query),
                      ),
                      onTap: () => onSearch(query),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('No matches', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
