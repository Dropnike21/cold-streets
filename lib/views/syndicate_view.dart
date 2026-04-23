// File Path: lib/views/syndicate_view.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class SyndicateView extends StatefulWidget {
  final String userId;
  const SyndicateView({super.key, required this.userId});
  @override
  State<SyndicateView> createState() => _SyndicateViewState();
}

class _SyndicateViewState extends State<SyndicateView> {
  // NOTE: 10.0.2.2 is for Android Emulator. Use local IPv4 if testing on a physical device.
  final String apiUrl = "http://10.0.2.2:3000/syndicate";

  List<dynamic> _activeCrew = [];
  List<dynamic> _recruitmentBoard = [];
  List<String> _ownedTools = [];

  int dailyRefreshes = 0;
  bool isLoading = true;
  bool _isFetching = false; // GUARD: Prevents overlapping 5-second polling requests
  int recruitCooldownSeconds = 0;
  Timer? _recruitTimer;
  Timer? _backgroundSyncTimer;

  @override
  void initState() {
    super.initState();
    _fetchActiveCrew();
    _backgroundSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _fetchActiveCrew(isBackground: true);
    });
  }

  @override
  void dispose() {
    _recruitTimer?.cancel();
    _backgroundSyncTimer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  // V1.2 FIX: Helper to abbreviate God-Tier stats (e.g. 1000000 -> 1.0M) preventing UI overflows
  String _formatStat(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }

  // V1.2 FIX: Centralized timer logic to sync between Hire and Generate
  void _startCooldownTimer(StateSetter setModalState) {
    _recruitTimer?.cancel();
    _recruitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (recruitCooldownSeconds > 0) {
        if (mounted) {
          setModalState(() => recruitCooldownSeconds--);
          setState(() {}); // Update the background UI
        }
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _fetchActiveCrew({bool isBackground = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    if (!isBackground && mounted) setState(() => isLoading = true);

    try {
      final response = await http
          .get(Uri.parse('$apiUrl/${widget.userId}'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _activeCrew = data['crew'] ?? [];
            dailyRefreshes = data['refreshesLeft'] ?? 0;
            _ownedTools = List<String>.from(data['ownedTools'] ?? [])
                .map((t) => t.toUpperCase())
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch Crew Error: $e");
    } finally {
      _isFetching = false;
      if (!isBackground && mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _generateRecruitBoard(StateSetter setModalState) async {
    if (dailyRefreshes <= 0) return;
    setModalState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/generate_board'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userId}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setModalState(() {
          _recruitmentBoard = data['board'];
          dailyRefreshes = data['refreshesLeft'];
          isLoading = false;
        });
        setState(() {});
      }
      // V1.2 FIX: Explicitly handle the 403 Cooldown lock from the backend
      else if (response.statusCode == 403) {
        final data = jsonDecode(response.body);
        if (data['seconds_left'] != null) {
          setModalState(() {
            recruitCooldownSeconds = data['seconds_left'].toInt();
            _recruitmentBoard.clear();
            isLoading = false;
          });
          _startCooldownTimer(setModalState);
        } else {
          setModalState(() => isLoading = false);
        }
      } else {
        setModalState(() => isLoading = false);
      }
    } catch (e) {
      setModalState(() => isLoading = false);
    }
  }

  Future<void> _hireRecruit(Map<String, dynamic> recruit, StateSetter setModalState) async {
    if (recruitCooldownSeconds > 0) return;
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/hire'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userId, "recruit": recruit}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        setModalState(() {
          _recruitmentBoard.remove(recruit);
          recruitCooldownSeconds = 120; // Explicit 2-minute default per backend
        });
        _fetchActiveCrew();
        _startCooldownTimer(setModalState);
      }
    } catch (e) {
      debugPrint("Hire Error: $e");
    }
  }

  Future<void> _unassignCrew(String crewId) async {
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/unassign_job'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userId, "crew_id": crewId}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        _fetchActiveCrew();
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF333333)))),
            child: const TabBar(
              indicatorColor: Color(0xFF39FF14), labelColor: Color(0xFF39FF14), unselectedLabelColor: Colors.white54,
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              tabs: [ Tab(text: "MY CREW"), Tab(text: "SYNDICATE") ],
            ),
          ),
          Expanded(child: TabBarView(children: [ _buildMyGangTab(), _buildSyndicateTab() ])),
        ],
      ),
    );
  }

  Widget _buildMyGangTab() {
    if (isLoading && _activeCrew.isEmpty) return const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("ACTIVE CREW (${_activeCrew.length})", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
              SizedBox(
                height: 28,
                child: ElevatedButton.icon(
                  onPressed: () => _showRecruitmentBoard(context),
                  icon: const Icon(Icons.person_add, size: 14, color: Color(0xFF39FF14)),
                  label: const Text("RECRUIT", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1), side: const BorderSide(color: Color(0xFF39FF14)), padding: const EdgeInsets.symmetric(horizontal: 12)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 0),
            itemCount: _activeCrew.length,
            itemBuilder: (context, index) => _buildActiveCrewCard(_activeCrew[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildSyndicateTab() {
    final myGangCount = _activeCrew.length;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("SYNDICATE ESTABLISHMENT", style: TextStyle(color: Color(0xFF39FF14), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 10),
              _buildReqRow("GANG MEMBERS", "$myGangCount / 150", myGangCount / 150.0),
              _buildReqRow("CAPITAL", "\$4,250 / \$500,000,000", 4250 / 500000000.0),
              _buildReqRow("COMPLETE BUSINESSES", "0 / 2", 0.0, subtext: "Requires fully linked Production, Manufacturing & Distribution lines."),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 36,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14).withValues(alpha:0.1), disabledBackgroundColor: const Color(0xFF121212), side: const BorderSide(color: Color(0xFF333333))),
                  child: const Text("INSUFFICIENT RESOURCES", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReqRow(String label, String value, double progress, {String? subtext}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          if (subtext != null) ...[ const SizedBox(height: 2), Text(subtext, style: const TextStyle(color: Colors.white24, fontSize: 9, fontStyle: FontStyle.italic)) ],
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(value: progress, backgroundColor: const Color(0xFF121212), color: const Color(0xFF39FF14).withValues(alpha:0.5), minHeight: 3),
          ),
        ],
      ),
    );
  }

  void _showAssignModal(BuildContext context, Map<String, dynamic> npc) {
    bool isFetching = true;
    List<dynamic> localCrimes = [];
    String? expandedCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setModalState) {
          if (isFetching && localCrimes.isEmpty) {
            http.get(Uri.parse('$apiUrl/crimes_board/${widget.userId}')).then((response) {
              if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                setModalState(() {
                  localCrimes = data['crimes'] ?? [];
                  localCrimes.sort((a, b) {
                    int reqA = int.tryParse(a['req_stat_value']?.toString() ?? '0') ?? 0;
                    int reqB = int.tryParse(b['req_stat_value']?.toString() ?? '0') ?? 0;
                    return reqA.compareTo(reqB);
                  });
                  isFetching = false;
                });
              }
            }).catchError((_) {
              setModalState(() => isFetching = false);
            });
          }

          Map<String, List<dynamic>> groupedCrimes = {};
          for (var crime in localCrimes) {
            String cat = crime['category']?.toString() ?? "General";
            groupedCrimes.putIfAbsent(cat, () => []).add(crime);
          }

          return FractionallySizedBox(
            heightFactor: 0.85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF333333)))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("ASSIGN ${npc["npc_name"].toString().toUpperCase()}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context))
                    ],
                  ),
                ),
                if (isFetching) const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))))
                else Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: groupedCrimes.keys.length,
                    itemBuilder: (context, index) {
                      String category = groupedCrimes.keys.elementAt(index);
                      List<dynamic> categoryCrimes = groupedCrimes[category]!;
                      bool isExpanded = expandedCategory == category;

                      return Column(
                        children: [
                          GestureDetector(
                            onTap: () => setModalState(() => expandedCategory = isExpanded ? null : category),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(color: isExpanded ? const Color(0xFF39FF14).withValues(alpha: 0.1) : const Color(0xFF121212), border: Border.all(color: isExpanded ? const Color(0xFF39FF14) : const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(category.toUpperCase(), style: TextStyle(color: isExpanded ? const Color(0xFF39FF14) : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: isExpanded ? const Color(0xFF39FF14) : Colors.white54),
                                ],
                              ),
                            ),
                          ),
                          if (isExpanded)
                            ...categoryCrimes.map((crime) {
                              dynamic assignedCrew;
                              try { assignedCrew = _activeCrew.firstWhere((c) => c['assignment'] == crime['title']); } catch (e) { assignedCrew = null; }

                              return Container(
                                margin: const EdgeInsets.only(left: 16, bottom: 8, right: 8), padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border(left: BorderSide(color: assignedCrew != null ? Colors.orangeAccent : const Color(0xFF333333), width: 4))),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(crime['title'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text("REQ: ${_formatStat(int.tryParse(crime['req_stat_value'].toString()) ?? 0)} ${crime['req_stat_type'].toString().replaceAll('stat_', '').toUpperCase()}", style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                                          Text("PAYOUT: \$${_formatStat(int.tryParse(crime['min_payout'].toString()) ?? 0)} - \$${_formatStat(int.tryParse(crime['max_payout'].toString()) ?? 0)}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 9, fontWeight: FontWeight.bold)),
                                          if (assignedCrew != null) ...[ const SizedBox(height: 4), Text("ACTIVE: ${assignedCrew['npc_name']}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)) ]
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () async {
                                        await http.post(
                                            Uri.parse('$apiUrl/assign_job'),
                                            headers: {"Content-Type": "application/json"},
                                            body: jsonEncode({"user_id": widget.userId, "crew_id": npc['crew_id'], "crime_title": crime['title']})
                                        );
                                        _fetchActiveCrew();
                                        if (!context.mounted) return;
                                        Navigator.pop(context);
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, side: const BorderSide(color: Colors.white54)),
                                      child: Text(assignedCrew != null ? "SWAP" : "ASSIGN", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                  ],
                                ),
                              );
                            }),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  void _showRecruitmentBoard(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: const Color(0xFF121212), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (BuildContext context) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              bool canRefresh = dailyRefreshes > 0 && !isLoading && recruitCooldownSeconds == 0;
              return FractionallySizedBox(
                heightFactor: 0.85,
                child: Column(
                  children: [
                    Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(2))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("THE STREETS", style: TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          Row(
                            children: [
                              Text("REFRESHES: $dailyRefreshes/5", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                              IconButton(icon: Icon(Icons.refresh, color: canRefresh ? const Color(0xFF39FF14) : Colors.grey, size: 18), onPressed: canRefresh ? () => _generateRecruitBoard(setModalState) : null)
                            ],
                          )
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF333333)),
                    if (recruitCooldownSeconds > 0)
                      Container(
                        margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), border: Border.all(color: Colors.red)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(value: recruitCooldownSeconds / 120, color: Colors.red, backgroundColor: Colors.red.withValues(alpha: 0.2), strokeWidth: 2)),
                            const SizedBox(width: 10),
                            Text("WORD IS OUT. LAY LOW FOR ${_formatTime(recruitCooldownSeconds)}.", style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (isLoading) const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))))
                    else if (_recruitmentBoard.isEmpty) Expanded(child: Center(child: Text(dailyRefreshes > 0 ? "TAP REFRESH TO SCOUT THE STREETS" : "NO MORE RECRUITS. NEXT DROP 6:00 AM PHT.", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))))
                    else Expanded(child: ListView.builder(padding: const EdgeInsets.all(10.0), itemCount: _recruitmentBoard.length, itemBuilder: (context, index) { return _buildRecruitCard(_recruitmentBoard[index], setModalState); })),
                  ],
                ),
              );
            }
        );
      },
    );
  }

  Widget _buildActiveCrewCard(Map<String, dynamic> npc) {
    // V1.2 FIX: Adjusted barMax dynamically to match the backend's new million-stat scaling
    int barMax = 1000;
    if (npc["tier"] == "Hustler") barMax = 10000;
    if (npc["tier"] == "Enforcer") barMax = 80000;
    if (npc["tier"] == "Specialist") barMax = 350000;
    if (npc["tier"] == "Lieutenant") barMax = 1000000;

    bool isAssigned = npc["assignment"] != 'UNASSIGNED';

    String? reqTool = npc['tool_req']?.toString().toUpperCase();
    bool isToolMissing = isAssigned && reqTool != null && reqTool != 'NONE' && !_ownedTools.contains(reqTool);

    Color cardBorderColor = isAssigned
        ? (isToolMissing ? Colors.redAccent : Colors.orangeAccent.withValues(alpha: 0.3))
        : const Color(0xFF39FF14).withValues(alpha: 0.3);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: cardBorderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(npc["npc_name"].toString().toUpperCase(), style: const TextStyle(color: Color(0xFF39FF14), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    Text("TIER: ${npc["tier"].toString().toUpperCase()}", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),

                    if (isToolMissing)
                      Text("HALTED: MISSING $reqTool", style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold))
                    else
                      Text("JOB: ${npc["assignment"] ?? "UNASSIGNED"}", style: TextStyle(color: isAssigned ? Colors.orangeAccent : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Row(
                children: [
                  if (isAssigned)
                    SizedBox(
                      height: 24,
                      child: ElevatedButton(
                        onPressed: () => _unassignCrew(npc['crew_id'].toString()),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), padding: const EdgeInsets.symmetric(horizontal: 12), side: const BorderSide(color: Colors.redAccent)),
                        child: const Text("RECALL", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (isAssigned) const SizedBox(width: 8),
                  SizedBox(
                    height: 24,
                    child: ElevatedButton(
                      onPressed: () => _showAssignModal(context, npc),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 12), side: const BorderSide(color: Colors.white54)),
                      child: Text(isAssigned ? "SWAP" : "ASSIGN", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF333333), height: 1),
          const SizedBox(height: 12),

          // V1.2 FIX: Fully Implemented all 8 stats
          _buildStatBar("STR", npc["cur_str"] ?? 0, npc["max_str"] ?? 0, barMax),
          _buildStatBar("DEF", npc["cur_def"] ?? 0, npc["max_def"] ?? 0, barMax),
          _buildStatBar("DEX", npc["cur_dex"] ?? 0, npc["max_dex"] ?? 0, barMax),
          _buildStatBar("SPD", npc["cur_spd"] ?? 0, npc["max_spd"] ?? 0, barMax),
          _buildStatBar("ACU", npc["cur_acu"] ?? 0, npc["max_acu"] ?? 0, barMax),
          _buildStatBar("OPS", npc["cur_ops"] ?? 0, npc["max_ops"] ?? 0, barMax),
          _buildStatBar("PRE", npc["cur_pre"] ?? 0, npc["max_pre"] ?? 0, barMax),
          _buildStatBar("RES", npc["cur_res"] ?? 0, npc["max_res"] ?? 0, barMax),
        ],
      ),
    );
  }

  Widget _buildRecruitCard(Map<String, dynamic> recruit, StateSetter setModalState) {
    Map<String, dynamic> stats = recruit["stats"];
    int barMax = recruit["barMax"];
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recruit["name"].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    Text("TIER: ${recruit["tier"].toString().toUpperCase()}", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("COST: \$${_formatStat(recruit["price"])}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 24,
                    child: ElevatedButton(
                      onPressed: recruitCooldownSeconds > 0 ? null : () => _hireRecruit(recruit, setModalState),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1), padding: const EdgeInsets.symmetric(horizontal: 12), side: BorderSide(color: recruitCooldownSeconds > 0 ? Colors.grey : const Color(0xFF39FF14))),
                      child: const Text("HIRE", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF333333), height: 1),
          const SizedBox(height: 12),

          // V1.2 FIX: Fully Implemented all 8 stats here as well
          _buildStatBar("STR", stats["str"]["cur"] ?? 0, stats["str"]["max"] ?? 0, barMax),
          _buildStatBar("DEF", stats["def"]["cur"] ?? 0, stats["def"]["max"] ?? 0, barMax),
          _buildStatBar("DEX", stats["dex"]["cur"] ?? 0, stats["dex"]["max"] ?? 0, barMax),
          _buildStatBar("SPD", stats["spd"]["cur"] ?? 0, stats["spd"]["max"] ?? 0, barMax),
          _buildStatBar("ACU", stats["acu"]["cur"] ?? 0, stats["acu"]["max"] ?? 0, barMax),
          _buildStatBar("OPS", stats["ops"]["cur"] ?? 0, stats["ops"]["max"] ?? 0, barMax),
          _buildStatBar("PRE", stats["pre"]["cur"] ?? 0, stats["pre"]["max"] ?? 0, barMax),
          _buildStatBar("RES", stats["res"]["cur"] ?? 0, stats["res"]["max"] ?? 0, barMax),
        ],
      ),
    );
  }

  Widget _buildStatBar(String label, int current, int max, int tierAbsoluteMax) {
    double currentPct = tierAbsoluteMax > 0 ? current / tierAbsoluteMax : 0.0;
    double maxPct = tierAbsoluteMax > 0 ? max / tierAbsoluteMax : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 4, decoration: BoxDecoration(color: const Color(0xFF121212), borderRadius: BorderRadius.circular(2)),
              child: Stack(
                children: [
                  FractionallySizedBox(widthFactor: maxPct.clamp(0.0, 1.0), child: Container(decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(2)))),
                  FractionallySizedBox(widthFactor: currentPct.clamp(0.0, 1.0), child: Container(decoration: BoxDecoration(color: const Color(0xFF39FF14), borderRadius: BorderRadius.circular(2)))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // V1.2 FIX: Increased width from 45 to 65, and used _formatStat to cleanly fit massive numbers like "100.5K / 1.0M"
          SizedBox(width: 65, child: Text("${_formatStat(current)} / ${_formatStat(max)}", textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF39FF14), fontSize: 9, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}