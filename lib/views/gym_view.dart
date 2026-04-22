import 'package:flutter/material.dart';

class GymView extends StatelessWidget {
  const GymView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("THE GYM", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.bold, letterSpacing: 1)),
        iconTheme: const IconThemeData(color: Color(0xFF39FF14)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(color: Color(0xFF39FF14), height: 1.0, thickness: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Train your combat stats here. Each session costs Energy.",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Coming Soon: The actual training buttons and logic
            _buildGymEquipmentCard("BENCH PRESS", "STRENGTH", "Dmg & Violence", Icons.fitness_center),
            _buildGymEquipmentCard("HEAVY BAG", "DEFENSE", "Mitigation", Icons.shield),
            _buildGymEquipmentCard("SPEED BAG", "DEXTERITY", "Stealth & Pickpocket", Icons.track_changes),
            _buildGymEquipmentCard("TREADMILL", "SPEED", "Evasion & Theft", Icons.directions_run),
          ],
        ),
      ),
    );
  }

  Widget _buildGymEquipmentCard(String title, String stat, String sub, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text("+ $stat ($sub)", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Wire up to Backend /train route
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1),
              side: const BorderSide(color: Color(0xFF39FF14)),
            ),
            child: const Text("TRAIN (10E)", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}