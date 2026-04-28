import 'package:flutter/material.dart';

class CrewStatusBadge extends StatelessWidget {
  final String domain;
  final String assignment;

  const CrewStatusBadge({super.key, required this.domain, required this.assignment});

  Color _getDomainColor() {
    switch (domain.toUpperCase()) {
      case 'CRIMES': return Colors.orangeAccent;
      case 'COMPANY': return Colors.cyanAccent;
      case 'WARS': return Colors.redAccent;
      case 'CASINO': return Colors.purpleAccent;
      default: return const Color(0xFF39FF14); // Neon Green for IDLE
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getDomainColor().withOpacity(0.1),
        border: Border.all(color: _getDomainColor(), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        assignment == 'UNASSIGNED' ? 'IDLE' : assignment.toUpperCase(),
        style: TextStyle(
          color: _getDomainColor(),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}