import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class StreetsView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const StreetsView({super.key, required this.userData, required this.onStateChange});

  @override
  State<StreetsView> createState() => _StreetsViewState();
}

class _StreetsViewState extends State<StreetsView> {
  final String crimesApiUrl = "http://10.0.2.2:3000/crimes";
  final String syndicateApiUrl = "http://10.0.2.2:3000/syndicate";

  bool _isLoading = true;
  Map<String, List<dynamic>> _groupedCrimes = {};
  List<dynamic> _activeCrew = [];
  List<String> _ownedTools = []; // NEW: Tracks inventory

  String _headerTitle = "THE STREETS";
  String _headerBody = "Welcome to the gritty streets. Execute crimes manually to build your empire, or assign NPC Crew members to automate your hustle.";
  Color _headerColor = const Color(0xFF39FF14);
  Timer? _revertTimer;

  final int automationDuration = 60;
  Map<String, int> _automatedTimers = {};
  Timer? _hustleTimer;
  int _syncTick = 0;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _startHustleTimer();
  }

  @override
  void dispose() {
    _revertTimer?.cancel();
    _hustleTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchJobBoard(),
      _fetchActiveCrew(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  // --- AUTOMATION ENGINE ---
  void _startHustleTimer() {
    _hustleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      bool needsUpdate = false;

      _syncTick++;
      if (_syncTick >= 5) {
        _fetchActiveCrew();
        _syncTick = 0;
      }

      List<String> finishedJobs = [];

      for (String crimeTitle in _automatedTimers.keys) {
        // CHECK 1: Find the actual crime data to see if it requires a tool
        dynamic targetCrime;
        for (var category in _groupedCrimes.values) {
          try { targetCrime = category.firstWhere((c) => c['title'] == crimeTitle); break; } catch (e) {}
        }

        // CHECK 2: Does the player have the tool?
        bool hasTool = true;
        if (targetCrime != null && targetCrime['tool_req'] != 'NONE') {
          hasTool = _ownedTools.contains(targetCrime['tool_req'].toString().toUpperCase());
        }

        // Only tick down if they actually possess the tool!
        if (hasTool) {
          if (_automatedTimers[crimeTitle]! > 0) {
            _automatedTimers[crimeTitle] = _automatedTimers[crimeTitle]! - 1;
            needsUpdate = true;
          } else {
            finishedJobs.add(crimeTitle);
          }
        } else {
          // If paused, force UI redraw to show the red warning state
          needsUpdate = true;
        }
      }

      for (String crimeTitle in finishedJobs) {
        _automatedTimers[crimeTitle] = automationDuration;
        _completeAutomatedJob(crimeTitle);
        needsUpdate = true;
      }

      if (needsUpdate) setState(() {});
    });
  }

  Future<void> _completeAutomatedJob(String crimeTitle) async {
    dynamic assignedCrew;
    try { assignedCrew = _activeCrew.firstWhere((c) => c['assignment'] == crimeTitle); } catch (e) { return; }

    dynamic targetCrime;
    for (var category in _groupedCrimes.values) {
      try { targetCrime = category.firstWhere((c) => c['title'] == crimeTitle); break; } catch (e) {}
    }
    if (targetCrime == null) return;

    int payout = ((targetCrime['min_payout'] + targetCrime['max_payout']) / 2).floor();

    try {
      final response = await http.post(
        Uri.parse('$syndicateApiUrl/complete_job'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.userData['user_id'],
          "crew_id": assignedCrew['crew_id'],
          "crime_category": targetCrime['category'],
          "payout": payout
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        _showDynamicResult("AUTOMATION COMPLETE", result['message'], Colors.orangeAccent);

        Map<String, dynamic> updatedUser = Map.from(widget.userData);
        updatedUser['dirty_cash'] = (updatedUser['dirty_cash'] ?? 0) + payout;
        widget.onStateChange(updatedUser);
      }
    } catch (e) {
      debugPrint("Automated job failed: $e");
    }
  }

  // --- API FETCHERS ---
  Future<void> _fetchJobBoard() async {
    try {
      final response = await http.get(Uri.parse('$crimesApiUrl/list'));
      if (response.statusCode == 200) {
        final List<dynamic> crimesData = jsonDecode(response.body);
        Map<String, List<dynamic>> tempGroup = {};
        for (var crime in crimesData) {
          String category = crime['category'];
          if (!tempGroup.containsKey(category)) tempGroup[category] = [];
          tempGroup[category]!.add(crime);
        }
        _groupedCrimes = tempGroup;
      }
    } catch (e) {
      debugPrint("Fetch Crimes Error: $e");
    }
  }

  Future<void> _fetchActiveCrew() async {
    try {
      final response = await http.get(Uri.parse('$syndicateApiUrl/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _activeCrew = data['crew'];
            // Store Owned Tools
            _ownedTools = List<String>.from(data['ownedTools'] ?? []).map((t) => t.toUpperCase()).toList();

            Set<String> activeAssignments = {};
            for (var crew in _activeCrew) {
              String assignment = crew['assignment'] ?? "UNASSIGNED";
              if (assignment != "UNASSIGNED") {
                activeAssignments.add(assignment);
                if (!_automatedTimers.containsKey(assignment)) {
                  _automatedTimers[assignment] = automationDuration;
                }
              }
            }
            _automatedTimers.removeWhere((crime, _) => !activeAssignments.contains(crime));
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch Crew Error: $e");
    }
  }

  Future<void> _assignCrewToCrime(String crewId, String crimeTitle) async {
    try {
      final response = await http.post(
          Uri.parse('$syndicateApiUrl/assign_job'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id'], "crew_id": crewId, "crime_title": crimeTitle})
      );
      if (response.statusCode == 200) {
        setState(() { _automatedTimers[crimeTitle] = automationDuration; });
        _fetchActiveCrew();
      }
    } catch (e) {
      debugPrint("Assign Error: $e");
    }
  }

  Future<void> _unassignCrew(String crewId, String crimeTitle) async {
    try {
      final response = await http.post(
          Uri.parse('$syndicateApiUrl/unassign_job'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id'], "crew_id": crewId})
      );
      if (response.statusCode == 200) {
        setState(() { _automatedTimers.remove(crimeTitle); });
        _fetchActiveCrew();
      }
    } catch (e) {
      debugPrint("Unassign Error: $e");
    }
  }

  Future<void> _executeCrime(Map<String, dynamic> crime) async {
    // Basic Manual Checking
    if (crime['tool_req'] != 'NONE' && !_ownedTools.contains(crime['tool_req'].toString().toUpperCase())) {
      _showDynamicResult("MISSING EQUIPMENT", "You need a ${crime['tool_req']} to pull this off.", Colors.redAccent);
      return;
    }
    if (widget.userData['hp'] < 25) {
      _showDynamicResult("TOO WEAK", "You need at least 25 HP.", Colors.redAccent);
      return;
    }
    if (widget.userData['energy'] < crime['energy_cost']) {
      _showDynamicResult("NO ENERGY", "Not enough Energy.", Colors.orangeAccent);
      return;
    }
    if (widget.userData['nerve'] < crime['nerve_cost']) {
      _showDynamicResult("NO NERVE", "Not enough Nerve.", Colors.purpleAccent);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$crimesApiUrl/execute'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userData['user_id'], "crime_id": crime['crime_id']}),
      );

      if (!mounted) return;
      final result = jsonDecode(response.body);
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

  void _processResult(Map<String, dynamic> result, String crimeTitle) {
    String outTitle = "UNKNOWN";
    String outBody = "\"${result['message']}\"\n\nResults: ";
    Color outColor = Colors.white;

    switch (result['status']) {
      case "success": outTitle = "SUCCESS"; outColor = const Color(0xFF39FF14); outBody += "+ \$${result['gained_cash']} Dirty Cash"; break;
      case "escaped": outTitle = "ESCAPED (FAILURE)"; outColor = Colors.yellowAccent; outBody += "- 10 HP"; break;
      case "hospitalized": outTitle = "HOSPITALIZED (FAILURE)"; outColor = Colors.orangeAccent; outBody += "HP dropped to 1. Locked in Hospital."; break;
      case "jailed": outTitle = "JAILED (FAILURE)"; outColor = Colors.redAccent; outBody += "Locked in Jail."; break;
    }
    _showDynamicResult(outTitle, outBody, outColor);
  }

  void _showDynamicResult(String title, String body, Color color) {
    _revertTimer?.cancel();
    setState(() { _headerTitle = title; _headerBody = body; _headerColor = color; });
    _revertTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() {
          _headerTitle = "THE STREETS";
          _headerBody = "Welcome to the gritty streets. Execute crimes manually to build your empire, or assign NPC Crew members to automate your hustle.";
          _headerColor = const Color(0xFF39FF14);
        });
      }
    });
  }

  void _showAssignCrewModal(Map<String, dynamic> crime) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (BuildContext context) {
        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF333333)))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text("ASSIGN CREW: ${crime['title'].toString().toUpperCase()}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context))
                  ],
                ),
              ),
              if (_activeCrew.isEmpty)
                const Expanded(child: Center(child: Text("YOU HAVE NO CREW MEMBERS.", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))))
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _activeCrew.length,
                    itemBuilder: (context, index) {
                      var npc = _activeCrew[index];
                      bool isAssignedHere = npc['assignment'] == crime['title'];
                      bool isAssignedElsewhere = npc['assignment'] != 'UNASSIGNED' && !isAssignedHere;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          border: Border.all(color: isAssignedHere ? Colors.orangeAccent : const Color(0xFF333333)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(npc['npc_name'].toString().toUpperCase(), style: TextStyle(color: isAssignedHere ? Colors.orangeAccent : Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text("TIER: ${npc['tier'].toString().toUpperCase()}", style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                                if (isAssignedElsewhere)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text("CURRENT: ${npc['assignment']}", style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                  )
                              ],
                            ),
                            ElevatedButton(
                              onPressed: () {
                                if (isAssignedHere) { _unassignCrew(npc['crew_id'], crime['title']); }
                                else { _assignCrewToCrime(npc['crew_id'], crime['title']); }
                                if (!context.mounted) return;
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isAssignedHere ? Colors.redAccent.withValues(alpha: 0.1) : const Color(0xFF39FF14).withValues(alpha: 0.1),
                                side: BorderSide(color: isAssignedHere ? Colors.redAccent : const Color(0xFF39FF14)),
                              ),
                              child: Text(isAssignedHere ? "RECALL" : (isAssignedElsewhere ? "SWAP HERE" : "ASSIGN"), style: TextStyle(color: isAssignedHere ? Colors.redAccent : const Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)));
    if (_groupedCrimes.isEmpty) return const Center(child: Text("The streets are quiet...", style: TextStyle(color: Colors.white54)));

    return Column(
      children: [
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

    dynamic activeWorker;
    try { activeWorker = _activeCrew.firstWhere((c) => c['assignment'] == crime['title']); } catch (e) { activeWorker = null; }

    bool isAutomated = activeWorker != null;
    int timeLeft = _automatedTimers[crime['title']] ?? 0;

    // NEW: Tool Check Logic
    String reqTool = crime['tool_req'].toString().toUpperCase();
    bool isToolMissing = reqTool != 'NONE' && !_ownedTools.contains(reqTool);

    // Dynamic Card Styling based on Tool Missing status
    Color cardBorderColor = isAutomated
        ? (isToolMissing ? Colors.redAccent : Colors.orangeAccent)
        : const Color(0xFF39FF14);
    Color cardBgColor = (isAutomated && isToolMissing)
        ? Colors.redAccent.withValues(alpha: 0.1)
        : const Color(0xFF1E1E1E);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cardBgColor,
          border: Border(left: BorderSide(color: cardBorderColor, width: 3)),
          borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4))
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
                  if (isAutomated && !isToolMissing)
                    Text("ACTIVE: ${activeWorker['npc_name']}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold))
                  else if (isAutomated && isToolMissing)
                    Text("PAUSED: MISSING $reqTool", style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold))
                  else
                    Text("TOOL REQ: $reqTool", style: TextStyle(color: reqTool == "NONE" ? Colors.white24 : (isToolMissing ? Colors.redAccent : Colors.orangeAccent), fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),

              Row(
                children: [
                  SizedBox(
                    height: 28, width: 36,
                    child: OutlinedButton(
                      onPressed: () => _showAssignCrewModal(crime),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: isAutomated ? (isToolMissing ? Colors.redAccent : Colors.orangeAccent) : const Color(0xFF333333)),
                      ),
                      child: Icon(Icons.person_add_alt_1, size: 14, color: isAutomated ? (isToolMissing ? Colors.redAccent : Colors.orangeAccent) : Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 8),

                  if (isAutomated)
                    if (isToolMissing)
                    // RED WARNING BUTTON
                      Container(
                        height: 28, padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.2), border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)),
                        alignment: Alignment.center,
                        child: const Text("HALTED", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    else
                    // NORMAL TIMER
                      SizedBox(
                        height: 28, width: 70,
                        child: Container(
                            decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.1), border: Border.all(color: Colors.orangeAccent), borderRadius: BorderRadius.circular(4)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(value: timeLeft / automationDuration, color: Colors.orangeAccent, backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2), strokeWidth: 2)),
                                const SizedBox(width: 6),
                                Text("${timeLeft}s", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            )
                        ),
                      )
                  else
                    SizedBox(
                      height: 28, width: 70,
                      child: ElevatedButton(
                        onPressed: () => _executeCrime(crime),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1),
                          padding: EdgeInsets.zero,
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