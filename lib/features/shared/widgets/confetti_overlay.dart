import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';

// Global Key to access the overlay state from anywhere
final GlobalKey<ConfettiOverlayState> confettiOverlayKey =
    GlobalKey<ConfettiOverlayState>();

class ConfettiOverlay extends StatefulWidget {
  final Widget child;

  const ConfettiOverlay({super.key, required this.child});

  @override
  State<ConfettiOverlay> createState() => ConfettiOverlayState();
}

class ConfettiOverlayState extends State<ConfettiOverlay> {
  late ConfettiController _controllerCenter;

  @override
  void initState() {
    super.initState();
    _controllerCenter = ConfettiController(
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _controllerCenter.dispose();
    super.dispose();
  }

  void play() {
    _controllerCenter.play();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _controllerCenter,
              blastDirection: pi / 2, // down
              maxBlastForce: 3, // [SUBTLE] Reduced from 5
              minBlastForce: 1, // [SUBTLE] Reduced from 2
              emissionFrequency: 0.05,
              numberOfParticles: 5, // [SUBTLE] Reduced from 20
              gravity: 0.3, // [SUBTLE] Increased gravity for faster fall
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
