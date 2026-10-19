import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/prices/cubit/price_chart_cubit.dart';
import 'package:lanka_radar/features/prices/widgets/price_chart.dart';

/// A price or the rate over time: where it is now and how it got there.
class PriceChartPage extends StatelessWidget {
  const PriceChartPage({required this.subject, super.key});

  static Route<void> route(ChartSubject subject) =>
      MaterialPageRoute(builder: (context) => PriceChartPage(subject: subject));

  final ChartSubject subject;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          PriceChartCubit(context.read(), context.read(), subject)..load(),
      child: Scaffold(
        appBar: AppBar(title: Text(subject.title)),
        body: BlocBuilder<PriceChartCubit, PriceChartState>(
          builder: (context, state) {
            final all = state.points;
            if (all == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (all.isEmpty) {
              return const Center(child: Text('No prices yet'));
            }
            final today = DateTime.now();
            final points = state.shown(subject, today);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _Now(subject: subject, points: points, today: today),
                if (!subject.steps) ...[
                  const SizedBox(height: 16),
                  SegmentedButton<ChartRange>(
                    segments: [
                      for (final range in ChartRange.values)
                        ButtonSegment(value: range, label: Text(range.label)),
                    ],
                    selected: {state.range},
                    showSelectedIcon: false,
                    onSelectionChanged: (selected) => context
                        .read<PriceChartCubit>()
                        .showRange(selected.single),
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
                    child: PriceChart(
                      points: points,
                      steps: subject.steps,
                      until: subject.steps ? today : null,
                    ),
                  ),
                ),
                if (subject.steps)
                  Section(
                    title: 'Changes',
                    children: [
                      for (final (index, point)
                          in all.indexed.toList().reversed)
                        _ChangeRow(
                          point: point,
                          before: index > 0 ? all[index - 1].value : null,
                          today: today,
                        ),
                    ],
                  )
                else
                  Section(title: 'In this range', children: _rangeRows(points)),
              ],
            );
          },
        ),
      ),
    );
  }

  static List<Widget> _rangeRows(List<PricePoint> points) {
    final values = [for (final point in points) point.value];
    final high = points.reduce((a, b) => b.value > a.value ? b : a);
    final low = points.reduce((a, b) => b.value < a.value ? b : a);
    final average = values.reduce((a, b) => a + b) / values.length;
    final today = DateTime.now();
    return [
      _ValueRow(
        label: 'High',
        value: amount(high.value),
        note: cardDate(high.day, today: today),
      ),
      _ValueRow(
        label: 'Low',
        value: amount(low.value),
        note: cardDate(low.day, today: today),
      ),
      _ValueRow(label: 'Average', value: average.toStringAsFixed(2)),
    ];
  }
}

/// The latest value, large, with its move over what the chart shows.
class _Now extends StatelessWidget {
  const _Now({
    required this.subject,
    required this.points,
    required this.today,
  });

  final ChartSubject subject;
  final List<PricePoint> points;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final latest = points.last;
    final first = points.first;
    final change = latest.value - first.value;
    final percent = first.value == 0 ? 0 : change / first.value * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(subject.source, style: muted),
        const SizedBox(height: 6),
        Text(
          amount(latest.value),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (points.length > 1 && change != 0) ...[
              Trend(
                change: change,
                text:
                    '${amount(_rounded(change.abs()))} '
                    '(${percent.abs().toStringAsFixed(1)}%)',
              ),
              const SizedBox(width: 8),
            ],
            Text(
              points.length > 1
                  ? 'since ${cardDate(first.day, today: today)}'
                  : 'since ${cardDate(latest.day, today: today)}',
              style: muted,
            ),
          ],
        ),
      ],
    );
  }

  static double _rounded(double value) => (value * 100).roundToDouble() / 100;
}

/// A price change: the day, the new price and how far it moved.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.point,
    required this.before,
    required this.today,
  });

  final PricePoint point;
  final double? before;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final before = this.before;
    return _ValueRow(
      label: weekdayDate(point.day),
      note: point.day.year == today.year ? null : '${point.day.year}',
      value: amount(point.value),
      trend: before == null || before == point.value
          ? null
          : Trend(
              change: point.value - before,
              text: amount((point.value - before).abs()),
            ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.note,
    this.trend,
  });

  final String label;
  final String value;
  final String? note;
  final Widget? trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
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
          if (trend case final trend?) ...[trend, const SizedBox(width: 12)],
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
