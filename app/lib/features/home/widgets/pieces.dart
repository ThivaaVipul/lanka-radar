import 'package:flutter/material.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// Which way a value moved: ochre up (a price rising), teal down, with how
/// much ("15", "0.4%").
class Trend extends StatelessWidget {
  const Trend({required this.change, required this.text, super.key});

  final double change;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = change > 0 ? colors.tertiary : colors.primary;
    if (change == 0) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          change > 0 ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A number at a glance: what it is, the value large, which way it moved and a
/// small note.
class NumberTile extends StatelessWidget {
  const NumberTile({
    required this.label,
    required this.value,
    this.trend,
    this.note,
    this.onTap,
    this.valueLines = 1,
    super.key,
  });

  final String label;
  final String value;
  final Widget? trend;
  final String? note;
  final VoidCallback? onTap;
  final int valueLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: quiet),
              const SizedBox(height: 6),
              Text(
                value,
                style: valueLines == 1
                    ? theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      )
                    : theme.textTheme.titleMedium,
                maxLines: valueLines,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (trend case final trend?) ...[
                    trend,
                    const SizedBox(width: 8),
                  ],
                  if (note case final note?)
                    Expanded(
                      child: Text(
                        note,
                        style: quiet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled group on a tab, with an optional note under the title.
class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.children,
    this.note,
    this.card = true,
    super.key,
  });

  final String title;
  final String? note;
  final List<Widget> children;

  /// Whether the children sit in one card (rows) or stand alone (cards).
  final bool card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
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
        if (card)
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, child) in children.indexed) ...[
                  if (index > 0) const Divider(height: 1, indent: 16),
                  child,
                ],
              ],
            ),
          )
        else
          ...children,
      ],
    );
  }
}

/// "changed 30 Sep", or "as of 14 Oct" when CEYPETCO hasn't answered for a
/// day or the prices come from a gazette.
String fuelNote(NowData data, {required DateTime today}) {
  final asOf = data.fuelAsOf;
  final changed = data.fuelChanged;
  final stale =
      data.fuelFromGazette ||
      asOf == null ||
      today.difference(asOf) > staleAfter;
  if (stale && asOf != null) {
    return 'as of ${cardDate(asOf, today: today)}';
  }
  return changed == null ? '' : 'changed ${cardDate(changed, today: today)}';
}

/// USD/LKR's move over the last week, in percent: the latest rate against the
/// last one at least 7 days before it. Null without one that old.
double? weekMove(List<RateNow> rates) {
  if (rates.isEmpty) {
    return null;
  }
  final latest = rates.first;
  final weekBefore = latest.day.subtract(const Duration(days: 7));
  for (final rate in rates) {
    if (!rate.day.isAfter(weekBefore)) {
      return (latest.rate / rate.rate - 1) * 100;
    }
  }
  return null;
}
