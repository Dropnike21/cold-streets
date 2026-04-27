import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';

class JobsView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const JobsView({super.key, required this.userData, required this.onStateChange});

  @override
  State<JobsView> createState() => _JobsViewState();
}

class _JobsViewState extends State<JobsView> {
  final String apiUrl = "http://10.0.2.2:3000/jobs";

  bool _isLoading = true;
  bool _isProcessing = false;

  int? _currentJobId;
  String? _lastClaimed;
  List<Map<String, dynamic>> _jobs = [];

  bool _isInterviewing = false;
  int _applyingForJobId = 0;
  List<dynamic> _interviewQuestions = [];
  Map<int, int> _selectedAnswers = {};

  bool _skimActive = false;
  Timer? _skimTimer;

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  // --- STATIC RANK DATA (Torn-Style with Specials) ---
  final Map<int, List<Map<String, dynamic>>> _rankData = {
    1: [ // City Hospital
      {
        "rank": 1, "title": "Hospital Janitor", "pay": 45, "daily_inc": 1, "cost": 0,
        "req": {"acu": 0, "ops": 0, "pre": 0, "res": 0},
        "gain": {"acu": 3, "ops": 2, "pre": 1, "res": 2},
        "special": {"name": "Scavenge", "effect": "Gain 1x Bandage", "cost": 10, "is_passive": false}
      },
      {
        "rank": 2, "title": "Orderly", "pay": 120, "daily_inc": 2, "cost": 15,
        "req": {"acu": 60, "ops": 40, "pre": 20, "res": 40},
        "gain": {"acu": 8, "ops": 4, "pre": 2, "res": 5},
        "special": {"name": "First Aid", "effect": "Heals 15 HP", "cost": 5, "is_passive": false}
      },
      {
        "rank": 3, "title": "Paramedic", "pay": 350, "daily_inc": 3, "cost": 40,
        "req": {"acu": 250, "ops": 150, "pre": 100, "res": 200},
        "gain": {"acu": 15, "ops": 10, "pre": 5, "res": 12},
        "special": {"name": "Medical Training", "effect": "+10% Medical Item Effectiveness", "cost": 0, "is_passive": true}
      },
      {
        "rank": 4, "title": "Resident", "pay": 1200, "daily_inc": 4, "cost": 100,
        "req": {"acu": 1000, "ops": 800, "pre": 500, "res": 800},
        "gain": {"acu": 30, "ops": 20, "pre": 10, "res": 25},
        "special": {"name": "Pharmacy Access", "effect": "Gain 1x Morphine", "cost": 25, "is_passive": false}
      },
      {
        "rank": 5, "title": "Chief of Surgery", "pay": 4500, "daily_inc": 5, "cost": 250,
        "req": {"acu": 3500, "ops": 2000, "pre": 1500, "res": 2500},
        "gain": {"acu": 50, "ops": 35, "pre": 20, "res": 45},
        "special": {"name": "Revive", "effect": "Revive someone from the hospital", "cost": 50, "is_passive": false}
      },
    ],
  };

  @override
  void initState() {
    super.initState();
    _fetchJobsDashboard();
    _startSkimTimer();
  }

  @override
  void dispose() {
    _skimTimer?.cancel();
    super.dispose();
  }

  void _startSkimTimer() {
    final randomSeconds = Random().nextInt(1020) + 180;
    _skimTimer = Timer(Duration(seconds: randomSeconds), () {
      if (mounted) setState(() => _skimActive = true);
    });
  }

  int _parseSafeInt(dynamic value) => (value is int) ? value : int.tryParse(value?.toString() ?? '0') ?? 0;

  int _getCurrentRank() {
    final activeJob = _jobs.firstWhere((j) => j['job_id'] == _currentJobId, orElse: () => {});
    return activeJob.isNotEmpty ? (activeJob['current_rank'] ?? 1) : 1;
  }

