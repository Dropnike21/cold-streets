import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';

class JobsView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final VoidCallback? onBack;
  final int? viewingJobId; // <-- NEW: Tells the view what the player wants to look at

  const JobsView({
    super.key,
    required this.userData,
    required this.onStateChange,
    this.onBack,
    this.viewingJobId, // <-- NEW
  });

  @override
  State<JobsView> createState() => _JobsViewState();
}

class _JobsViewState extends State<JobsView> {
  final String apiUrl = "http://10.0.2.2:3000/jobs";

  bool _isLoading = true;
  bool _isProcessing = false;

  int? _currentJobId;
  String? _lastClaimed;
  Map<String, dynamic>? _privateEmployment; // <-- Unified Status
  List<Map<String, dynamic>> _jobs = [];

  bool _isInterviewing = false;
  int _applyingForJobId = 0;
  List<dynamic> _interviewQuestions = [];
  Map<int, int> _selectedAnswers = {};

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _fetchJobsDashboard();
  }

  int _parseSafeInt(dynamic value) => (value is int) ? value : int.tryParse(value?.toString() ?? '0') ?? 0;

  Future<void> _fetchJobsDashboard() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _currentJobId = data['current_job_id'];
            _lastClaimed = data['last_claimed'];
            _privateEmployment = data['private_employment']; // Unified check
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
          body: jsonEncode({"user_id": widget.userData['user_id'], "exit_type": exitType}));
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
                    onPressed: () { Navigator.pop(ctx); _quitJob('clean'); },
                    style: ElevatedButton.styleFrom(backgroundColor: matteBlack, side: const BorderSide(color: Colors.white24)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("CLEAN EXIT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 4),
                          Text("Put in your two weeks. 50% of your unspent Job Points will be saved.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () { Navigator.pop(ctx); _quitJob('heist'); },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1), side: const BorderSide(color: Colors.redAccent)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("THE FINAL HEIST", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text("Steal \$${_formatNumber(heistPayout)} Dirty Cash. Lose all Job Points, gain MAX HEAT, and catch a 30-Day Ban.", style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54)))],
          );
        }
    );
  }

  void _openSpecialExchangeSheet(Map<String, dynamic> special, int currentIncentives) {
    if (special['is_passive'] == true) return;
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

                          if (amount <= 0) { Navigator.pop(ctx); _showSnackbar("Invalid amount.", isError: true); return; }
                          if (currentIncentives < totalCost) { Navigator.pop(ctx); _showSnackbar("You need $totalCost Job Points.", isError: true); return; }

                          Navigator.pop(ctx);
                          setState(() => _isProcessing = true);
                          try {
                            final response = await http.post(Uri.parse('$apiUrl/exchange'),
                                headers: {"Content-Type": "application/json"},
                                body: jsonEncode({"user_id": widget.userData['user_id'], "amount": amount}));
                            final data = jsonDecode(response.body);
                            if (response.statusCode == 200) {
                              _showSnackbar(data['message']);
                              await _fetchJobsDashboard();
                              widget.onStateChange(widget.userData);
                            } else {
                              _showSnackbar(data['error'], isError: true);
                            }
                          } catch (e) { _showSnackbar("Network error.", isError: true); }
                          finally { setState(() => _isProcessing = false); }
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

  String _formatNumber(dynamic amount) {
    int val = amount is int ? amount : int.tryParse(amount.toString()) ?? 0;
    return val.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  Widget _buildStatBox(String label, int value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_formatNumber(value), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ==========================================
  // MAIN ROUTING BUILDER
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: matteBlack, body: Center(child: CircularProgressIndicator(color: neonGreen)));

    Widget bodyWidget;
    bool showResignButton = false;

    // 1. Interview Screen wins
    if (_isInterviewing) {
      bodyWidget = _buildInterviewScreen();
    }
    // 2. Smart Routing: If viewingJobId is their current job, or viewingJobId is null, show Dashboard
    else if (_currentJobId != null && (widget.viewingJobId == null || widget.viewingJobId == _currentJobId)) {
      bodyWidget = _buildEmployedDashboard();
      showResignButton = true;
    }
    // 3. Kiosk Mode: They are viewing a specific job they don't own
    else if (widget.viewingJobId != null) {
      bodyWidget = _buildKioskMode(widget.viewingJobId!);
    }
    // 4. Fallback Error State
    else {
      bodyWidget = const Center(child: Text("ERROR: No Job Selected", style: TextStyle(color: Colors.redAccent)));
    }

    return Scaffold(
      backgroundColor: matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_isInterviewing ? "INTERVIEW IN PROGRESS" : "CITY EMPLOYMENT",
            style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
        iconTheme: IconThemeData(color: neonGreen),
        leading: _isInterviewing
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _isInterviewing = false))
            : (widget.onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack) : null),
        actions: [
          if (showResignButton)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton(
                onPressed: () {
                  final activeJob = _jobs.firstWhere((j) => j['job_id'] == _currentJobId, orElse: () => {});
                  _showResignationDialog(activeJob['current_rank'] ?? 1);
                },
                child: const Text("RESIGN", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            )
        ],
      ),
      body: Stack(
        children: [
          bodyWidget,
          if (_isProcessing) Container(color: Colors.black54, child: Center(child: CircularProgressIndicator(color: neonGreen)))
        ],
      ),
    );
  }

  // ==========================================
  // KIOSK MODE (WINDOW SHOPPING)
  // ==========================================
  Widget _buildKioskMode(int jobId) {
    final job = _jobs.firstWhere((j) => j['job_id'] == jobId, orElse: () => {});
    if (job.isEmpty) return const Center(child: Text("Job data corrupted.", style: TextStyle(color: Colors.redAccent)));

    List<dynamic> ranks = job['ranks'] ?? [];

    // GATEKEEPER UI LOGIC
    bool hasCityJob = _currentJobId != null;
    bool hasPrivateJob = _privateEmployment != null;
    bool isBanned = job['ban_expiry'] != null && DateTime.parse(job['ban_expiry']).isAfter(DateTime.now());

    String btnText = "TAKE INTERVIEW";
    Color btnColor = neonGreen;
    VoidCallback? onBtnPressed = () => _startInterview(jobId);

    if (isBanned) {
      btnText = "BANNED FROM APPLYING";
      btnColor = Colors.redAccent;
      onBtnPressed = null;
    } else if (hasCityJob) {
      btnText = "RESTRICTED (CITY EMPLOYEE)";
      btnColor = Colors.white24;
      onBtnPressed = () => _showSnackbar("Resign from your current City Job first.", isError: true);
    } else if (hasPrivateJob) {
      btnText = "RESTRICTED (PRIVATE SECTOR)";
      btnColor = Colors.white24;
      onBtnPressed = () => _showSnackbar("Resign from your Private Sector position first.", isError: true);
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job['job_name'].toString().toUpperCase(), style: TextStyle(color: neonGreen, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 8),
                Text("Primary Stat Requirement: ${job['primary_stat'].toString().toUpperCase()}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                const Divider(color: Color(0xFF333333), height: 32),

                const Text("CAREER PATH & SPECIALS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 12),

                Container(
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
                  child: Column(
                    children: ranks.map((rank) {
                      bool isLast = rank['rank_level'] == ranks.last['rank_level'];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: darkSurface, border: Border(bottom: BorderSide(color: isLast ? Colors.transparent : const Color(0xFF333333)))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(rank['title'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                Text("\$${_formatNumber(rank['daily_pay'])} / day", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Req: ${_formatNumber(rank['stat_req_value'])} ${job['primary_stat'].toString().toUpperCase()}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
                                Text("Earns: ${rank['daily_incentives']} Job Points / day", style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity, padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.black45, border: Border.all(color: Colors.white12)),
                              child: Text("Perk: ${rank['special']['effect']}", style: TextStyle(color: neonGreen.withOpacity(0.8), fontSize: 10, fontStyle: FontStyle.italic)),
                            )
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),

        // BOTTOM ACTION BAR
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Color(0xFF1A1A1A), border: Border(top: BorderSide(color: Color(0xFF333333)))),
          child: SizedBox(
            width: double.infinity, height: 45,
            child: ElevatedButton(
              onPressed: onBtnPressed,
              style: ElevatedButton.styleFrom(backgroundColor: btnColor.withOpacity(0.1), side: BorderSide(color: btnColor)),
              child: Text(btnText, style: TextStyle(color: btnColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
        )
      ],
    );
  }

  // ==========================================
  // EMPLOYED DASHBOARD
  // ==========================================
  Widget _buildEmployedDashboard() {
    final activeJob = _jobs.firstWhere((j) => j['job_id'] == _currentJobId, orElse: () => {});
    if (activeJob.isEmpty) return const SizedBox.shrink();

    final int currentRank = activeJob['current_rank'] ?? 1;
    final int incentiveBalance = activeJob['incentive_balance'] ?? 0;
    final String primaryStat = activeJob['primary_stat'];

    final List<dynamic> ranksList = activeJob['ranks'] ?? [];
    final Map<String, dynamic> currentRankDetails = ranksList.firstWhere((r) => r['rank_level'] == currentRank, orElse: () => ranksList.isNotEmpty ? ranksList.first : {});

    final int acu = _parseSafeInt(widget.userData['stat_acu']);
    final int ops = _parseSafeInt(widget.userData['stat_ops']);
    final int pre = _parseSafeInt(widget.userData['stat_pre']);
    final int res = _parseSafeInt(widget.userData['stat_res']);

    // Check if they have the specific stat required to promote
    int playerPrimaryStat = _parseSafeInt(widget.userData['stat_$primaryStat']);
    bool statsMet = false;
    if (currentRank < 5 && ranksList.length > currentRank) {
      final nextRankDetails = ranksList.firstWhere((r) => r['rank_level'] == currentRank + 1);
      statsMet = playerPrimaryStat >= nextRankDetails['stat_req_value'];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    Text("Salary: \$${_formatNumber(currentRankDetails['daily_pay'] ?? 0)} / day", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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

          const Text("RANKS & PROMOTIONS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 8),

          Container(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              children: ranksList.map((rank) {
                bool isCurrent = rank['rank_level'] == currentRank;
                bool isLast = rank['rank_level'] == ranksList.last['rank_level'];

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
                          Text("\$${_formatNumber(rank['daily_pay'])} / day", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                          color: Colors.transparent,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Req: ${_formatNumber(rank['stat_req_value'])} ${primaryStat.toUpperCase()}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Promo Cost: ${rank['promotion_cost']} Inc", style: const TextStyle(color: Colors.amberAccent, fontSize: 9)),
                                  Text("Earns: ${rank['daily_incentives']} Inc / day", style: const TextStyle(color: Colors.white54, fontSize: 9)),
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

                ...ranksList.map((rank) {
                  bool isUnlocked = currentRank >= rank['rank_level'];
                  Map<String, dynamic> special = rank['special'];
                  bool isPassive = special['is_passive'] ?? false;

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

  // ==========================================
  // INTERVIEW SCREEN
  // ==========================================
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
}