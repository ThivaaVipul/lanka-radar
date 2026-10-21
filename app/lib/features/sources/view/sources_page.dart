import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/app/viz/radar.dart';
import 'package:lanka_radar/core/data/health.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/sources/cubit/sources_cubit.dart';

/// Every source on the radar, nearer the centre the fresher (GitHub's on the
/// right, the phone's on the left), then listed by who reads it with when it
/// last answered. A tap on a row rings its blip.
class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (context) => const SourcesPage());

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  String? _picked;

  /// The radar's rings: an hour, six hours and a day old.
  static const _rings = [(1, '1 h'), (6, '6 h'), (24, '1 day')];

  /// How far out a source sits for its age: the square root of its share of a
  /// day, so the last hours get the most room.
  static double _distance(SourceHealth source, DateTime now) {
    final success = source.lastSuccess;
    if (success == null || source.isStale(now)) {
      return 0.94;
    }
    final hours = now.difference(success).inMinutes / 60;
    return math.sqrt((hours / 24).clamp(0.0, 1.0)).clamp(0.1, 0.94);
  }

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
            final colors = Theme.of(context).colorScheme;
            final now = DateTime.now();
            final ran = health.workflowRan;
            final all = [...health.github, ...health.phone];
            List<Blip> side(List<SourceHealth> sources, double from) => [
              for (final (index, source) in sources.indexed)
                Blip(
                  turn: from + (index + 0.5) / sources.length * 0.46,
                  distance: _distance(source, now),
                  color: source.isStale(now) || source.lastSuccess == null
                      ? colors.tertiary
                      : colors.primary,
                ),
            ];
            final picked = all.indexWhere((source) => source.name == _picked);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Center(
                  child: _Scope(
                    blips: [
                      ...side(health.github, 0.02),
                      ...side(health.phone, 0.52),
                    ],
                    picked: picked < 0 ? null : picked,
                  ),
                ),
                const SizedBox(height: 8),
                _Group(
                  title: 'Read by GitHub',
                  note: ran == null
                      ? 'Not run yet'
                      : 'Last run ${dayTime(ran, today: now)}',
                  warn: health.workflowStale(now),
                  sources: health.github,
                  now: now,
                  picked: _picked,
                  onPick: _pick,
                ),
                const SizedBox(height: 16),
                _Group(
                  title: 'Read by this phone',
                  note: 'Only answer inside Sri Lanka',
                  sources: health.phone,
                  now: now,
                  picked: _picked,
                  onPick: _pick,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _pick(String name) =>
      setState(() => _picked = _picked == name ? null : name);
}

/// The radar itself, with the rings' ages along its twelve o'clock line.
class _Scope extends StatelessWidget {
  const _Scope({required this.blips, required this.picked});

  final List<Blip> blips;
  final int? picked;

  static const size = 248.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 10,
    );
    final rings = [
      for (final (hours, _) in _SourcesPageState._rings) math.sqrt(hours / 24),
    ];
    const radius = size / 2;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Radar(size: size, blips: blips, ringAt: rings, picked: picked),
          for (final (index, (_, label)) in _SourcesPageState._rings.indexed)
            Positioned(
              left: radius + 4,
              top: radius - rings[index] * (radius - 1) + 2,
              child: Text(label, style: style),
            ),
        ],
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
    required this.picked,
    required this.onPick,
    this.warn = false,
  });

  final String title;
  final String note;
  final List<SourceHealth> sources;
  final DateTime now;
  final bool warn;
  final String? picked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              Text(
                note,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: warn ? colors.tertiary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (sources.isEmpty)
                const ListTile(title: Text('Nothing checked yet')),
              for (final (index, source) in sources.indexed) ...[
                if (index > 0) const Divider(height: 1, indent: 16),
                _SourceRow(
                  source: source,
                  now: now,
                  picked: source.name == picked,
                  onTap: () => onPick(source.name),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A source: its name, when it last answered (ochre once quiet), and the
/// last error under it.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.now,
    required this.picked,
    required this.onTap,
  });

  final SourceHealth source;
  final DateTime now;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quiet = source.isStale(now) || source.lastSuccess == null;
    final success = source.lastSuccess;
    final error = source.lastError;
    final when = source.lastRun == null
        ? 'Not checked'
        : success == null
        ? 'Never answered'
        : now.difference(success) < staleAfter && success.day == now.day
        ? clock(success.hour * 60 + success.minute)
        : dayTime(success, today: now);
    return AnimatedContainer(
      duration: Motion.of(context, Motion.short),
      color: picked ? colors.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.name, style: theme.textTheme.bodyLarge),
                    if (error != null)
                      Text(
                        'Last try failed: $error',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                when,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: quiet ? colors.tertiary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
