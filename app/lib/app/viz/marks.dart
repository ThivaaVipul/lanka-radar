import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lanka_radar/app/viz/sparkline.dart';

/// A ring that fills toward something, with [child] in the middle. It fills
/// itself in once when first shown.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    required this.progress,
    required this.child,
    this.size = 48,
    this.stroke = 4,
    this.color,
    super.key,
  });

  /// 0 empty to 1 full.
  final double progress;
  final Widget child;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: DrawIn(
        builder: (context, drawn) => CustomPaint(
          painter: _RingPainter(
            progress: progress.clamp(0.0, 1.0) * drawn,
            color: color ?? colors.primary,
            track: colors.surfaceContainerHighest,
            stroke: stroke,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        progress * 2 * math.pi,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Where a range sits among others: a track from [min] to [max] (the cheapest
/// and dearest anywhere), with [low] to [high] on it.
class RangeTrack extends StatelessWidget {
  const RangeTrack({
    required this.min,
    required this.max,
    required this.low,
    required this.high,
    this.width = 72,
    super.key,
  });

  final double min;
  final double max;
  final double low;
  final double high;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DrawIn(
      builder: (context, drawn) => CustomPaint(
        size: Size(width, 10),
        painter: _TrackPainter(
          min: min,
          max: max,
          low: low,
          high: high,
          drawn: drawn,
          track: colors.surfaceContainerHighest,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.min,
    required this.max,
    required this.low,
    required this.high,
    required this.drawn,
    required this.track,
    required this.color,
  });

  final double min;
  final double max;
  final double low;
  final double high;
  final double drawn;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const end = 3.0;
    final width = size.width - end * 2;
    double x(double value) =>
        end + (max == min ? 0.5 : (value - min) / (max - min)) * width;
    canvas.drawLine(
      Offset(end, y),
      Offset(size.width - end, y),
      Paint()
        ..color = track
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    final middle = (x(low) + x(high)) / 2;
    final half = (x(high) - x(low)) / 2 * drawn;
    canvas.drawLine(
      Offset(middle - half, y),
      Offset(middle + half, y),
      Paint()
        ..color = color
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.drawn != drawn ||
      old.low != low ||
      old.high != high ||
      old.min != min ||
      old.max != max;
}

/// A change as a bar from a middle line: ochre to the right for a rise, teal
/// to the left for a fall, as long as the change (up to [full], a fraction).
class ChangeBar extends StatelessWidget {
  const ChangeBar({
    required this.change,
    this.full = 0.3,
    this.width = 56,
    super.key,
  });

  /// The change as a fraction: 0.25 for 25% up.
  final double change;

  /// The change that fills half the bar's width.
  final double full;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DrawIn(
      builder: (context, drawn) => CustomPaint(
        size: Size(width, 12),
        painter: _ChangePainter(
          change: (change / full).clamp(-1.0, 1.0) * drawn,
          rise: colors.tertiary,
          fall: colors.primary,
          axis: colors.outlineVariant,
        ),
      ),
    );
  }
}

class _ChangePainter extends CustomPainter {
  _ChangePainter({
    required this.change,
    required this.rise,
    required this.fall,
    required this.axis,
  });

  /// -1 to 1.
  final double change;
  final Color rise;
  final Color fall;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.width / 2;
    if (change == 0) {
      // No change: a short level mark.
      canvas.drawLine(
        Offset(middle - 4, size.height / 2),
        Offset(middle + 4, size.height / 2),
        Paint()
          ..color = axis
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    canvas.drawLine(
      Offset(middle, 0),
      Offset(middle, size.height),
      Paint()
        ..color = axis
        ..strokeWidth = 1.5,
    );
    final length = math.max(3, change.abs() * (middle - 2));
    final rect = change > 0
        ? Rect.fromLTWH(middle + 2, 2, length.toDouble(), size.height - 4)
        : Rect.fromLTWH(
            middle - 2 - length,
            2,
            length.toDouble(),
            size.height - 4,
          );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = change > 0 ? rise : fall,
    );
  }

  @override
  bool shouldRepaint(_ChangePainter old) => old.change != change;
}
