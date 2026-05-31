import 'package:flutter/material.dart';

class TutorialIntroOverlay extends StatelessWidget {
  final VoidCallback onContinue;

  const TutorialIntroOverlay({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onContinue,
        child: Container(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_city, color: Color(0xFF39FF14), size: 60),
                  const SizedBox(height: 24),
                  const Text("WELCOME TO COLD STREETS", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
                  const SizedBox(height: 32),
                  const Text("You wake up in an alleyway. No money. No friends.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                  const SizedBox(height: 16),
                  const Text("The only thing in your pocket is a cheap burner phone.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                  const SizedBox(height: 16),
                  const Text("It starts vibrating...", textAlign: TextAlign.center, style: TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 60),
                  Text("(Tap anywhere to continue)", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12, letterSpacing: 1.0)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}