import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lanka_radar/app/viz/sparkline.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// A day as 24 hours, one lane per place, with its load shedding slots (and
/// a cut on now) filled in, and a line for now that moves on by itself.
class DayLanes extends StatefulWidget {
  const DayLanes({
    required this.day,
    required this.places,
    this.now,
    super.key,
  });

  /// Midnight of the day shown.
  final DateTime day;
  final List<PlaceCuts> places;

  /// For tests; the clock otherwise.
  final DateTime? now;

  /// The cuts at [place] on [day], as start and end within it.
  static List<(DateTime, DateTime)> slots(PlaceCuts place, DateTime day) {
    final next = DateTime(day.year, day.month, day.day + 1);
    return [
      for (final cut in place.ahead) (cut.start, cut.end),
      for (final outage in place.outages)
        if ((outage.from, outage.time) case (
          final DateTime from,
          final DateTime to,
        ) when outage.kind == OutageKind.maintenance)
          (from, to),
    ].where((slot) => slot.$1.isBefore(next) && slot.$2.isAfter(day)).toList();
  }

  @override
  State<DayLanes> createState() => _DayLanesState();
}

class _DayLanesState extends State<DayLanes> {
  late DateTime _now = widget.now ?? DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    if (widget.now == null) {
      _clock = Timer.periodic(
        const Duration(minutes: 1),
        (_) => setState(() => _now = DateTime.now()),
      );
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final day = widget.day;
    final hours = _now.difference(day).inMinutes / 60;
    final showNow = hours >= 0 && hours < 24;
    const nameWidth = 84.0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth - nameWidth;
            double x(DateTime time) =>
                (time.difference(day).inMinutes / (24 * 60)).clamp(0.0, 1.0) *
                width;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final place in widget.places)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: nameWidth,
                              child: Text(
                                place.place.name,
                                style: theme.textTheme.labelLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              height: 30,
                              child: DrawIn(
                                builder: (context, drawn) => Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    Container(
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: colors.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                    for (final (start, end) in DayLanes.slots(
                                      place,
                                      day,
                                    ))
                                      Positioned(
                                        left: x(start),
                                        width: (x(end) - x(start)) * drawn,
                                        top: 6,
                                        height: 18,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: colors.tertiary,
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        const SizedBox(width: nameWidth),
                        SizedBox(
                          width: width,
                          height: 14,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (final hour in const [0, 6, 12, 18, 24])
                                Positioned(
                                  left:
                                      hour / 24 * width - (hour == 24 ? 16 : 0),
                                  child: Text(
                                    hour.toString().padLeft(2, '0'),
                                    style: muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (showNow)
                  Positioned(
                    left: nameWidth + hours / 24 * width - 4,
                    top: -4,
                    bottom: 16,
                    child: Column(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(width: 2, color: colors.primary),
                        ),
                      ],
                    ),
                  ),
                if (showNow)
                  Positioned(
                    left: nameWidth + hours / 24 * width + 8,
                    top: -8,
                    child: Text(
                      clock(_now.hour * 60 + _now.minute),
                      style: muted?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
