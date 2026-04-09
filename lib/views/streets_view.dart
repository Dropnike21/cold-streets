import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // Required for Timer

class StreetsView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const StreetsView({super.key, required this.userData, required this.onStateChange});

  @override
  State<StreetsView> createState() => _StreetsViewState();
}

class _StreetsViewState extends State<StreetsView> {
  final String apiUrl = "http://10.0.2.2:3000/crimes";
  bool _isLoading = true;
  Map<String, List<dynamic>> _groupedCrimes = {};

  // Dynamic Header State Variables
  String _headerTitle = "THE STREETS";
  String _headerBody = "Welcome to the gritty streets. Execute crimes manually to build your empire, or assign NPC Crew members to automate your hustle.";
  Color _headerColor = const Color(0xFF39FF14);
  Timer? _revertTimer;

  @override
  void initState() {
    super.initState();
    _fetchJobBoard();
  }

  @override
  void dispose() {
    _revertTimer?.cancel(); // Clean up timer if user navigates away
    super.dispose();
  }

  Future<void> _fetchJobBoard() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/list'));
      if (response.statusCode == 200) {
        final List<dynamic> crimesData = jsonDecode(response.body);
        Map<String, List<dynamic>> tempGroup = {};
        for (var crime in crimesData) {
          String category = crime['category'];
          if (!tempGroup.containsKey(category)) tempGroup[category] = [];
          tempGroup[category]!.add(crime);
        }
        if (mounted) setState(() { _groupedCrimes = tempGroup; _isLoading = false; });
      } else {
        debugPrint("🔴 CRITICAL BACKEND ERROR: ${response.statusCode}");
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executeCrime(Map<String, dynamic> crime) async {
    // Basic UI blocks (Backend is the true authority)
    if (widget.userData['hp'] < 25) {
      _showDynamicResult("TOO WEAK", "You need at least 25 HP to hit the streets. Heal up or wait.", Colors.redAccent);
      return;
    }
    if (widget.userData['energy'] < crime['energy_cost']) {
      _showDynamicResult("NO ENERGY", "You don't have enough Energy to do this.", Colors.orangeAccent);
      return;
    }
    if (widget.userData['nerve'] < crime['nerve_cost']) {
      _showDynamicResult("NO NERVE", "You don't have the guts for this job. Wait for Nerve to recharge.", Colors.purpleAccent);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/execute'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userData['user_id'], "crime_id": crime['crime_id']}),
      );

      if (!mounted) return;
      final result = jsonDecode(response.body);

      // State Bridge Update
      if (result['user'] != null) widget.onStateChange(result['user']);

      if (response.statusCode == 200) {
        _processResult(result, crime['title']);
      } else {
        _showDynamicResult("ACTION BLOCKED", result['error'] ?? "Unknown error.", Colors.redAccent);
      }
    } catch (e) {
      if (!mounted) return;
      _showDynamicResult("CONNECTION LOST", "Cannot reach the game servers.", Colors.redAccent);
    }
  }

  // Parses the backend response and fires the dynamic text box
  void _processResult(Map<String, dynamic> result, String crimeTitle) {
    String outTitle = "UNKNOWN";
    String outBody = "\"${result['message']}\"\n\nResults: ";
    Color outColor = Colors.white;

    switch (result['status']) {
      case "success":
        outTitle = "SUCCESS";
        outColor = const Color(0xFF39FF14);
        outBody += "+ \$${result['gained_cash']} Dirty Cash";
        break;
      case "escaped":
        outTitle = "ESCAPED (FAILURE)";
        outColor = Colors.yellowAccent;
        outBody += "- 10 HP";
        break;
      case "hospitalized":
        outTitle = "HOSPITALIZED (FAILURE)";
        outColor = Colors.orangeAccent;
        outBody += "HP dropped to 1. Locked in Hospital.";
        break;
      case "jailed":
        outTitle = "JAILED (FAILURE)";
        outColor = Colors.redAccent;
        outBody += "Locked in Jail.";
        break;
    }

    _showDynamicResult(outTitle, outBody, outColor);
  }

  // Changes the Header UI and starts the 5-second revert timer
  void _showDynamicResult(String title, String body, Color color) {
    _revertTimer?.cancel(); // Cancel existing timer if they spam crimes

    setState(() {
      _headerTitle = title;
      _headerBody = body;
      _headerColor = color;
    });

    _revertTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _headerTitle = "THE STREETS";
          _headerBody = "Welcome to the gritty streets. Execute crimes manually to build your empire, or assign NPC Crew members to automate your hustle.";
          _headerColor = const Color(0xFF39FF14);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)));
    if (_groupedCrimes.isEmpty) return const Center(child: Text("The streets are quiet...", style: TextStyle(color: Colors.white54)));

    return Column(
      children: [
        // --- DYNAMIC RESULTS HEADER ---
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            border: Border.all(color: _headerColor.withValues(alpha: 0.5), width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_headerTitle, style: TextStyle(color: _headerColor, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(_headerBody, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
            ],
          ),
        ),

        // --- THE JOB BOARD ---
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            children: _groupedCrimes.entries.map((entry) {
              return ExpansionTile(
                initiallyExpanded: true,
                iconColor: const Color(0xFF39FF14),
                collapsedIconColor: Colors.white54,
                title: Text(entry.key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
                children: entry.value.map((crime) => _buildCrimeCard(crime)).toList(),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCrimeCard(Map<String, dynamic> crime) {
    String costStr = "${crime['energy_cost']} E";
    if (crime['nerve_cost'] > 0) costStr = "${crime['nerve_cost']} N | $costStr";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          border: Border(left: BorderSide(color: Color(0xFF39FF14), width: 3)),
          borderRadius: BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(crime['title'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
              Text("COST: $costStr", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("PAYOUT: \$${crime['min_payout']} - \$${crime['max_payout']}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("TOOL REQ: ${crime['tool_req']}", style: TextStyle(color: crime['tool_req'] == "NONE" ? Colors.white24 : Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),

              // FIXED: Added the "Assign Crew" + button
              Row(
                children: [
                  SizedBox(
                    height: 28,
                    width: 36, // Square-ish button for the icon
                    child: OutlinedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Syndicate assignment coming soon.")));
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: Color(0xFF333333)),
                      ),
                      child: const Icon(Icons.person_add_alt_1, size: 14, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: () => _executeCrime(crime),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        side: const BorderSide(color: Color(0xFF39FF14)),
                      ),
                      child: const Text("EXECUTE", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }
}