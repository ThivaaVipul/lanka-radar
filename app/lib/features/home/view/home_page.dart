import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/topics.dart';
import 'package:lanka_radar/features/about/view/about_page.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/widgets/now_card.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';
import 'package:lanka_radar/features/search/view/search_page.dart';
import 'package:lanka_radar/features/sources/view/sources_page.dart';

/// The feed: the Now card, topic chips, then the items newest first under month
/// headings.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => HomeCubit(context.read(), context.read())..watch(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<HomeCubit>();
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(cubit.leave()),
      onShow: () => unawaited(cubit.resume()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lanka Radar'),
        actions: [
          BlocSelector<HomeCubit, HomeState, bool>(
            selector: (state) =>
                state.health?.needsALook(DateTime.now()) ?? false,
            builder: (context, needsALook) => needsALook
                ? IconButton(
                    tooltip: 'A source has gone quiet',
                    icon: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    onPressed: () =>
                        Navigator.of(context).push(SourcesPage.route()),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(SearchPage.route()),
          ),
          PopupMenuButton<Route<void> Function()>(
            tooltip: 'More',
            onSelected: (route) => Navigator.of(context).push(route()),
            itemBuilder: (context) => const [
              PopupMenuItem(value: SourcesPage.route, child: Text('Sources')),
              PopupMenuItem(value: AboutPage.route, child: Text('About')),
            ],
          ),
        ],
      ),
      body: BlocConsumer<HomeCubit, HomeState>(
        listenWhen: (before, now) =>
            !before.failed && now.failed && (now.items?.isNotEmpty ?? false),
        listener: (context, state) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Couldn't refresh"))),
        builder: (context, state) {
          final items = state.items;
          if (items == null || (items.isEmpty && state.refreshing)) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return state.failed
                ? const _LoadFailed()
                : const Center(child: Text('Nothing yet'));
          }
          return RefreshIndicator(
            onRefresh: context.read<HomeCubit>().refresh,
            child: _Feed(state: state),
          );
        },
      ),
    );
  }
}

/// A row of the feed: a month heading or an item.
sealed class _Row {
  const _Row();
}

final class _Heading extends _Row {
  const _Heading(this.month);

  final DateTime month;
}

final class _Entry extends _Row {
  const _Entry(this.item);

  final FeedItem item;
}

class _Feed extends StatelessWidget {
  const _Feed({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[];
    for (final item in state.visibleItems ?? const <FeedItem>[]) {
      final last = rows.isEmpty ? null : rows.last;
      final previous = last is _Entry ? last.item.published : null;
      if (previous == null ||
          previous.month != item.published.month ||
          previous.year != item.published.year) {
        rows.add(_Heading(item.published));
      }
      rows.add(_Entry(item));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          final card = state.nowCard;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (card != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: NowCard(data: card),
                ),
              _TopicChips(selected: state.topic, empty: rows.isEmpty),
            ],
          );
        }
        return switch (rows[index - 1]) {
          _Heading(:final month) => _MonthHeading(month: month),
          _Entry(:final item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ItemCard(
              item: item,
              isNew: state.isNew(item),
              onTap: () => Navigator.of(context).push(ItemPage.route(item)),
            ),
          ),
        };
      },
    );
  }
}

class _TopicChips extends StatelessWidget {
  const _TopicChips({required this.selected, required this.empty});

  final String? selected;

  /// Nothing in the chosen topic yet.
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HomeCubit>();
    final chips = [
      (null, 'All'),
      for (final MapEntry(:key, :value) in topics.entries) (key, value),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: chips.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (topic, label) = chips[index];
              return ChoiceChip(
                label: Text(label),
                selected: selected == topic,
                showCheckmark: false,
                onSelected: (_) => cubit.showTopic(topic),
              );
            },
          ),
        ),
        if (empty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Text('Nothing yet'),
          ),
      ],
    );
  }
}

class _MonthHeading extends StatelessWidget {
  const _MonthHeading({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        monthHeading(month),
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed();

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
