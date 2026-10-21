import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/core/data/price_history.dart';

/// Runs [builder] from 0 to 1 once, when first shown, so a line can draw
/// itself; with animations off it starts at 1.
class DrawIn extends StatelessWidget {
  const DrawIn({required this.builder, super.key});

  final Widget Function(BuildContext context, double progress) builder;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.draw);
    if (duration == Duration.zero) {
      return builder(context, 1);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Motion.enter,
      builder: (context, progress, _) => builder(context, progress),
    );
  }
}

/// A value's history in a line the height of a row, with a dot on the latest:
/// steps for prices set on a day, a line for a rate. It draws itself once.
class Sparkline extends StatelessWidget {
  const Sparkline({
    required this.points,
    this.steps = false,
    this.until,
    this.color,
    this.height = 28,
    this.area = false,
    super.key,
  });

  /// Oldest first.
  final List<PricePoint> points;
  final bool steps;

  /// The day the last step runs to, when later than the last point.
  final DateTime? until;
  final Color? color;
  final double height;

  /// Tint the area under the line.
  final bool area;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(height: height);
    }
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: DrawIn(
        builder: (context, progress) => CustomPaint(
          size: Size.infinite,
          painter: _SparkPainter(
            points: points,
            steps: steps,
            until: until,
            color: color ?? colors.primary,
            dotRing: colors.surfaceContainerLowest,
            area: area,
            progress: progress,
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.points,
    required this.steps,
    required this.until,
    required this.color,
    required this.dotRing,
    required this.area,
    required this.progress,
  });

  final List<PricePoint> points;
  final bool steps;
  final DateTime? until;
  final Color color;
  final Color dotRing;
  final bool area;
  final double progress;

  /// Room for the end dot.
  static const _pad = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final first = points.first.day;
    final lastPoint = points.last.day;
    final last = until != null && until!.isAfter(lastPoint)
        ? until!
        : lastPoint;
    final span = math.max(1, last.difference(first).inHours);
    final values = [for (final point in points) point.value];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final width = size.width - _pad * 2;
    final height = size.height - _pad * 2;
    double x(DateTime day) =>
        _pad + day.difference(first).inHours / span * width;
    double y(double value) => high == low
        ? _pad + height / 2
        : _pad + (high - value) / (high - low) * height;

    final line = Path();
    for (final (index, point) in points.indexed) {
      final at = Offset(x(point.day), y(point.value));
      if (index == 0) {
        line.moveTo(at.dx, at.dy);
      } else if (steps) {
        line
          ..lineTo(at.dx, y(points[index - 1].value))
          ..lineTo(at.dx, at.dy);
      } else {
        line.lineTo(at.dx, at.dy);
      }
    }
    if (steps) {
      line.lineTo(x(last), y(points.last.value));
    }

    final drawn = progress >= 1 ? line : _part(line, progress);
    final end = _end(drawn);
    if (area && end != null) {
      final fill = Path.from(drawn)
        ..lineTo(end.dx, size.height)
        ..lineTo(_pad, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (end != null) {
      canvas
        ..drawCircle(end, 4, Paint()..color = dotRing)
        ..drawCircle(end, 2.75, Paint()..color = color);
    }
  }

  /// The first [fraction] of [path]'s length.
  static Path _part(Path path, double fraction) {
    final out = Path();
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, metric) => sum + metric.length);
    var left = total * fraction;
    for (final metric in metrics) {
      final take = math.min(left, metric.length);
      out.addPath(metric.extractPath(0, take), Offset.zero);
      left -= take;
      if (left <= 0) {
        break;
      }
    }
    return out;
  }

  /// Where [path] ends.
  static Offset? _end(Path path) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) {
      return null;
    }
    final metric = metrics.last;
    return metric.getTangentForOffset(metric.length)?.position;
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress ||
      old.points != points ||
      old.color != color ||
      old.until != until;
}
