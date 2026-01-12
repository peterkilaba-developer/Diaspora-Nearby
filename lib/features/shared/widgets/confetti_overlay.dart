import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';

// Global Key to access the overlay state from anywhere
final GlobalKey<ConfettiOverlayState> confettiOverlayKey = GlobalKey<ConfettiOverlayState>();

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
    _controllerCenter = ConfettiController(duration: const Duration(seconds: 3));
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
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _controllerCenter,
            blastDirection: pi / 2, // down
            maxBlastForce: 5,
            minBlastForce: 2,
            emissionFrequency: 0.05,
            numberOfParticles: 20,
            gravity: 0.2,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
            ],
          ),
        ),
      ],
    );
  }
}
