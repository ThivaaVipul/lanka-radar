import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lanka_radar/app/motion.dart';

/// A power cut on Today, as a tile like the numbers: a bulb in a ring, then
/// what and where, its time large, and how long until it starts (or ends).
/// Before a cut the bulb is lit and its ring counts down to it; once the cut
/// is on, the bulb flickers off, the tile turns ochre and the ring shows what
/// is left of the cut.
class CutTile extends StatefulWidget {
  const CutTile({
    required this.title,
    required this.time,
    this.rest,
    this.start,
    this.end,
    this.on = false,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  /// "Load shedding at Home".
  final String title;

  /// Large: "19:30", or "since 09:24" for a breakdown.
  final String time;

  /// After it, smaller: "to 20:30".
  final String? rest;

  /// When it starts and ends, if known; the ring needs both.
  final DateTime? start;
  final DateTime? end;

  /// The cut is on now.
  final bool on;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The countdown ring is full this long before a cut.
  static const ringSpan = Duration(hours: 12);

  @override
  State<CutTile> createState() => _CutTileState();
}

class _CutTileState extends State<CutTile> {
  DateTime _now = DateTime.now();
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    // The countdown and the ring move on by themselves.
    _clock = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  /// "in 3 h 58 m", "tomorrow" or "ends in 45 m".
  String? get _countdown {
    final start = widget.start;
    final end = widget.end;
    if (widget.on) {
      return end == null ? null : 'ends in ${_span(end.difference(_now))}';
    }
    if (start == null) {
      return null;
    }
    final days = DateTime.utc(
      start.year,
      start.month,
      start.day,
    ).difference(DateTime.utc(_now.year, _now.month, _now.day)).inDays;
    return days >= 1 ? 'tomorrow' : 'in ${_span(start.difference(_now))}';
  }

  /// How full the ring is: the time left before the cut out of
  /// [CutTile.ringSpan], or once it is on, the part of it still to go.
  double? get _ring {
    final start = widget.start;
    final end = widget.end;
    if (start == null || end == null) {
      return null;
    }
    double share(Duration part, Duration whole) => whole.inSeconds <= 0
        ? 0
        : (part.inSeconds / whole.inSeconds).clamp(0.0, 1.0);
    return widget.on
        ? share(end.difference(_now), end.difference(start))
        : share(start.difference(_now), CutTile.ringSpan);
  }

  static String _span(Duration duration) {
    final minutes = math.max(1, duration.inMinutes);
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return hours == 0
        ? '$rest m'
        : rest == 0
        ? '$hours h'
        : '$hours h $rest m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final on = widget.on;
    final ink = on ? colors.onTertiaryContainer : colors.onSurface;
    final muted = on
        ? colors.onTertiaryContainer.withValues(alpha: 0.72)
        : colors.onSurfaceVariant;
    final countdown = _countdown;
    final start = widget.start;
    // Within the hour, the countdown turns ochre.
    final soon =
        !on &&
        start != null &&
        start.difference(_now) < const Duration(hours: 1);
    return Card(
      margin: EdgeInsets.zero,
      color: on ? colors.tertiaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            children: [
              _Bulb(on: on, ring: _ring, soon: soon),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: widget.time,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.rest case final rest?)
                            TextSpan(
                              text: '  $rest',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (countdown != null) ...[
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: Motion.of(context, Motion.medium),
                        transitionBuilder: fadeRise,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: AlignmentDirectional.centerStart,
                          children: [...previous, ?current],
                        ),
                        child: Text(
                          countdown,
                          key: ValueKey(countdown),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: on || soon ? ink : colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bulb in its ring. Lit, it glows teal with rays that breathe; when the
/// cut comes on it flickers off and keeps a slow ochre glow. Still when the
/// phone's animations are off.
class _Bulb extends StatefulWidget {
  const _Bulb({required this.on, required this.ring, required this.soon});

  final bool on;

  /// How full the ring is, or null for no ring.
  final double? ring;

  /// The cut is less than an hour away.
  final bool soon;

  @override
  State<_Bulb> createState() => _BulbState();
}

class _BulbState extends State<_Bulb> with TickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// The flicker as the power goes, played once.
  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  static const size = 64.0;

  bool get _still => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Bulb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on && !oldWidget.on) {
      _flicker.value = 0;
    }
    _sync();
  }

  void _sync() {
    if (_still) {
      _breath
        ..stop()
        ..value = 0.5;
      _flicker.value = 1;
      return;
    }
    if (!_breath.isAnimating) {
      unawaited(_breath.repeat());
    }
    if (widget.on && _flicker.value < 1 && !_flicker.isAnimating) {
      unawaited(_flicker.forward());
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _flicker.dispose();
    super.dispose();
  }

  /// How lit the bulb is while the power goes: a few stutters, then out.
  static double _lit(double t) {
    const steps = [1.0, 0.25, 0.9, 0.1, 0.6, 0.0, 0.3, 0.0];
    final at = (t * (steps.length - 1)).clamp(0.0, steps.length - 1.0);
    final i = at.floor();
    if (i >= steps.length - 1) {
      return steps.last;
    }
    // Snaps rather than fades, as a failing bulb does.
    return at - i < 0.6 ? steps[i] : steps[i + 1];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final on = widget.on;
    final ring = widget.ring;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          // The ring sweeps in when the tile appears.
          tween: Tween(begin: 0, end: ring ?? 0),
          duration: Motion.of(context, Motion.glide),
          curve: Motion.enter,
          builder: (context, sweep, _) => AnimatedBuilder(
            animation: Listenable.merge([_breath, _flicker]),
            builder: (context, _) => CustomPaint(
              painter: _BulbPainter(
                lit: on ? _lit(_flicker.value) : 1,
                breath: math.sin(_breath.value * 2 * math.pi) * 0.5 + 0.5,
                ring: ring == null ? null : sweep,
                light: colors.primary,
                warn: on ? colors.onTertiaryContainer : colors.tertiary,
                glass: on
                    ? colors.onTertiaryContainer.withValues(alpha: 0.75)
                    : colors.onSurfaceVariant,
                track: on
                    ? colors.onTertiaryContainer.withValues(alpha: 0.16)
                    : colors.outlineVariant,
                ringColor: on || widget.soon ? colors.tertiary : colors.primary,
                cut: on,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BulbPainter extends CustomPainter {
  _BulbPainter({
    required this.lit,
    required this.breath,
    required this.ring,
    required this.light,
    required this.warn,
    required this.glass,
    required this.track,
    required this.ringColor,
    required this.cut,
  });

  /// How lit the bulb is, from 0 (off) to 1.
  final double lit;

  /// The rays' and glow's slow swell, from 0 to 1.
  final double breath;

  /// How full the ring is; null draws none.
  final double? ring;
  final Color light;
  final Color warn;
  final Color glass;
  final Color track;
  final Color ringColor;

  /// The cut is on: an ochre glow instead of light.
  final bool cut;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ring = this.ring;
    if (ring != null) {
      final rect = Rect.fromCircle(center: c, radius: size.width / 2 - 2);
      canvas
        ..drawArc(
          rect,
          0,
          2 * math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = track,
        )
        ..drawArc(
          rect,
          -math.pi / 2,
          2 * math.pi * ring,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = ringColor,
        );
    }

    final globe = c.translate(0, -5);
    const r = 12.0;

    // The glow: teal light while lit, a low ochre warmth once the cut is on.
    final glow = cut ? 0.18 + 0.14 * breath : lit * (0.22 + 0.16 * breath);
    canvas.drawCircle(
      globe,
      r + 8 + 3 * breath,
      Paint()
        ..shader = RadialGradient(
          colors: [
            (cut ? warn : light).withValues(alpha: glow),
            (cut ? warn : light).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: globe, radius: r + 11)),
    );

    // Rays, only while it gives light.
    if (lit > 0.05) {
      final ray = Paint()
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = light.withValues(alpha: lit * (0.45 + 0.4 * breath));
      for (var i = 0; i < 7; i++) {
        final angle = -math.pi + math.pi * (i + 0.5) / 7;
        final direction = Offset(math.cos(angle), math.sin(angle));
        final from = r + 3 + 1.5 * breath;
        canvas.drawLine(
          globe + direction * from,
          globe + direction * (from + 3 + breath),
          ray,
        );
      }
    }

    // The glass: a globe narrowing to a neck.
    final neckTop = globe.dy + r * 0.62;
    final neckBottom = globe.dy + r + 3;
    final bulb = Path()
      ..moveTo(globe.dx - r * 0.62, neckTop)
      ..arcToPoint(
        Offset(globe.dx + r * 0.62, neckTop),
        radius: const Radius.circular(r),
        largeArc: true,
      )
      ..lineTo(globe.dx + 4.5, neckBottom)
      ..lineTo(globe.dx - 4.5, neckBottom)
      ..close();
    canvas
      ..drawPath(
        bulb,
        Paint()..color = light.withValues(alpha: 0.10 + 0.32 * lit),
      )
      ..drawPath(
        bulb,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round
          ..color = Color.lerp(glass, light, lit)!,
      );

    // The filament: two wires up from the neck, joined in a loop.
    final filament = Path()
      ..moveTo(globe.dx - 2.6, neckTop + 1.5)
      ..lineTo(globe.dx - 2.6, globe.dy + 0.5)
      ..arcToPoint(
        Offset(globe.dx + 2.6, globe.dy + 0.5),
        radius: const Radius.circular(2.6),
      )
      ..lineTo(globe.dx + 2.6, neckTop + 1.5);
    canvas.drawPath(
      filament,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(glass.withValues(alpha: 0.6), light, lit)!,
    );

    // The screw base.
    final base = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = glass;
    for (final (i, half) in const [4.0, 3.2, 1.6].indexed) {
      final y = neckBottom + 2.5 + i * 2.6;
      canvas.drawLine(
        Offset(globe.dx - half, y),
        Offset(globe.dx + half, y),
        base,
      );
    }
  }

  @override
  bool shouldRepaint(_BulbPainter old) =>
      old.lit != lit ||
      old.breath != breath ||
      old.ring != ring ||
      old.light != light ||
      old.warn != warn ||
      old.glass != glass ||
      old.track != track ||
      old.ringColor != ringColor ||
      old.cut != cut;
}
