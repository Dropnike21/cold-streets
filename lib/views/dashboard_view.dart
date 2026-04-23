// File Path: lib/views/dashboard_view.dart

import 'package:flutter/material.dart';

class DashboardView extends StatelessWidget {
  final Map<String, dynamic> userData;

  const DashboardView({super.key, required this.userData});

  // Helper for safe strings
  String _safeStr(dynamic value, String fallback) => value?.toString() ?? fallback;

  // Bulletproof parsers for V1.2 "Trillions" Economy
  double _parseSafeDouble(dynamic value) => (value is num) ? value.toDouble() : double.tryParse(value?.toString() ?? '0.0') ?? 0.0;

  // Use num instead of int to prevent overflow issues during parsing
  num _parseSafeNum(dynamic value) => (value is num) ? value : num.tryParse(value?.toString() ?? '0') ?? 0;

  String _formatWholeNumber(dynamic value) {
    num val = _parseSafeNum(value);
    return val.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  String _formatMoney(dynamic value) {
    num val = _parseSafeNum(value);
    return "\$" + val.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildGeneralInfo(),
          const SizedBox(height: 12),

          // Side-by-Side Stats
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBattleStats()),
              const SizedBox(width: 10),
              Expanded(child: _buildWorkingStats()),
            ],
          ),
          const SizedBox(height: 12),

          _buildProgressionStats(), // NEW: Crime EXP & Progression
          const SizedBox(height: 12),

          _buildEquippedGear(),
          const SizedBox(height: 12),

          _buildPropertyInfo(),
          const SizedBox(height: 12),

          _buildLatestEvents(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // --- UI SECTION BUILDERS ---

  Widget _buildHeader() {
    String username = _safeStr(userData['username'], "Ghost");
    String userId = _safeStr(userData['user_id'], "0000");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: const Color(0xFF39FF14).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Color(0xFF121212),
            child: Icon(Icons.person, size: 40, color: Color(0xFF39FF14)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
                Text("ID: [$userId]", style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralInfo() {
    num dirtyCash = _parseSafeNum(userData['dirty_cash']);
    num cleanCash = _parseSafeNum(userData['clean_cash']);
    int level = _parseSafeNum(userData['level']).toInt();
    String role = _safeStr(userData['role'], "player");

    // V1.2 Dynamic Networth Calculation
    num totalNetworth = dirtyCash + cleanCash;

    return _buildCard("GENERAL INFO", [
      _buildRow("Dirty Cash:", _formatMoney(dirtyCash), valueColor: const Color(0xFF39FF14)),
      _buildRow("Clean Cash:", _formatMoney(cleanCash), valueColor: Colors.white),
      _buildRow("Level:", "$level"),
      _buildRow("Rank:", _safeStr(userData['rank'], "Thug")),
      _buildRow("Role:", role.toUpperCase()),
      _buildRow("Networth:", _formatMoney(totalNetworth), valueColor: Colors.orangeAccent),
    ]);
  }

  Widget _buildBattleStats() {
    return _buildCard("BATTLE STATS", [
      _buildRow("STR:", _formatWholeNumber(userData['stat_str']), valueColor: const Color(0xFF39FF14)),
      _buildRow("DEF:", _formatWholeNumber(userData['stat_def']), valueColor: const Color(0xFF39FF14)),
      _buildRow("DEX:", _formatWholeNumber(userData['stat_dex']), valueColor: const Color(0xFF39FF14)),
      _buildRow("SPD:", _formatWholeNumber(userData['stat_spd']), valueColor: const Color(0xFF39FF14)),
    ]);
  }

  Widget _buildWorkingStats() {
    return _buildCard("WORKING STATS", [
      _buildRow("ACU:", _formatWholeNumber(userData['stat_acu']), valueColor: Colors.orangeAccent),
      _buildRow("OPS:", _formatWholeNumber(userData['stat_ops']), valueColor: Colors.orangeAccent),
      _buildRow("PRE:", _formatWholeNumber(userData['stat_pre']), valueColor: Colors.orangeAccent),
      _buildRow("RES:", _formatWholeNumber(userData['stat_res']), valueColor: Colors.orangeAccent),
    ]);
  }

  // NEW: Wired up the Crime EXP system from the V1.1 GDD
  Widget _buildProgressionStats() {
    num crimeExp = _parseSafeNum(userData['crime_exp']);
    int maxNerve = _parseSafeNum(userData['max_nerve']).toInt();

    return _buildCard("PROGRESSION", [
      _buildRow("Crime EXP:", _formatWholeNumber(crimeExp), valueColor: Colors.purpleAccent),
      _buildRow("Current Max Nerve:", "$maxNerve", valueColor: Colors.white),
      const SizedBox(height: 8),
      const Text("Next Nerve upgrade at 5,000 Crime EXP", style: TextStyle(color: Colors.white24, fontSize: 9, fontStyle: FontStyle.italic)),
    ]);
  }

  Widget _buildEquippedGear() {
    // These will be wired once the user_equipment table is fully synced in the main_hub
    return _buildCard("EQUIPPED GEAR", [
      _buildRow("Primary:", "None", valueColor: Colors.white24),
      _buildRow("Secondary:", "None", valueColor: Colors.white24),
      _buildRow("Melee:", "None", valueColor: Colors.white24),
      _buildRow("Armor:", "None", valueColor: Colors.white24),
    ]);
  }

  Widget _buildPropertyInfo() {
    return _buildCard("PROPERTY INFORMATION", [
      _buildRow("Property:", "Cardboard Box"),
      _buildRow("Gym Bonus:", "+0%", valueColor: Colors.white54),
      _buildRow("Daily Fees:", "\$0 / day", valueColor: Colors.redAccent),
    ]);
  }

  Widget _buildLatestEvents() {
    // This will eventually pull from the user_events table in the backend
    return _buildCard("LATEST EVENTS", [
      _buildEventText("Welcome to Cold Streets. Trust no one, build your empire."),
    ]);
  }

  // --- CORE STYLING WIDGETS ---

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF39FF14), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color valueColor = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: valueColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEventText(String eventStr) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("> ", style: TextStyle(color: Color(0xFF39FF14), fontSize: 11, fontWeight: FontWeight.bold)),
          Expanded(child: Text(eventStr, style: const TextStyle(color: Colors.white54, fontSize: 11))),
        ],
      ),
    );
  }
}