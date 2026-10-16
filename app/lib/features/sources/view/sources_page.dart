import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/health.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/sources/cubit/sources_cubit.dart';

/// Every source, grouped by who reads it, with its last success and error.
class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (context) => const SourcesPage());

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SourcesCubit(context.read())..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Sources')),
        body: BlocBuilder<SourcesCubit, Health?>(
          builder: (context, health) {
            if (health == null) {
              return const SizedBox.shrink();
            }
            final now = DateTime.now();
            final ran = health.workflowRan;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _Group(
                  title: 'Read by GitHub',
                  note: ran == null
                      ? 'Not run yet'
                      : 'Last run ${dayTime(ran, today: now)}',
                  warn: health.workflowStale(now),
                  sources: health.github,
                  now: now,
                ),
                const SizedBox(height: 16),
                _Group(
                  title: 'Read by this phone',
                  note: 'Only answer inside Sri Lanka',
                  sources: health.phone,
                  now: now,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.note,
    required this.sources,
    required this.now,
    this.warn = false,
  });

  final String title;
  final String note;
  final List<SourceHealth> sources;
  final DateTime now;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            note,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: warn ? colors.tertiary : colors.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              if (sources.isEmpty)
                const ListTile(title: Text('Nothing checked yet')),
              for (final source in sources)
                _SourceTile(source: source, now: now),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.now});

  final SourceHealth source;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stale = source.isStale(now);
    final success = source.lastSuccess;
    final error = source.lastError;
    return ListTile(
      leading: Icon(
        stale ? Icons.error_outline : Icons.check_circle_outline,
        color: stale ? colors.tertiary : colors.primary,
      ),
      title: Text(source.name),
      subtitle: Text(
        [
          if (source.lastRun == null)
            'Not checked yet'
          else if (success == null)
            'Never answered'
          else
            'Updated ${dayTime(success, today: now)}',
          if (error != null) 'Last try failed: $error',
        ].join('\n'),
      ),
    );
  }
}
