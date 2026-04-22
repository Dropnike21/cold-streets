// File Path: lib/views/gym_view.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class GymView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const GymView({super.key, required this.userData, required this.onStateChange});

  @override
  State<GymView> createState() => _GymViewState();
}

class _GymViewState extends State<GymView> {
  final String apiUrl = "http://10.0.2.2:3000/gym";
  bool isLoading = true;
  bool isTraining = false;

  int activeGymId = 1;
  int? viewedGymId;
  int playerGymExp = 0;
  List<Map<String, dynamic>> gymList = [];

  String _headerText = "";
  Timer? _feedbackTimer;

  final List<String> zones = ["The Neighborhood", "Downtown District", "The Underground", "High Society", "Cartel Territory"];

  final TextEditingController _strController = TextEditingController(text: '1');
  final TextEditingController _defController = TextEditingController(text: '1');
  final TextEditingController _dexController = TextEditingController(text: '1');
  final TextEditingController _spdController = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _fetchGymData();
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _strController.dispose();
    _defController.dispose();
    _dexController.dispose();
    _spdController.dispose();
    super.dispose();
  }

  void _showFeedback(String message) {
    _feedbackTimer?.cancel();
    setState(() => _headerText = message);
    _feedbackTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _headerText = "");
    });
  }

  String _formatTrainingTime(int energy) {
    int totalMinutes = energy * 3;
    if (totalMinutes < 60) return "$totalMinutes minutes";
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;
    return minutes > 0 ? "$hours hr $minutes mins" : "$hours hrs";
  }

  Future<void> _fetchGymData() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            playerGymExp = data['gym_exp'] ?? 0;
            activeGymId = data['active_gym_id'] ?? 1;
            gymList = List<Map<String, dynamic>>.from(data['gyms']);
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _purchaseGym(int gymId) async {
    setState(() => isTraining = true);
    try {
      final response = await http.post(Uri.parse('$apiUrl/purchase'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id'], "gym_id": gymId}));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          widget.userData.addAll(data['user']);
          activeGymId = gymId;
        });
        widget.onStateChange(data['user']);
        await _fetchGymData();
        viewedGymId = null;
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error']), backgroundColor: Colors.redAccent));
      }
    } catch (e) {} finally { if (mounted) setState(() => isTraining = false); }
  }

  Future<void> _activateGym(int gymId) async {
    setState(() => isTraining = true);
    try {
      final response = await http.post(Uri.parse('$apiUrl/activate'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id'], "gym_id": gymId}));
      if (response.statusCode == 200) {
        setState(() { activeGymId = gymId; viewedGymId = null; });
      }
    } catch (e) {} finally { if (mounted) setState(() => isTraining = false); }
  }

  // UPDATED: Energy Auto-Clamping Math
  Future<void> _trainStat(String statType, String statName, TextEditingController controller) async {
    int currentEnergy = _parseSafeInt(widget.userData['energy']);
    int requestedEnergy = int.tryParse(controller.text) ?? 1;

    Map<String, dynamic> currentGym = gymList.firstWhere((g) => g['id'] == activeGymId);
    int gymCost = _parseSafeInt(currentGym['energy_cost']);
    if (gymCost <= 0) gymCost = 1; // Failsafe

    // If they ask to spend more than they have, clamp it down to their current energy
    if (requestedEnergy > currentEnergy) {
      requestedEnergy = currentEnergy;
    }

    // Calculate how many times they can actually train based on the gym's cost
    int trainCount = requestedEnergy ~/ gymCost;

    if (trainCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Not enough Energy. Need at least $gymCost⚡.", style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.redAccent
      ));
      return;
    }

    // This is the EXACT amount of energy that will be deducted and used for math
    int finalEnergySpent = trainCount * gymCost;

    setState(() => isTraining = true);
    try {
      final response = await http.post(Uri.parse('$apiUrl/train'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id'], "stat_type": statType, "energy_spent": finalEnergySpent, "gym_id": activeGymId}));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          widget.userData.addAll(data['user']);
          playerGymExp = data['user']['gym_exp'] ?? playerGymExp;
        });
        widget.onStateChange(data['user']);

        String actionText = currentGym['${statType}_action'] ?? "trained hard";
        _showFeedback("You $actionText for ${_formatTrainingTime(finalEnergySpent)} and gained ${data['gained']} $statName.");
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally { if (mounted) setState(() => isTraining = false); }
  }

  double _parseSafeDouble(dynamic value) => (value is num) ? value.toDouble() : double.tryParse(value?.toString() ?? '0.0') ?? 0.0;
  int _parseSafeInt(dynamic value) => (value is int) ? value : int.tryParse(value?.toString() ?? '0') ?? 0;

  String _formatNumber(num amount) {
    if (amount is int) {
      return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    } else {
      return amount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))\.'), (m) => '${m[1]},');
    }
  }

  String _formatWholeNumber(dynamic value) {
    double val = _parseSafeDouble(value);
    return val.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || gymList.isEmpty) return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))));

    int energy = _parseSafeInt(widget.userData['energy']);
    double str = _parseSafeDouble(widget.userData['stat_str']);
    double def = _parseSafeDouble(widget.userData['stat_def']);
    double dex = _parseSafeDouble(widget.userData['stat_dex']);
    double spd = _parseSafeDouble(widget.userData['stat_spd']);

    int gearBonusStr = 5;  int gearBonusDef = 10; int gearBonusDex = 2;  int gearBonusSpd = 0;
    double effStr = str + (str * gearBonusStr / 100);
    double effDef = def + (def * gearBonusDef / 100);
    double effDex = dex + (dex * gearBonusDex / 100);
    double effSpd = spd + (spd * gearBonusSpd / 100);
    double totalEffStats = effStr + effDef + effDex + effSpd;

    Map<String, dynamic> activeGym = gymList.firstWhere((g) => g['id'] == activeGymId, orElse: () => gymList[0]);
    String displayHeader = _headerText.isEmpty ? "CURRENT: ${activeGym['name'].toUpperCase()}" : _headerText;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black, elevation: 0,
        title: const Text("THE GYM", style: TextStyle(color: Color(0xFF39FF14), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
        iconTheme: const IconThemeData(color: Color(0xFF39FF14)),
        actions: [Padding(padding: const EdgeInsets.only(right: 16.0), child: Center(child: Text("⚡ $energy / 100", style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.bold))))],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey(displayHeader), width: double.infinity, constraints: const BoxConstraints(minHeight: 48), padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _headerText.isEmpty ? const Color(0xFF1A1A1A) : const Color(0xFF39FF14).withOpacity(0.05), border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.3)), borderRadius: BorderRadius.circular(4)),
                    child: Text(displayHeader, style: TextStyle(color: _headerText.isEmpty ? const Color(0xFF39FF14) : Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: [
                      _buildStatCard("Increases raw damage and brutality.", "str", str, Icons.fitness_center, _parseSafeDouble(activeGym['mult_str']), _strController, "STR"),
                      _buildStatCard("Mitigates incoming combat damage.", "def", def, Icons.shield, _parseSafeDouble(activeGym['mult_def']), _defController, "DEF")
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(children: [
                      _buildStatCard("Improves accuracy and stealth actions.", "dex", dex, Icons.track_changes, _parseSafeDouble(activeGym['mult_dex']), _dexController, "DEX"),
                      _buildStatCard("Increases evasion and escape chances.", "spd", spd, Icons.directions_run, _parseSafeDouble(activeGym['mult_spd']), _spdController, "SPD")
                    ])),
                  ],
                ),

                const SizedBox(height: 24),
                const Text("MEMBERSHIPS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 12),

                ...zones.map((zoneName) {
                  List<Map<String, dynamic>> zoneGyms = gymList.where((g) => g['zone'] == zoneName).toList();
                  bool isZoneViewed = viewedGymId != null && gymList.firstWhere((g) => g['id'] == viewedGymId)['zone'] == zoneName;

                  if (zoneGyms.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Row(children: [Text(zoneName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)), const SizedBox(width: 12), const Expanded(child: Divider(color: Color(0xFF333333)))]),),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: zoneGyms.map((gym) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2.0), child: _buildGymGridBox(gym)))).toList()),
                      if (isZoneViewed) Padding(padding: const EdgeInsets.only(top: 12.0, bottom: 8.0), child: _buildGymDetailsCard()),
                      const SizedBox(height: 8),
                    ],
                  );
                }),

                const SizedBox(height: 32),
                const Text("EFFECTIVE BATTLE STATS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(6)),
                  child: Column(
                    children: [
                      _buildEffectiveStatRow("STR", str, gearBonusStr, effStr), const Divider(color: Color(0xFF333333), height: 16),
                      _buildEffectiveStatRow("DEF", def, gearBonusDef, effDef), const Divider(color: Color(0xFF333333), height: 16),
                      _buildEffectiveStatRow("DEX", dex, gearBonusDex, effDex), const Divider(color: Color(0xFF333333), height: 16),
                      _buildEffectiveStatRow("SPD", spd, gearBonusSpd, effSpd), const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), decoration: BoxDecoration(color: const Color(0xFF39FF14).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL POWER:", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)), Text(_formatNumber(totalEffStats), style: const TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1))]),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
          if (isTraining) Container(color: Colors.black.withOpacity(0.5), child: const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))))
        ],
      ),
    );
  }

  Widget _buildStatCard(String desc, String statCode, dynamic currentStat, IconData icon, double activeMultiplier, TextEditingController controller, String nameLabel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [Icon(icon, color: Colors.white54, size: 12), const SizedBox(width: 4), Text(nameLabel, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold))]),
            Text(_formatWholeNumber(currentStat), style: const TextStyle(color: Color(0xFF39FF14), fontSize: 11, fontWeight: FontWeight.w900))
          ]),
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(color: Colors.white24, fontSize: 8, fontStyle: FontStyle.italic), maxLines: 2),
          const SizedBox(height: 8),
          _buildMultiplierBars(activeMultiplier),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(flex: 2, child: Container(
                height: 28,
                alignment: Alignment.center, // FIX: Forces the TextField to center perfectly
                decoration: BoxDecoration(color: const Color(0xFF121212), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
                child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero // FIX: Strips Flutter's default weird padding
                    )
                )
            )),
            const SizedBox(width: 6),
            Expanded(flex: 3, child: SizedBox(height: 28, child: ElevatedButton(
                onPressed: isTraining ? null : () => _trainStat(statCode, nameLabel.substring(0,3), controller),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14).withOpacity(0.1), side: const BorderSide(color: Color(0xFF39FF14), width: 0.5), padding: EdgeInsets.zero),
                child: const Text("TRAIN", style: TextStyle(color: Color(0xFF39FF14), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)))))
          ])
        ],
      ),
    );
  }

  // ... (Keep _buildGymGridBox, _buildGymDetailsCard, _buildEffectiveStatRow, _buildStatBarRow, _buildMultiplierBars the same) ...
  Widget _buildGymGridBox(Map<String, dynamic> gym) {
    bool isUndiscovered = playerGymExp < (gym['unlock_exp_req'] ?? 0);
    bool isActive = gym['id'] == activeGymId;
    bool isOwned = gym['is_owned'] ?? false;

    Color borderColor = isActive ? const Color(0xFF39FF14) : (viewedGymId == gym['id'] ? Colors.white : const Color(0xFF333333));
    Color bgColor = isActive ? const Color(0xFF39FF14).withOpacity(0.1) : (isOwned ? const Color(0xFF1A1A1A) : const Color(0xFF121212));

    return GestureDetector(
      onTap: () {
        if (isUndiscovered) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Requires ${_formatNumber(gym['unlock_exp_req'])} Gym EXP."), duration: const Duration(seconds: 1)));
          return;
        }
        setState(() => viewedGymId = (viewedGymId == gym['id']) ? null : gym['id']);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), height: 32,
        decoration: BoxDecoration(color: bgColor, border: Border.all(color: borderColor, width: isActive ? 1.5 : 1), borderRadius: BorderRadius.circular(4)),
        child: Center(child: isUndiscovered
            ? const Icon(Icons.lock, color: Colors.white10, size: 10)
            : Text(gym['id'].toString(), style: TextStyle(color: isOwned ? Colors.white : Colors.white24, fontWeight: FontWeight.bold, fontSize: 9))),
      ),
    );
  }

  Widget _buildGymDetailsCard() {
    Map<String, dynamic> gym = gymList.firstWhere((g) => g['id'] == viewedGymId);
    bool isOwned = gym['is_owned'] ?? false;
    bool isActive = gym['id'] == activeGymId;

    return Container(
      width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: isOwned ? const Color(0xFF39FF14).withOpacity(0.4) : const Color(0xFF333333)), borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(gym['name'].toString().toUpperCase(), style: TextStyle(color: isOwned ? Colors.white : Colors.white54, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1))),
              if (isActive) const Text("ACTIVE", style: TextStyle(color: Color(0xFF39FF14), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1))
            ],
          ),
          const SizedBox(height: 6),
          if (!isOwned) ...[
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Icon(Icons.lock_outline, color: Colors.white10, size: 32))),
            const Center(child: Text("MEMBERSHIP REQUIRED", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
            const SizedBox(height: 16),
          ] else ...[
            Text(gym['desc'] ?? "", style: const TextStyle(color: Colors.white70, fontSize: 9, fontStyle: FontStyle.italic)),
            const SizedBox(height: 12),
            _buildStatBarRow("STR", _parseSafeDouble(gym['mult_str'])), const SizedBox(height: 4),
            _buildStatBarRow("DEF", _parseSafeDouble(gym['mult_def'])), const SizedBox(height: 4),
            _buildStatBarRow("DEX", _parseSafeDouble(gym['mult_dex'])), const SizedBox(height: 4),
            _buildStatBarRow("SPD", _parseSafeDouble(gym['mult_spd'])), const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("DAILY FEE:", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)), Text("\$${_formatNumber(gym['daily_fee'])}", style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold))]),
          ],
          const SizedBox(height: 12),
          if (!isActive && !isOwned)
            SizedBox(width: double.infinity, height: 32,
                child: ElevatedButton(onPressed: () => _purchaseGym(gym['id']),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14).withOpacity(0.1), side: const BorderSide(color: Color(0xFF39FF14))),
                    child: Text("BUY MEMBERSHIP (\$${_formatNumber(gym['unlock_cost'])})", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 9, fontWeight: FontWeight.bold))))
          else if (!isActive && isOwned)
            SizedBox(width: double.infinity, height: 32,
                child: ElevatedButton(onPressed: () => _activateGym(gym['id']),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, side: const BorderSide(color: Colors.white24)),
                    child: const Text("ACTIVATE", style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }

  Widget _buildEffectiveStatRow(String label, double base, int bonusPct, double effective) {
    return Row(
      children: [
        SizedBox(width: 35, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
        Text(_formatNumber(base), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6), Text("(+$bonusPct%)", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        const Expanded(child: SizedBox()), const Icon(Icons.arrow_right_alt, color: Colors.white24, size: 16), const SizedBox(width: 8),
        Text(_formatNumber(effective), style: const TextStyle(color: Color(0xFF39FF14), fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatBarRow(String statName, double multiplier) {
    return Row(children: [SizedBox(width: 25, child: Text(statName, style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold))), Expanded(child: _buildMultiplierBars(multiplier))]);
  }

  Widget _buildMultiplierBars(double multiplier) {
    return Row(
      children: List.generate(10, (index) {
        double fillRatio = (multiplier - index).clamp(0.0, 1.0);
        return Expanded(child: Container(margin: const EdgeInsets.only(right: 2), height: 3, decoration: BoxDecoration(color: const Color(0xFF121212), borderRadius: BorderRadius.circular(1)),
            child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: fillRatio, child: Container(decoration: BoxDecoration(color: const Color(0xFF39FF14).withOpacity(0.7), borderRadius: BorderRadius.circular(1))))));
      }),
    );
  }
}