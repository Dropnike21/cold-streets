import 'package:flutter/material.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          const Text("CORE ATTRIBUTES (D.I.S.S.)", style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.5)),
          const Divider(color: Color(0xFF333333)),
          _buildStatRow("STRENGTH", "10", "Dmg & Violence"),
          _buildStatRow("DEFENSE", "10", "Mitigation"),
          _buildStatRow("DEXTERITY", "10", "Stealth & Pickpocket"),
          _buildStatRow("SPEED", "10", "Evasion & Theft"),
          _buildStatRow("INTELLIGENCE", "10", "Hacking & Strategy"),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(sub, style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
          Text(value, style: const TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}