  Future<void> _fetchJobsDashboard() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _currentJobId = data['current_job_id'];
            _lastClaimed = data['last_claimed'];
            _jobs = List<Map<String, dynamic>>.from(data['jobs']);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startInterview(int jobId) async {
    setState(() => _isProcessing = true);
    try {
      final response = await http.get(Uri.parse('$apiUrl/interview/$jobId/${widget.userData['user_id']}'));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          _applyingForJobId = jobId;
          _interviewQuestions = data['questions'];
          _selectedAnswers.clear();
          _isInterviewing = true;
        });
      } else {
        _showSnackbar(data['error'], isError: true);
      }
    } catch (e) {
      _showSnackbar("Server error connecting to HR.", isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _submitInterview() async {
    if (_selectedAnswers.length < 5) return;
    setState(() => _isProcessing = true);
    List<Map<String, int>> answersPayload = _selectedAnswers.entries.map((e) => {"question_id": e.key, "selected_index": e.value}).toList();

    try {
      final response = await http.post(Uri.parse('$apiUrl/interview/submit'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id'], "job_id": _applyingForJobId, "answers": answersPayload}));

      final data = jsonDecode(response.body);
      _showSnackbar(data['message'], isError: !data['passed']);

      setState(() => _isInterviewing = false);
      await _fetchJobsDashboard();
    } catch (e) {} finally { if (mounted) setState(() => _isProcessing = false); }
  }

  Future<void> _promote() async {
    setState(() => _isProcessing = true);
    try {
      final response = await http.post(Uri.parse('$apiUrl/promote'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id']}));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _showSnackbar(data['message']);
        await _fetchJobsDashboard();
      } else {
        _showSnackbar(data['error'], isError: true);
      }
    } catch (e) {} finally { if (mounted) setState(() => _isProcessing = false); }
  }

  Future<void> _quitJob(String exitType) async {
    setState(() => _isProcessing = true);
    try {
      final response = await http.post(Uri.parse('$apiUrl/quit'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "user_id": widget.userData['user_id'],
            "exit_type": exitType
          }));
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _showSnackbar(data['message'], isError: exitType == 'heist');
        await _fetchJobsDashboard();
      } else {
        _showSnackbar(data['error'], isError: true);
      }
    } catch (e) {
      _showSnackbar("Server error processing resignation.", isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier')),
        backgroundColor: isError ? Colors.redAccent.shade700 : neonGreen.withOpacity(0.8)));
  }

  void _showResignationDialog(int currentRank) {
    int heistPayout = currentRank * 10000;

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            backgroundColor: darkSurface,
            shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.redAccent), borderRadius: BorderRadius.circular(8)),
            title: const Text("TERMINATE EMPLOYMENT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("How do you want to leave?", style: TextStyle(color: Colors.white, fontSize: 12)),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _quitJob('clean');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: matteBlack, side: const BorderSide(color: Colors.white24)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("CLEAN EXIT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 4),
                          Text("Put in your two weeks. 50% of your unspent Job Points will be saved if you ever return to this company.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _quitJob('heist');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1), side: const BorderSide(color: Colors.redAccent)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("THE FINAL HEIST", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text("Burn it to the ground. Steal \$${_formatNumber(heistPayout)} Dirty Cash. Lose all Job Points, gain MAX HEAT, and catch a 30-Day Ban.", style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54)))
            ],
          );
        }
    );
  }

  // --- JOB SPECIALS BOTTOM SHEET (TORN STYLE WIRED TO API) ---
  void _openSpecialExchangeSheet(Map<String, dynamic> special, int currentIncentives) {
    if (special['is_passive']) return;
    final TextEditingController amountController = TextEditingController(text: "1");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: darkSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12)), side: BorderSide(color: Color(0xFF39FF14), width: 1)),
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("JOB SPECIAL: ${special['name'].toUpperCase()}", style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("How many job points would you like to exchange for ${special['effect']}?", style: const TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(color: matteBlack, border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(4)),
                      child: TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.only(top: 10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withOpacity(0.1), side: BorderSide(color: neonGreen)),
                        onPressed: () async {
                          int amount = int.tryParse(amountController.text) ?? 0;
                          int totalCost = amount * (special['cost'] as int);

                          if (amount <= 0) { Navigator.pop(ctx); _showSnackbar("Invalid amount entered.", isError: true); return; }
                          if (currentIncentives < totalCost) { Navigator.pop(ctx); _showSnackbar("You need $totalCost Job Points to do this.", isError: true); return; }

                          // Close Bottom Sheet first
                          Navigator.pop(ctx);

                          // Execute the API Call
                          setState(() => _isProcessing = true);
                          try {
                            final response = await http.post(Uri.parse('$apiUrl/exchange'),
                                headers: {"Content-Type": "application/json"},
                                body: jsonEncode({"user_id": widget.userData['user_id'], "amount": amount}));

                            final data = jsonDecode(response.body);

                            if (response.statusCode == 200) {
                              _showSnackbar(data['message']);
                              await _fetchJobsDashboard();
                              // Call the parent's state change to update HP or Inventory globally
                              widget.onStateChange(widget.userData);
                            } else {
                              _showSnackbar(data['error'], isError: true);
                            }
                          } catch (e) {
                            _showSnackbar("Network error exchanging points.", isError: true);
                          } finally {
                            setState(() => _isProcessing = false);
                          }
                        },
                        child: Text("EXCHANGE", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  String _formatNumber(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  // Helper for Stats Display to prevent overflow
  Widget _buildStatBox(String label, int value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_formatNumber(value), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: matteBlack, body: Center(child: CircularProgressIndicator(color: neonGreen)));

    return Scaffold(
      backgroundColor: matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_isInterviewing ? "INTERVIEW IN PROGRESS" : "CITY EMPLOYMENT",
            style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
        iconTheme: IconThemeData(color: neonGreen),
        leading: _isInterviewing ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _isInterviewing = false)) : null,
        // --- MOVED RESIGN BUTTON TO APP BAR ---
        actions: [
          if (!_isInterviewing && _currentJobId != null && _currentJobId! > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton(
                onPressed: () => _showResignationDialog(_getCurrentRank()),
                child: const Text("RESIGN", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            )
        ],
      ),
      body: Stack(
        children: [
          _isInterviewing
              ? _buildInterviewScreen()
              : (_currentJobId != null && _currentJobId! > 0)
              ? _buildEmployedDashboard()
              : _buildUnemployedDashboard(),
          if (_isProcessing) Container(color: Colors.black54, child: Center(child: CircularProgressIndicator(color: neonGreen)))
        ],
      ),
    );
  }

  Widget _buildUnemployedDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), border: Border.all(color: Colors.redAccent)),
            child: const Text("YOU ARE CURRENTLY UNEMPLOYED.\nApply below to start earning Clean Cash and Working Stats.", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
          const Text("CITY JOBS DIRECTORY", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 12),
          ..._jobs.map((job) {
            bool hasBan = job['ban_expiry'] != null && DateTime.parse(job['ban_expiry']).isAfter(DateTime.now());
            return Card(
              color: darkSurface,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.white12), borderRadius: BorderRadius.circular(4)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job['job_name'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity, height: 30,
                      child: ElevatedButton(
                        onPressed: hasBan ? null : () => _startInterview(job['job_id']),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide(color: hasBan ? Colors.redAccent : Colors.white24)),
                        child: Text(hasBan ? "BANNED FROM APPLYING" : "APPLY NOW", style: TextStyle(color: hasBan ? Colors.redAccent : Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildInterviewScreen() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: neonGreen.withOpacity(0.1), border: Border.all(color: neonGreen)),
            child: const Text("HR ASSESSMENT:\nAnswer 4 out of 5 correctly to be hired. Failure results in a 24-hour application ban.", style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Courier')),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: _interviewQuestions.length,
              itemBuilder: (context, index) {
                var q = _interviewQuestions[index];
                List<dynamic> options = q['options'] is String ? jsonDecode(q['options']) : q['options'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Q${index + 1}: ${q['question_text']}", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ...options.asMap().entries.map((entry) {
                        int optIndex = entry.key;
                        bool isSelected = _selectedAnswers[q['question_id']] == optIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedAnswers[q['question_id']] = optIndex),
                          child: Container(
                            width: double.infinity, margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(color: isSelected ? neonGreen.withOpacity(0.2) : matteBlack, border: Border.all(color: isSelected ? neonGreen : Colors.white24), borderRadius: BorderRadius.circular(4)),
                            child: Text(entry.value, style: TextStyle(color: isSelected ? neonGreen : Colors.white70, fontSize: 12)),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedAnswers.length == 5 ? _submitInterview : null,
              style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withOpacity(0.2), side: BorderSide(color: neonGreen), padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text("SUBMIT ASSESSMENT", style: TextStyle(color: neonGreen, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEmployedDashboard() {
    final activeJob = _jobs.firstWhere((j) => j['job_id'] == _currentJobId, orElse: () => {});
    if (activeJob.isEmpty) return const SizedBox.shrink();

    final int jobId = activeJob['job_id'];
    final int currentRank = activeJob['current_rank'] ?? 1;
    final int incentiveBalance = activeJob['incentive_balance'] ?? 0;

    final List<Map<String, dynamic>> ranks = _rankData[jobId] ?? _rankData[1]!;
    final currentRankDetails = ranks.firstWhere((r) => r['rank'] == currentRank, orElse: () => ranks.first);

    final int acu = _parseSafeInt(widget.userData['stat_acu']);
    final int ops = _parseSafeInt(widget.userData['stat_ops']);
    final int pre = _parseSafeInt(widget.userData['stat_pre']);
    final int res = _parseSafeInt(widget.userData['stat_res']);

    bool statsMet = false;
    if (currentRank < 5) {
      final nextRankReq = ranks.firstWhere((r) => r['rank'] == currentRank + 1)['req'];
      statsMet = (acu >= nextRankReq['acu'] && ops >= nextRankReq['ops'] && pre >= nextRankReq['pre'] && res >= nextRankReq['res']);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // --- 1. COMPANY DETAILS ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Type: ${activeJob['job_name']}", style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text("Salary: \$${_formatNumber(currentRankDetails['pay'])} / day", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Position: ${currentRankDetails['title']}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text("Job Points: $incentiveBalance", style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- 2. CURRENT WORKING STATS & PROMOTION BUTTON ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("CURRENT WORKING STATS", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    if (statsMet && currentRank < 5)
                      SizedBox(
                        height: 24,
                        child: ElevatedButton(
                          onPressed: () => _promote(),
                          style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withOpacity(0.2), side: BorderSide(color: neonGreen), padding: const EdgeInsets.symmetric(horizontal: 12)),
                          child: Text("PROMOTE", style: TextStyle(color: neonGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      )
                  ],
                ),
                const Divider(color: Color(0xFF333333), height: 16),

                // --- FIXED OVERFLOW: Clean 4-Column Layout ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatBox("ACU", acu),
                    _buildStatBox("OPS", ops),
                    _buildStatBox("PRE", pre),
                    _buildStatBox("RES", res),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- 3. RANKS & PROMOTIONS LIST (COMPACT LAYOUT) ---
          const Text("RANKS & PROMOTIONS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 8),

          Container(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              children: ranks.map((rank) {
                bool isCurrent = rank['rank'] == currentRank;
                bool isLast = rank['rank'] == ranks.last['rank'];
                Map<String, dynamic> req = rank['req'];
                Map<String, dynamic> gain = rank['gain'];

                return Container(
                  decoration: BoxDecoration(
                    color: isCurrent ? neonGreen.withOpacity(0.05) : darkSurface,
                    border: Border(bottom: BorderSide(color: isLast ? Colors.transparent : const Color(0xFF333333))),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: isCurrent,
                      iconColor: isCurrent ? neonGreen : Colors.white54,
                      collapsedIconColor: Colors.white54,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      visualDensity: const VisualDensity(vertical: -4),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(rank['title'], style: TextStyle(color: isCurrent ? neonGreen : Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          Text("\$${_formatNumber(rank['pay'])} / day", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                          color: Colors.transparent,
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
                                        const Text("Req. Stats:", style: TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text("Acu: ${_formatNumber(req['acu'])} | Ops: ${_formatNumber(req['ops'])}\nPre: ${_formatNumber(req['pre'])} | Res: ${_formatNumber(req['res'])}", style: const TextStyle(color: Colors.white70, fontSize: 9, height: 1.2)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("Daily Gains:", style: TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text("+${gain['acu']} Acu | +${gain['ops']} Ops\n+${gain['pre']} Pre | +${gain['res']} Res", style: const TextStyle(color: Colors.white70, fontSize: 9, height: 1.2)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Promo Cost: ${rank['cost']} Inc", style: const TextStyle(color: Colors.amberAccent, fontSize: 9)),
                                  Text("Earns: ${rank['daily_inc']} Inc / day", style: const TextStyle(color: Colors.white54, fontSize: 9)),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // --- 4. TORN STYLE JOB SPECIALS ---
          const Text("JOB SPECIALS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 8),

          Container(
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: const Color(0xFF1A1A1A),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: Text("Special", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text("Effect", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),

                ...ranks.map((rank) {
                  bool isUnlocked = currentRank >= rank['rank'];
                  Map<String, dynamic> special = rank['special'];
                  bool isPassive = special['is_passive'];

                  return InkWell(
                    onTap: (isUnlocked && !isPassive) ? () => _openSpecialExchangeSheet(special, incentiveBalance) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF333333)))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    if (!isUnlocked) const Icon(Icons.lock, color: Colors.white24, size: 12),
                                    if (!isUnlocked) const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        special['name'],
                                        style: TextStyle(color: isUnlocked ? (isPassive ? Colors.cyanAccent : neonGreen) : Colors.white24, fontSize: 11, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    isPassive ? "Passive" : "Cost: ${special['cost']} Inc",
                                    style: TextStyle(color: isUnlocked ? Colors.amberAccent : Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                                special['effect'],
                                style: TextStyle(color: isUnlocked ? Colors.white70 : Colors.white24, fontSize: 10)
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}