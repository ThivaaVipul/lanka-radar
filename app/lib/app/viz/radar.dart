import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lanka_radar/app/motion.dart';

/// Something on the radar: where (a fraction of a turn from twelve o'clock,
/// and how far out, 0 at the centre to 1 at the edge) and its colour.
class Blip {
  const Blip({required this.turn, required this.distance, required this.color});

  final double turn;
  final double distance;
  final Color color;
}

/// The radar the app is named for: rings, a cross, the sweep with its fading
/// trail, and blips that glow as the sweep passes them.
class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.turn,
    required this.ink,
    required this.sweepColor,
    this.blips = const [],
    this.rings = 3,
    this.ringAt,
    this.sweeping = true,
    this.stroke = 1,
    this.picked,
  });

  /// Where the sweep is, a fraction of a turn from twelve o'clock.
  final double turn;
  final Color ink;
  final Color sweepColor;
  final List<Blip> blips;
  final int rings;

  /// The rings' distances from the centre (0 to 1), in place of [rings]
  /// evenly spaced.
  final List<double>? ringAt;

  /// The blip to ring, by its index.
  final int? picked;

  /// Draw the sweep; without it the radar is at rest.
  final bool sweeping;
  final double stroke;

  /// How much of a turn the trail behind the sweep covers.
  static const trail = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke;
    final lines = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final at
        in ringAt ?? [for (var ring = 1; ring <= rings; ring++) ring / rings]) {
      canvas.drawCircle(centre, radius * at, lines);
    }
    final cross = Paint()
      ..color = ink.withValues(alpha: ink.a * 0.6)
      ..strokeWidth = stroke;
    canvas
      ..drawLine(centre - Offset(radius, 0), centre + Offset(radius, 0), cross)
      ..drawLine(centre - Offset(0, radius), centre + Offset(0, radius), cross);

    final angle = _angle(turn);
    if (sweeping) {
      // The trail fades in from behind the line, drawn from zero so the
      // gradient's angles stay positive.
      const span = trail * 2 * math.pi;
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas
        ..save()
        ..translate(centre.dx, centre.dy)
        ..rotate(angle - span)
        ..translate(-centre.dx, -centre.dy)
        ..drawArc(
          rect,
          0,
          span,
          true,
          Paint()
            ..shader = SweepGradient(
              center: Alignment.center,
              endAngle: span,
              colors: [
                sweepColor.withValues(alpha: 0),
                sweepColor.withValues(alpha: 0.32),
              ],
            ).createShader(rect),
        )
        ..restore()
        ..drawLine(
          centre,
          centre + Offset(math.cos(angle), math.sin(angle)) * radius,
          Paint()
            ..color = sweepColor
            ..strokeWidth = stroke * 1.5
            ..strokeCap = StrokeCap.round,
        );
    }

    for (final (index, blip) in blips.indexed) {
      final at =
          centre +
          Offset(math.cos(_angle(blip.turn)), math.sin(_angle(blip.turn))) *
              (radius * blip.distance);
      // Brightest just after the sweep passes, dimming over the trail.
      final since = (turn - blip.turn) % 1;
      final glow = sweeping ? (1 - since / (trail * 2)).clamp(0.0, 1.0) : 0.0;
      final size = math.min(radius * 0.03 + 1.5, 5).toDouble();
      if (glow > 0) {
        canvas.drawCircle(
          at,
          size * (1.4 + glow * 1.2),
          Paint()..color = blip.color.withValues(alpha: 0.25 * glow),
        );
      }
      canvas.drawCircle(
        at,
        size,
        Paint()
          ..color = blip.color.withValues(
            alpha: sweeping ? 0.55 + 0.45 * glow : 1,
          ),
      );
      if (index == picked) {
        canvas.drawCircle(
          at,
          size + 5,
          Paint()
            ..color = blip.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  /// Twelve o'clock is a quarter turn back from the canvas's zero angle.
  static double _angle(double turn) => (turn - 0.25) * 2 * math.pi;

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.turn != turn ||
      old.sweeping != sweeping ||
      old.blips != blips ||
      old.picked != picked ||
      old.ink != ink ||
      old.sweepColor != sweepColor;
}

/// A radar that turns while [sweeping] and rests where it stopped otherwise.
/// With animations off it never turns.
class Radar extends StatefulWidget {
  const Radar({
    required this.size,
    this.sweeping = true,
    this.blips = const [],
    this.rings = 3,
    this.ringAt,
    this.picked,
    this.stroke = 1,
    this.rest = 0.12,
    super.key,
  });

  final double size;
  final bool sweeping;
  final List<Blip> blips;
  final int rings;
  final List<double>? ringAt;
  final int? picked;
  final double stroke;

  /// Where the sweep rests when still.
  final double rest;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: Motion.sweep,
    value: widget.rest,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(Radar old) {
    super.didUpdateWidget(old);
    _follow();
  }

  void _follow() {
    final moving =
        widget.sweeping && Motion.of(context, Motion.sweep) != Duration.zero;
    if (moving && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!moving && _turn.isAnimating) {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _turn,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: RadarPainter(
            turn: _turn.value,
            ink: colors.outline.withValues(alpha: 0.55),
            sweepColor: colors.primary,
            blips: widget.blips,
            rings: widget.rings,
            ringAt: widget.ringAt,
            picked: widget.picked,
            stroke: widget.stroke,
          ),
        ),
      ),
    );
  }
}

/// The title bar's radar: it turns while the app refreshes and shows an ochre
/// blip when a source has gone quiet. A tap opens the sources.
class RadarStatus extends StatelessWidget {
  const RadarStatus({
    required this.refreshing,
    required this.quiet,
    required this.onTap,
    super.key,
  });

  final bool refreshing;

  /// A source has gone quiet.
  final bool quiet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: quiet ? 'A source has gone quiet' : 'Sources',
      onPressed: onTap,
      icon: Radar(
        size: 22,
        rings: 2,
        stroke: 1.2,
        sweeping: refreshing,
        blips: [
          if (quiet) Blip(turn: 0.38, distance: 0.62, color: colors.tertiary),
        ],
      ),
    );
  }
}
