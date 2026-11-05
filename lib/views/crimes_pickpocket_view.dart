import 'package:flutter/material.dart';

class CrimesPickpocketView extends StatelessWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;
  final Function(Map<String, dynamic>) onStateChange;

  const CrimesPickpocketView({
    super.key,
    required this.userData,
    required this.onBack,
    required this.onStateChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1A1A1A),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Color(0xFF39FF14),
                  size: 16,
                ),
                onPressed: onBack,
              ),
              const Text(
                'PICKPOCKETING',
                style: TextStyle(
                  color: Color(0xFF39FF14),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'PICKPOCKETING PAUSED\n\n'
                'The previous client generated target activity and success '
                'modifiers locally. Execution will reopen only after target '
                'activity is issued and persisted by the authoritative server.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
