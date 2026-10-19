import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lanka_radar/core/data/price_history.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/numbers.dart';

/// A price over time: a line, or steps for prices set on a day, the area under
/// it tinted, a few value lines and dates, and the value under your finger.
class PriceChart extends StatefulWidget {
  const PriceChart({
    required this.points,
    this.steps = false,
    this.until,
    this.height = 220,
    super.key,
  });

  /// Oldest first; at least one.
  final List<PricePoint> points;

  /// Draw steps: each price holds until the next one.
  final bool steps;

  /// The day the last step runs to (today), when it is later than the last
  /// point.
  final DateTime? until;
  final double height;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  /// The point under the finger.
  int? _touched;

  void _touch(Offset at, double width) {
    final layout = _Layout(widget.points, widget.until, width, widget.height);
    var nearest = 0;
    var distance = double.infinity;
    for (final (index, point) in widget.points.indexed) {
      final gap = (layout.x(point.day) - at.dx).abs();
      if (gap < distance) {
        distance = gap;
        nearest = index;
      }
    }
    if (nearest != _touched) {
      setState(() => _touched = nearest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanDown: (details) => _touch(details.localPosition, width),
          onPanUpdate: (details) => _touch(details.localPosition, width),
          onPanEnd: (_) => setState(() => _touched = null),
          onPanCancel: () => setState(() => _touched = null),
          child: CustomPaint(
            size: Size(width, widget.height),
            painter: _ChartPainter(
              points: widget.points,
              steps: widget.steps,
              until: widget.until,
              touched: _touched,
              colors: theme.colorScheme,
              labels: theme.textTheme.labelSmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              readout: theme.textTheme.labelMedium!.copyWith(
                color: theme.colorScheme.onInverseSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Round values for about three lines between [low] and [high], and the step
/// between them: 1, 2, 2.5 or 5 times a power of ten.
(List<double>, double) valueTicks(double low, double high) {
  final rough = (high - low) / 3;
  final power = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final step = [1, 2, 2.5, 5, 10]
      .map((factor) => factor * power)
      .firstWhere((candidate) => candidate >= rough);
  return (
    [
      for (var value = (low / step).ceil() * step; value <= high; value += step)
        // Undo floating point drift, so 0.1 * 3 reads 0.3.
        double.parse(value.toStringAsFixed(6)),
    ],
    step,
  );
}

/// Where days and values land on the canvas.
class _Layout {
  _Layout(List<PricePoint> points, DateTime? until, this.width, this.height) {
    first = points.first.day;
    final last = points.last.day;
    lastDay = until != null && until.isAfter(last) ? until : last;
    final values = [for (final point in points) point.value];
    var low = values.reduce(math.min);
    var high = values.reduce(math.max);
    final pad = high == low
        ? math.max(high.abs() * 0.05, 1)
        : (high - low) * 0.15;
    low -= pad;
    high += pad;
    bottom = low;
    top = high;
  }

  /// Room on the right for values, at the bottom for dates.
  static const right = 48.0;
  static const below = 22.0;
  static const above = 8.0;

  final double width;
  final double height;
  late final DateTime first;
  late final DateTime lastDay;
  late final double bottom;
  late final double top;

  double get plotWidth => width - right;
  double get plotHeight => height - below - above;

  double x(DateTime day) {
    final span = lastDay.difference(first).inHours;
    if (span == 0) {
      return plotWidth / 2;
    }
    return day.difference(first).inHours / span * plotWidth;
  }

  double y(double value) => above + (top - value) / (top - bottom) * plotHeight;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.steps,
    required this.until,
    required this.touched,
    required this.colors,
    required this.labels,
    required this.readout,
  });

  final List<PricePoint> points;
  final bool steps;
  final DateTime? until;
  final int? touched;
  final ColorScheme colors;
  final TextStyle labels;
  final TextStyle readout;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _Layout(points, until, size.width, size.height);
    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;

    // Value lines at round numbers, with the values on the right.
    final (values, step) = valueTicks(layout.bottom, layout.top);
    for (final value in values) {
      final y = layout.y(value);
      canvas.drawLine(Offset(0, y), Offset(layout.plotWidth, y), grid);
      _text(
        canvas,
        step < 1 ? value.toStringAsFixed(step < 0.1 ? 2 : 1) : amount(value),
        Offset(layout.plotWidth + 8, y),
        labels,
        centreY: true,
      );
    }
    final base = _Layout.above + layout.plotHeight;

    // The first, middle and last dates along the bottom.
    final today = DateTime.now();
    final dates = {
      layout.first,
      _middle(layout.first, layout.lastDay),
      layout.lastDay,
    };
    for (final (index, day) in dates.indexed) {
      final label = cardDate(day, today: today);
      final x = layout.x(day);
      _text(
        canvas,
        label,
        Offset(x, base + 6),
        labels,
        align: index == 0
            ? TextAlign.left
            : index == dates.length - 1
            ? TextAlign.right
            : TextAlign.center,
      );
    }

    // The line, and the area under it.
    final line = Path();
    for (final (index, point) in points.indexed) {
      final at = Offset(layout.x(point.day), layout.y(point.value));
      if (index == 0) {
        line.moveTo(at.dx, at.dy);
      } else if (steps) {
        line
          ..lineTo(at.dx, layout.y(points[index - 1].value))
          ..lineTo(at.dx, at.dy);
      } else {
        line.lineTo(at.dx, at.dy);
      }
    }
    final end = layout.x(layout.lastDay);
    if (steps) {
      line.lineTo(end, layout.y(points.last.value));
    }
    final area = Path.from(line)
      ..lineTo(steps ? end : layout.x(points.last.day), base)
      ..lineTo(layout.x(points.first.day), base)
      ..close();
    canvas
      ..drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.primary.withValues(alpha: 0.22),
              colors.primary.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, base)),
      )
      ..drawPath(
        line,
        Paint()
          ..color = colors.primary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

    // The latest value, or the one under the finger with its readout.
    final shown = touched ?? points.length - 1;
    final point = points[shown];
    final at = Offset(layout.x(point.day), layout.y(point.value));
    if (touched != null) {
      canvas.drawLine(
        Offset(at.dx, _Layout.above),
        Offset(at.dx, base),
        Paint()
          ..color = colors.outline
          ..strokeWidth = 1,
      );
    }
    canvas
      ..drawCircle(at, 5, Paint()..color = colors.surfaceContainerLowest)
      ..drawCircle(at, 3.5, Paint()..color = colors.primary);
    if (touched != null) {
      _readout(
        canvas,
        layout,
        at,
        '${cardDate(point.day, today: today)}  '
        '${amount(point.value)}',
      );
    }
  }

  void _readout(Canvas canvas, _Layout layout, Offset at, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: readout),
      textDirection: TextDirection.ltr,
    )..layout();
    const pad = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
    final width = painter.width + pad.horizontal;
    final height = painter.height + pad.vertical;
    final left = (at.dx - width / 2)
        .clamp(0, layout.plotWidth - width)
        .toDouble();
    final top = math.max(0, at.dy - height - 12).toDouble();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        const Radius.circular(8),
      ),
      Paint()..color = colors.inverseSurface,
    );
    painter.paint(canvas, Offset(left + pad.left, top + pad.top));
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    TextAlign align = TextAlign.left,
    bool centreY = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    painter.paint(
      canvas,
      Offset(dx, centreY ? at.dy - painter.height / 2 : at.dy),
    );
  }

  static DateTime _middle(DateTime a, DateTime b) =>
      a.add(Duration(hours: b.difference(a).inHours ~/ 2));

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.touched != touched || old.steps != steps;
}
