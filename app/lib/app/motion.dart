import 'package:flutter/material.dart';

/// The app's motion, as in Zen Mode: a few durations and curves used everywhere,
/// so every change moves the same way. Motion only answers something you did or
/// something that changed, and all of it stops when Android's "Remove
/// animations" setting is on.
abstract final class Motion {
  /// Toggles, selections, the map pin.
  static const short = Duration(milliseconds: 160);

  /// Content changing in place: a section opening, a status changing.
  static const medium = Duration(milliseconds: 300);

  /// Screens and large surfaces.
  static const long = Duration(milliseconds: 450);

  /// The map gliding to a new spot.
  static const glide = Duration(milliseconds: 900);

  /// Most motion: a quick start and a gentle landing.
  static const Curve standard = Curves.easeInOutCubicEmphasized;

  /// Things arriving on screen.
  static const Curve enter = Curves.easeOutCubic;

  /// [duration], or none when the user turned animations off.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Fades content in and out while it grows or shrinks, for sections that
/// appear and disappear inside a form.
class RevealSwitcher extends StatelessWidget {
  const RevealSwitcher({required this.child, super.key});

  /// Give it a key that changes with what it shows.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.enter,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: AlignmentDirectional.topStart,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: child,
    );
  }
}

/// A fade with a short rise, for text that changes in place.
Widget fadeRise(Widget child, Animation<double> animation) => FadeTransition(
  opacity: animation,
  child: SlideTransition(
    position: Tween(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(animation),
    child: child,
  ),
);

/// Grows or shrinks with its child; with animations off it just takes the new
/// size, since an AnimatedSize with no duration fights its own layout.
class SmoothSize extends StatelessWidget {
  const SmoothSize({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.medium);
    if (duration == Duration.zero) {
      return child;
    }
    return AnimatedSize(
      duration: duration,
      curve: Motion.standard,
      alignment: Alignment.topLeft,
      child: child,
    );
  }
}
