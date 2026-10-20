import 'package:flutter/material.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/power/hero_status.dart';
import 'package:lanka_radar/features/power/widgets/power_line.dart';

/// One place in the Power list: an edge in its state's color, its name, how it
/// stands, and its area; with its cuts listed under it when there are several.
/// Tapping it opens it.
class PlaceRow extends StatelessWidget {
  const PlaceRow({
    required this.place,
    required this.state,
    required this.cuts,
    required this.checking,
    required this.onTap,
    this.shape,
    super.key,
  });

  /// How many cuts are listed under a place.
  static const shown = 3;

  final Place place;
  final NodeState state;

  /// Null until its area has been read.
  final List<Outage>? cuts;
  final bool checking;
  final VoidCallback onTap;

  /// Lets the list round only the outer corners of its group.
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cuts = this.cuts ?? const <Outage>[];
    final (edge, status, statusColor) = switch (state) {
      NodeState.cut => (
        colors.tertiary,
        cuts.length == 1 ? _first(cuts.single) : '${cuts.length} power cuts',
        colors.tertiary,
      ),
      NodeState.clear => (
        colors.primary,
        'No cuts reported',
        colors.onSurfaceVariant,
      ),
      NodeState.waiting => (
        colors.outlineVariant,
        checking ? 'Checking...' : 'Not checked yet',
        colors.onSurfaceVariant,
      ),
      NodeState.unfinished => (
        colors.outlineVariant,
        place.area == null ? 'Pick its CEB area' : 'Set where it is',
        colors.primary,
      ),
    };
    return Material(
      shape: shape,
      color: colors.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: Motion.of(context, Motion.medium),
                width: 4,
                color: edge,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              place.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (place.area case final area?)
                            Text(
                              area.name,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          Icon(
                            Icons.chevron_right,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: Motion.of(context, Motion.medium),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: AlignmentDirectional.centerStart,
                          children: [...previous, ?current],
                        ),
                        child: Text(
                          status,
                          key: ValueKey(status),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                            fontWeight: state == NodeState.cut
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                      ),
                      RevealSwitcher(
                        child: cuts.length > 1
                            ? Padding(
                                key: ValueKey(cuts),
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  children: [
                                    for (final outage in cuts.take(shown))
                                      _CutLine(outage: outage),
                                  ],
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey('none'),
                                width: double.infinity,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Breakdown since 09:24".
  static String _first(Outage outage) {
    final sentence = outageSentence(outage);
    return sentence.startsWith('A ')
        ? sentence.substring(2).capitalized
        : sentence;
  }
}

extension on String {
  String get capitalized =>
      isEmpty ? this : this[0].toUpperCase() + substring(1);
}

/// A cut under its place: what it is and when.
class _CutLine extends StatelessWidget {
  const _CutLine({required this.outage});

  final Outage outage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final time = outage.time;
    final at = time == null ? null : clock(time.hour * 60 + time.minute);
    final what = switch (outage.kind) {
      OutageKind.breakdown => at == null ? 'Breakdown' : 'Breakdown since $at',
      OutageKind.maintenance =>
        at == null
            ? (outage.reason ?? 'Maintenance')
            : '${outage.reason ?? 'Maintenance'} until $at',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.tertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(what, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
