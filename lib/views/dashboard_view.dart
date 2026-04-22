import 'package:flutter/material.dart';

class DashboardView extends StatelessWidget {
  final Map<String, dynamic> userData;

  const DashboardView({super.key, required this.userData});

  // Helper for safe strings
  String _safeStr(dynamic value, String fallback) => value?.toString() ?? fallback;

  // NEW: Bulletproof Integer Parser to prevent the Red Screen
  int _parseSafeInt(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
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

          // Row for side-by-side stats
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBattleStats()),
              const SizedBox(width: 10),
              Expanded(child: _buildWorkingStats()),
            ],
          ),
          const SizedBox(height: 12),

          _buildEquippedGear(),
          const SizedBox(height: 12),

          _buildPropertyInfo(),
          const SizedBox(height: 12),

          _buildJobInfo(),
          const SizedBox(height: 12),

          _buildCriminalRecords(),
          const SizedBox(height: 12),

          _buildSkillLevels(),
          const SizedBox(height: 12),

          _buildLatestEvents(),
          const SizedBox(height: 12),

          _buildSyndicateInfo(),
          const SizedBox(height: 12),

          _buildPersonalPerks(),
          const SizedBox(height: 30), // Bottom padding
        ],
      ),
    );
  }

  // --- UI SECTION BUILDERS ---

  Widget _buildHeader() {
    String username = _safeStr(userData['username'], "Unknown");
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
    // FIXED: Now we safely parse these values so they never crash!
    int dirtyCash = _parseSafeInt(userData['dirty_cash'], 0);
    int level = _parseSafeInt(userData['level'], 1);

    return _buildCard("GENERAL INFO", [
      _buildRow("Money on Hand:", "\$${dirtyCash.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}"),
      _buildRow("Level:", "$level"),
      _buildRow("Rank:", "Street Rat"),
      _buildRow("Age:", "Day 1"),
      _buildRow("Marital Status:", "Single"),
      _buildRow("Networth:", "\$0"),
    ]);
  }

  Widget _buildBattleStats() {
    return _buildCard("BATTLE STATS", [
      _buildRow("STR:", _safeStr(userData['stat_str'], "10"), valueColor: const Color(0xFF39FF14)),
      _buildRow("DEF:", _safeStr(userData['stat_def'], "10"), valueColor: const Color(0xFF39FF14)),
      _buildRow("DEX:", _safeStr(userData['stat_dex'], "10"), valueColor: const Color(0xFF39FF14)),
      _buildRow("SPD:", _safeStr(userData['stat_spd'], "10"), valueColor: const Color(0xFF39FF14)),
    ]);
  }

  Widget _buildWorkingStats() {
    return _buildCard("WORKING STATS", [
      _buildRow("INT:", _safeStr(userData['stat_int'], "10"), valueColor: Colors.orangeAccent),
      _buildRow("LAB:", "10", valueColor: Colors.orangeAccent), // TODO: V2 DB Column
      _buildRow("LOG:", "10", valueColor: Colors.orangeAccent), // TODO: V2 DB Column
    ]);
  }

  Widget _buildEquippedGear() {
    return _buildCard("EQUIPPED GEAR", [
      _buildRow("Primary:", "None", valueColor: Colors.white54),
      _buildRow("Secondary:", "9mm Pistol"),
      _buildRow("Melee:", "Switchblade"),
      _buildRow("Armor:", "Thick Hoodie"),
    ]);
  }

  Widget _buildPropertyInfo() {
    return _buildCard("PROPERTY INFORMATION", [
      _buildRow("Property:", "Dirty Motel Room"),
      _buildRow("Asset Value:", "\$500"),
      _buildRow("Daily Fees:", "\$15 / day", valueColor: Colors.redAccent),
    ]);
  }

  Widget _buildJobInfo() {
    return _buildCard("JOB INFORMATION", [
      _buildRow("Position:", "Runner"),
      _buildRow("Company:", "Los Pollos Hermanos (Meth Lab)"),
      _buildRow("Income:", "\$2,500 / day", valueColor: const Color(0xFF39FF14)),
    ]);
  }

  Widget _buildCriminalRecords() {
    return _buildCard("CRIMINAL RECORDS", [
      _buildRow("Total Crimes:", "142"),
      _buildRow("Successes:", "120"),
      _buildRow("Fails:", "22", valueColor: Colors.orangeAccent),
      _buildRow("Jailed:", "4", valueColor: Colors.redAccent),
    ]);
  }

  Widget _buildSkillLevels() {
    return _buildCard("SKILL LEVELS", [
      _buildRow("Searching:", "Level 15"),
      _buildRow("Pickpocketing:", "Level 4"),
      _buildRow("Shoplifting:", "Level 1"),
      _buildRow("Mugging:", "Level 8"),
    ]);
  }

  Widget _buildLatestEvents() {
    return _buildCard("LATEST EVENTS", [
      _buildEventText("You were hospitalized by an Undercover Detective."),
      _buildEventText("Sly Bones successfully hacked the ATM for \$4,500."),
      _buildEventText("You bought a Switchblade from the Black Market."),
      _buildEventText("You leveled up to Level 5!"),
      _buildEventText("Welcome to Cold Streets."),
    ]);
  }

  Widget _buildSyndicateInfo() {
    return _buildCard("SYNDICATE INFORMATION", [
      _buildRow("Status:", "None for now", valueColor: Colors.white24),
    ]);
  }

  Widget _buildPersonalPerks() {
    return _buildCard("PERSONAL PERKS (V2)", [
      _buildRow("Active Perks:", "0", valueColor: Colors.white24),
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