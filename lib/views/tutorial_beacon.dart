// File Path: lib/views/tutorial_beacon.dart

import 'package:flutter/material.dart';

class TutorialBeacon extends StatefulWidget {
  final String id;
  final String? activeId;
  final Widget child;
  final Color glowColor;
  final double borderRadius;

  const TutorialBeacon({
    super.key,
    required this.id,
    required this.activeId,
    required this.child,
    this.glowColor = Colors.orangeAccent,
    this.borderRadius = 8.0,
  });

  @override
  State<TutorialBeacon> createState() => _TutorialBeaconState();
}

class _TutorialBeaconState extends State<TutorialBeacon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _animation = Tween<double>(begin: 2.0, end: 12.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isActive = widget.id == widget.activeId;

    if (!isActive) return widget.child;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(0.6),
                blurRadius: _animation.value,
                spreadRadius: _animation.value / 2,
              )
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}