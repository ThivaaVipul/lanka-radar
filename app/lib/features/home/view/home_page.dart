import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';

/// The feed. For now a plain list of headlines; the Now card, cards and topic
/// chips come in the next milestone pieces (docs/PLAN.md, M5c and M5d).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => HomeCubit(context.read())..watch(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lanka Radar')),
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
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) => _ItemRow(item: items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        item.headlineEn,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text([?item.issuer, shortDate(item.published)].join(', ')),
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
