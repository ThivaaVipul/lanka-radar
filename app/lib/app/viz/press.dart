import 'package:flutter/material.dart';
import 'package:lanka_radar/app/motion.dart';

/// Sinks a little under the finger, so a tile feels pressed.
class Press extends StatefulWidget {
  const Press({required this.child, super.key});

  final Widget child;

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) {
      setState(() => _down = down);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Motion.of(context, Motion.short),
        curve: Motion.standard,
        child: widget.child,
      ),
    );
  }
}
