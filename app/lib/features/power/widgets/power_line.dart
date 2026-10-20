import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How a place stands on the line.
enum NodeState { clear, cut, waiting, unfinished }

/// A place on the power line.
typedef LineNode = ({String name, NodeState state});

/// How the line itself looks.
enum LineMode {
  /// Current flows along it.
  flowing,

  /// A bright reading sweeps along it while the phone looks.
  checking,

  /// Dashed and grey: EDLCare isn't answering.
  down,
}

/// A power line running through each place watched, each place a small
/// circle with its initial. Current flows along it while all is clear; it
/// breaks with a spark at a place with a cut. Everything holds still
/// when animations are off.
class PowerLine extends StatefulWidget {
  const PowerLine({required this.nodes, required this.mode, super.key});

  final List<LineNode> nodes;
  final LineMode mode;

  @override
  State<PowerLine> createState() => _PowerLineState();
}

class _PowerLineState extends State<PowerLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  static const _node = 34.0;
  static const _line = 46.0;
  static const _label = 22.0;

  bool get _animate =>
      !MediaQuery.disableAnimationsOf(context) && widget.mode != LineMode.down;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PowerLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_animate && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!_animate && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final nodes = widget.nodes;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final xs = [
            for (var index = 0; index < nodes.length; index++)
              width * (index + 1) / (nodes.length + 1),
          ];
          return SizedBox(
            height: _line + _label,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  bottom: _label,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _LinePainter(
                        xs: xs,
                        cut: [
                          for (final node in nodes) node.state == NodeState.cut,
                        ],
                        mode: widget.mode,
                        current: colors.primary,
                        rest: colors.outline,
                        spark: colors.tertiary,
                        clock: _animate ? _clock : null,
                      ),
                    ),
                  ),
                ),
                for (final (index, node) in nodes.indexed) ...[
                  Positioned(
                    left: xs[index] - _node / 2,
                    top: (_line - _node) / 2,
                    child: _Node(node: node, clock: _clock),
                  ),
                  Positioned(
                    left: xs[index] - 60,
                    width: 120,
                    top: _line + 2,
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: node.state == NodeState.cut
                            ? colors.tertiary
                            : colors.onSurfaceVariant,
                        fontWeight: node.state == NodeState.cut
                            ? FontWeight.w600
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A place on the line: its initial in a circle, teal while clear, ochre and
/// glowing while it has a cut, quiet while it waits, hollow while it still
/// needs setting up.
class _Node extends StatelessWidget {
  const _Node({required this.node, required this.clock});

  final LineNode node;
  final Animation<double> clock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (fill, ink) = switch (node.state) {
      NodeState.clear => (colors.primary, colors.onPrimary),
      NodeState.cut => (colors.tertiary, colors.onTertiary),
      NodeState.waiting => (colors.surfaceContainerHighest, colors.onSurface),
      NodeState.unfinished => (colors.surface, colors.onSurfaceVariant),
    };
    final initial = node.name.trim().isEmpty
        ? '?'
        : node.name.trim().characters.first.toUpperCase();
    final still = MediaQuery.disableAnimationsOf(context);
    Widget circle = AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 300),
      width: _PowerLineState._node,
      height: _PowerLineState._node,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: node.state == NodeState.unfinished
            ? Border.all(color: colors.outline, width: 1.5)
            : Border.all(color: colors.surfaceContainerLowest, width: 3),
      ),
      child: Text(
        initial,
        style: theme.textTheme.labelLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (node.state == NodeState.cut && !still) {
      // A soft glow that swells and fades with the line's clock.
      circle = AnimatedBuilder(
        animation: clock,
        builder: (context, child) {
          final glow = 0.5 + 0.5 * math.sin(clock.value * 2 * math.pi);
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colors.tertiary.withValues(alpha: 0.2 + 0.3 * glow),
                  blurRadius: 8 + 10 * glow,
                  spreadRadius: 1 + 3 * glow,
                ),
              ],
            ),
            child: child,
          );
        },
        child: circle,
      );
    }
    return circle;
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.xs,
    required this.cut,
    required this.mode,
    required this.current,
    required this.rest,
    required this.spark,
    this.clock,
  }) : super(repaint: clock);

  /// Where each place sits along the line.
  final List<double> xs;

  /// Which places have a cut.
  final List<bool> cut;
  final LineMode mode;
  final Color current;
  final Color rest;
  final Color spark;

  /// Drives the flow and the sweep; null holds them still.
  final Animation<double>? clock;

  /// How far each side of a cut's node the line is broken.
  static const _gap = 28.0;
  static const _pulseSpacing = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final width = size.width;
    final breaks = [
      for (final (index, x) in xs.indexed)
        if (cut[index]) (x - _gap, x + _gap),
    ];

    // The stretches of line between the breaks.
    final spans = <(double, double)>[];
    var from = 0.0;
    for (final (start, end) in breaks) {
      if (start > from) {
        spans.add((from, start));
      }
      from = end;
    }
    if (from < width) {
      spans.add((from, width));
    }

    final base = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (mode == LineMode.down) {
      base.color = rest.withValues(alpha: 0.5);
      for (var x = 0.0; x < width; x += 12) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 6, width), y), base);
      }
      return;
    }
    base.color = current.withValues(alpha: 0.25);
    for (final (start, end) in spans) {
      canvas.drawLine(Offset(start, y), Offset(end, y), base);
    }

    // Each break: the cut ends of the line in ochre, sparking into the gap.
    final broken = Paint()
      ..color = spark
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final (start, end) in breaks) {
      canvas
        ..drawLine(Offset(start - 8, y), Offset(start, y), broken)
        ..drawLine(Offset(end, y), Offset(end + 8, y), broken);
      _spark(canvas, Offset(start, y), 1);
      _spark(canvas, Offset(end, y), -1);
    }

    final t = clock?.value ?? 0;
    if (mode == LineMode.flowing) {
      // Pulses of current running left to right, only where the line holds.
      final pulse = Paint()
        ..color = current
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final shift = (t * _pulseSpacing * 4) % _pulseSpacing;
      for (final (start, end) in spans) {
        for (
          var x = start - _pulseSpacing + shift;
          x < end;
          x += _pulseSpacing
        ) {
          final a = math.max(x, start);
          final b = math.min(x + 8, end);
          if (b > a) {
            canvas.drawLine(Offset(a, y), Offset(b, y), pulse);
          }
        }
      }
    } else {
      // A bright reading sweeping along the line.
      final head = -80 + (width + 160) * Curves.easeInOut.transform(t);
      final sweep = Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            current.withValues(alpha: 0),
            current,
            current.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(head - 80, y - 2, 160, 4));
      canvas.drawLine(
        Offset(math.max(0, head - 80), y),
        Offset(math.min(width, head + 80), y),
        sweep,
      );
    }
  }

  /// Three short strokes leaving a cut end, fanning toward [side].
  void _spark(Canvas canvas, Offset end, int side) {
    final thin = Paint()
      ..color = spark
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final angle in const [-0.9, 0.0, 0.9]) {
      final direction = Offset(side * math.cos(angle), math.sin(angle));
      canvas.drawLine(end + direction * 4, end + direction * 9, thin);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.mode != mode ||
      old.current != current ||
      old.rest != rest ||
      old.spark != spark ||
      old.clock != clock ||
      !_same(old.xs, xs) ||
      !_same(old.cut, cut);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
