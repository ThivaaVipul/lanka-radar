import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/features/power/hero_status.dart';
import 'package:lanka_radar/features/power/widgets/power_line.dart';

/// The Power tab's top card: a short line on how the places stand (and one
/// more when there is something to say), the power line through the places,
/// when it last looked, and an action when one is needed.
class PowerCard extends StatelessWidget {
  const PowerCard({
    required this.status,
    required this.onAction,
    required this.onRefresh,
    super.key,
  });

  final HeroStatus status;
  final VoidCallback onAction;

  /// Looks again; null when there is nothing to look for.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final medium = Motion.of(context, Motion.medium);
    final (background, title, accent, onAccent) = switch (status.tone) {
      HeroTone.clear || HeroTone.calm => (
        colors.surfaceContainerLowest,
        colors.onSurface,
        colors.primary,
        colors.onPrimary,
      ),
      HeroTone.attention => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        colors.tertiary,
        colors.onTertiary,
      ),
      // A failed look is quieter than a cut: only its button says so.
      HeroTone.trouble => (
        colors.surfaceContainerLowest,
        colors.onSurface,
        colors.error,
        colors.onError,
      ),
    };
    final muted = title.withValues(alpha: 0.72);
    return AnimatedContainer(
      duration: Motion.of(context, Motion.long),
      curve: Motion.standard,
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SmoothSize(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: medium,
                          transitionBuilder: fadeRise,
                          layoutBuilder: _alignStart,
                          child: Semantics(
                            key: ValueKey(status.title),
                            header: true,
                            child: Text(
                              status.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: title,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (status.detail case final detail?)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              detail,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // The line and "Checking..." already show a look under way.
                if (onRefresh case final refresh?
                    when status.action != HeroAction.retry)
                  IconButton(
                    tooltip: 'Check again',
                    color: muted,
                    onPressed: status.checking ? null : refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: PowerLine(nodes: status.nodes, mode: status.line),
            ),
            if (status.checked case final checked?) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _LiveDot(
                    color: status.live ? accent : muted.withValues(alpha: 0.5),
                    breathing: status.live,
                  ),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: medium,
                    child: Text(
                      status.live ? 'Live, ${_lower(checked)}' : checked,
                      key: ValueKey((checked, status.live)),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (status.actionLabel case final label?) ...[
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: onAccent,
                  minimumSize: const Size(64, 40),
                ),
                onPressed: onAction,
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _lower(String text) =>
      text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);

  /// Keeps switching text pinned to the left edge instead of centered.
  static Widget _alignStart(Widget? current, List<Widget> previous) => Stack(
    alignment: AlignmentDirectional.topStart,
    children: [...previous, ?current],
  );
}

/// A small dot that breathes while the last look is fresh.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color, required this.breathing});

  final Color color;
  final bool breathing;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final breathe =
        widget.breathing && !MediaQuery.disableAnimationsOf(context);
    if (breathe && !_breath.isAnimating) {
      _breath.repeat();
    } else if (!breathe && _breath.isAnimating) {
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 16,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, _) {
          final t = _breath.value;
          final halo = math.sin(t * math.pi);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 8 + 8 * t,
                height: 8 + 8 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.35 * halo),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
