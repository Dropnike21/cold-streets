import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api_config.dart';

class InfoBrokerView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final Function(int)? onNavigate;
  final Function(int)? onViewCompany; // For Company Navigation
  final int initialTabIndex;

  const InfoBrokerView({
    super.key,
    required this.userData,
    required this.onStateChange,
    this.onNavigate,
    this.onViewCompany,
    this.initialTabIndex = 0,
  });

  @override
  State<InfoBrokerView> createState() => _InfoBrokerViewState();
}

class _InfoBrokerViewState extends State<InfoBrokerView> {
  String get apiUrl => "${ApiConfig.baseUrl}/info-broker";
  String get companyApiUrl => "${ApiConfig.baseUrl}/companies";
  String get jobsApiUrl => "${ApiConfig.baseUrl}/jobs";

  bool _isLoading = true;
  bool _isProcessing = false;

  List<dynamic> _news = [];
  List<dynamic> _bounties = [];
  List<dynamic> _classifieds = [];
  List<dynamic> _directoryTypes = [];
  List<dynamic> _cityJobs = [];

  // --- Unified Employment Tracking ---
  int? _currentCityJobId;
  Map<String, dynamic>? _privateEmployment;

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);
  final Color darkGrey = const Color(0xFF2A2A2A);

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    try {
      final String userId = widget.userData['user_id'].toString();
      final responses = await Future.wait([
        http.get(Uri.parse('$apiUrl/frontpage')),
        http.get(Uri.parse('$companyApiUrl/directory/types')),
        http.get(Uri.parse('$jobsApiUrl/$userId'))
      ]);

      if (responses.every((res) => res.statusCode == 200)) {
        if (mounted) {
          final jobsData = jsonDecode(responses[2].body);

          setState(() {
            _news = jsonDecode(responses[0].body)['news'] ?? [];
            _bounties = jsonDecode(responses[0].body)['bounties'] ?? [];
            _classifieds = jsonDecode(responses[0].body)['classifieds'] ?? [];
            _directoryTypes = jsonDecode(responses[1].body)['types'] ?? [];

            // --- Parsing Employment Status ---
            _cityJobs = jobsData['jobs'] ?? [];
            _currentCityJobId = jobsData['current_job_id'];
            _privateEmployment = jobsData['private_employment'];

            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatNumber(dynamic amount) {
    int val = amount is int ? amount : int.tryParse(amount.toString()) ?? 0;
    return val.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.redAccent : Colors.green));
  }

  // ==========================================
  // MODALS: PLACING ADS & BOUNTIES
  // ==========================================

  void _showAdDialog() {
    final TextEditingController adController = TextEditingController();
    int currentCost = 0;

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
                  backgroundColor: darkSurface,
                  shape: RoundedRectangleBorder(side: BorderSide(color: neonGreen), borderRadius: BorderRadius.circular(4)),
                  title: Text("POST CLASSIFIED", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Courier')),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Ads cost \$10 Clean Cash per character and last 24 hours.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: adController,
                        maxLength: 150,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: const InputDecoration(
                          filled: true, fillColor: Colors.black,
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF39FF14))),
                        ),
                        onChanged: (text) => setStateDialog(() => currentCost = text.length * 10),
                      ),
                      const SizedBox(height: 8),
                      Text("Total Cost: \$${_formatNumber(currentCost)}", style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withOpacity(0.1), side: BorderSide(color: neonGreen)),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (adController.text.trim().isNotEmpty) {
                          setState(() => _isProcessing = true);
                          try {
                            final res = await http.post(Uri.parse('$apiUrl/classifieds'),
                                headers: {"Content-Type": "application/json"},
                                body: jsonEncode({"user_id": widget.userData['user_id'], "ad_text": adController.text}));
                            final data = jsonDecode(res.body);
                            _showSnackbar(data['message'] ?? data['error'], isError: res.statusCode != 200);
                            if (res.statusCode == 200) await _fetchAllData();
                          } catch (e) { _showSnackbar("Network Error", isError: true); }
                          finally { setState(() => _isProcessing = false); }
                        }
                      },
                      child: Text("POST AD", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold)),
                    )
                  ],
                );
              }
          );
        }
    );
  }

  void _showBountyDialog() {
    final TextEditingController targetController = TextEditingController();
    final TextEditingController rewardController = TextEditingController();
    bool isAnonymous = false;

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
                  backgroundColor: darkSurface,
                  shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)),
                  title: const Text("ISSUE HIT CONTRACT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Courier')),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Bounties require a minimum of \$500 Dirty Cash.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: targetController,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: const InputDecoration(filled: true, fillColor: Colors.black, labelText: "Target Username", labelStyle: TextStyle(color: Colors.white54), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.redAccent))),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: rewardController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                        decoration: const InputDecoration(filled: true, fillColor: Colors.black, prefixText: "\$ ", labelText: "Reward Amount", labelStyle: TextStyle(color: Colors.white54), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)), focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.redAccent))),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: isAnonymous,
                            activeColor: Colors.redAccent,
                            onChanged: (val) => setStateDialog(() => isAnonymous = val!),
                          ),
                          const Text("Post Anonymously", style: TextStyle(color: Colors.white70, fontSize: 11))
                        ],
                      )
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1), side: const BorderSide(color: Colors.redAccent)),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        setState(() => _isProcessing = true);
                        try {
                          final res = await http.post(Uri.parse('$apiUrl/bounty'),
                              headers: {"Content-Type": "application/json"},
                              body: jsonEncode({"user_id": widget.userData['user_id'], "target_username": targetController.text, "reward_cash": rewardController.text, "is_anonymous": isAnonymous}));
                          final data = jsonDecode(res.body);
                          _showSnackbar(data['message'] ?? data['error'], isError: res.statusCode != 200);
                          if (res.statusCode == 200) await _fetchAllData();
                        } catch (e) { _showSnackbar("Network Error", isError: true); }
                        finally { setState(() => _isProcessing = false); }
                      },
                      child: const Text("ISSUE HIT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    )
                  ],
                );
              }
          );
        }
    );
  }

  // ==========================================
  // MODALS: CORPORATE RECRUITMENT FLOW
  // ==========================================

  void _showIndustryDetails(int typeId, String industryName) {
    bool isModalLoading = true;
    List<dynamic> positions = [];
    List<dynamic> activeCompanies = [];

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isModalLoading) {
              http.get(Uri.parse('$companyApiUrl/directory/details/$typeId')).then((res) {
                if (res.statusCode == 200) {
                  final data = jsonDecode(res.body);
                  setModalState(() {
                    positions = data['positions'] ?? [];
                    activeCompanies = data['companies'] ?? [];
                    isModalLoading = false;
                  });
                }
              });
            }

            return Dialog(
              backgroundColor: matteBlack,
              insetPadding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(side: BorderSide(color: neonGreen), borderRadius: BorderRadius.circular(4)),
              child: isModalLoading
                  ? SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: neonGreen)))
                  : Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  _buildModalHeader(industryName, ctx),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildSectionTitle("INDUSTRY ROLES"),
                        ...positions.map((pos) => _buildPositionTile(pos)),
                        const SizedBox(height: 24),
                        _buildSectionTitle("ESTABLISHED ENTERPRISES"),
                        if (activeCompanies.isEmpty)
                          const Text("No active player-owned companies.", style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ...activeCompanies.map((comp) => _buildCompanyApplyTile(comp, ctx)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showApplicationPitch(int companyId, String companyName) {
    final TextEditingController pitchController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: darkSurface,
        title: Text("APPLY TO $companyName", style: TextStyle(color: neonGreen, fontSize: 14, fontFamily: 'Courier')),
        content: TextField(
          controller: pitchController,
          maxLines: 4,
          maxLength: 200,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(hintText: "Why should the Director hire you?", hintStyle: TextStyle(color: Colors.white24), border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: neonGreen),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isProcessing = true);
              try {
                final res = await http.post(Uri.parse('$companyApiUrl/apply'),
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({"user_id": widget.userData['user_id'], "company_id": companyId, "pitch_message": pitchController.text}));
                final data = jsonDecode(res.body);
                _showSnackbar(data['message'] ?? data['error'], isError: res.statusCode != 200);
              } catch (e) { _showSnackbar("Connection error.", isError: true); }
              finally { setState(() => _isProcessing = false); }
            },
            child: const Text("SUBMIT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // ==========================================
  // UI BUILDER HELPERS
  // ==========================================

  Widget _buildModalHeader(String title, BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF333333)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title.toUpperCase(), style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1, fontFamily: 'Courier')),
          IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, fontFamily: 'Courier')),
    );
  }

  Widget _buildPositionTile(dynamic pos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pos['role_name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("Primary: ${pos['req_stat_primary']} | Secondary: ${pos['req_stat_secondary']}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text("Gains: ${pos['stat_gain_desc']}", style: TextStyle(color: neonGreen.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCompanyApplyTile(dynamic comp, BuildContext modalCtx) {
    // Determine if the "Apply" button should be locked out
    bool isEmployed = _currentCityJobId != null || _privateEmployment != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: neonGreen.withOpacity(0.2))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comp['company_name'], style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold)),
                Text("Owner: ${comp['owner_name']} | Rating: ${comp['star_rating']}★", style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: isEmployed ? Colors.black26 : Colors.transparent,
                side: BorderSide(color: isEmployed ? Colors.white24 : neonGreen)
            ),
            onPressed: () {
              if (isEmployed) {
                _showSnackbar("You must resign from your current job first.", isError: true);
              } else {
                Navigator.pop(modalCtx);
                _showApplicationPitch(comp['company_id'], comp['company_name']);
              }
            },
            child: Text(isEmployed ? "RESTRICTED" : "APPLY", style: TextStyle(color: isEmployed ? Colors.white24 : Colors.white, fontSize: 10)),
          )
        ],
      ),
    );
  }

  // --- TAB 1: ONION.BBS (News & Ads) ---
  Widget _buildTheWireTab() {
    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        const Text("> SYSTEM.BROADCAST", style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: darkSurface, border: Border.all(color: Colors.cyanAccent.withOpacity(0.3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _news.isEmpty
                ? [const Text("No active events. The city is sleeping.", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic))]
                : _news.map((n) => Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Text("[${n['category']}] ${n['headline']}", style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Courier')),
            )).toList(),
          ),
        ),

        const SizedBox(height: 24),
        const Text("> CLASSIFIEDS", style: TextStyle(color: Color(0xFF39FF14), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
        const SizedBox(height: 8),
        if (_classifieds.isEmpty)
          const Text("No ads currently running.", style: TextStyle(color: Colors.white54, fontSize: 11)),
        ..._classifieds.map((c) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: darkGrey, border: Border(left: BorderSide(color: neonGreen, width: 3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${c['ad_text']}"', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.person, color: Colors.white38, size: 12),
                  const SizedBox(width: 4),
                  Text(c['username'].toString().toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        )),
        const SizedBox(height: 60),
      ],
    );
  }

  // --- TAB 2: THE HITLIST ---
  Widget _buildHitlistTab() {
    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), border: Border.all(color: Colors.redAccent)),
          child: const Text("WARNING: Claiming bounties initiates immediate PvP combat. Ensure your Battle Stats and Loadout are prepared.", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 16),
        if (_bounties.isEmpty)
          const Center(child: Text("The streets are safe. No active hits.", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic))),
        ..._bounties.map((b) {
          String placersName = b['is_anonymous'] ? "Anonymous" : b['placed_by_username'];
          return Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: Colors.redAccent.withOpacity(0.5))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${b['target_username']} [Lv. ${b['target_level']}]", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text("Client: $placersName", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("\$${_formatNumber(b['reward_cash'])}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Courier')),
                    const SizedBox(height: 4),
                    ElevatedButton(
                      onPressed: () { /* Future PvP implementation */ },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.2), side: const BorderSide(color: Colors.redAccent), minimumSize: const Size(60, 26), padding: const EdgeInsets.symmetric(horizontal: 12)),
                      child: const Text("ATTACK", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 60),
      ],
    );
  }

  // --- TAB 3: CAREERS & DIRECTORY (NEW BANNER UI) ---
  Widget _buildCareersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // --- STATUS BANNERS ---
        if (_currentCityJobId != null) ...[
          Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), border: Border.all(color: Colors.cyanAccent)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("STATUS: CITY EMPLOYEE", style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text("You are on the city payroll. Resign before applying to the private sector.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () => widget.onNavigate?.call(_currentCityJobId!),
                        style: ElevatedButton.styleFrom(backgroundColor: matteBlack, side: const BorderSide(color: Colors.cyanAccent)),
                        child: const Text("GO TO CITY DASHBOARD", style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    )
                  ]
              )
          )
        ] else if (_privateEmployment != null) ...[
          Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(color: neonGreen.withOpacity(0.1), border: Border.all(color: neonGreen)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("STATUS: ${_privateEmployment!['role'] == 'Director' ? 'DIRECTOR' : 'PRIVATE SECTOR'}", style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("${_privateEmployment!['role'] == 'Director' ? 'Owner of' : 'Employed at'}: ${_privateEmployment!['company_name']}", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text("You must resign or liquidate assets before seeking new employment.", style: TextStyle(color: Colors.white54, fontSize: 10)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          if (widget.onViewCompany != null) {
                            widget.onViewCompany!(_privateEmployment!['company_id']);
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: matteBlack, side: BorderSide(color: neonGreen)),
                        child: Text("GO TO COMPANY DASHBOARD", style: TextStyle(color: neonGreen, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ),
                    )
                  ]
              )
          )
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), border: Border.all(color: Colors.redAccent)),
            child: const Text("STATUS: UNEMPLOYED\nYou are currently generating no active income or daily stats. Apply below.", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold, height: 1.4)),
          ),
        ],

        // --- DIRECTORY REMAINS VISIBLE ---
        _buildSectionTitle("CITY SECTOR"),
        // Changed "Apply" to "View" so users can inspect requirements without committing
        ..._cityJobs.map((job) => _buildCareerTile(
            job['job_name'],
            "View",
            Colors.cyanAccent,
                () => widget.onNavigate?.call(job['job_id'])
        )),

        const Divider(color: Colors.white10, height: 40),

        _buildSectionTitle("PRIVATE SECTOR"),
        if (_directoryTypes.isEmpty)
          const Text("No industries established yet.", style: TextStyle(color: Colors.white38, fontSize: 11)),
        ..._directoryTypes.map((type) => _buildCareerTile(
            "${type['industry_type']} (${type['active_count']} Active)",
            "View",
            neonGreen,
                () => _showIndustryDetails(type['type_id'], type['industry_type'])
        )),
      ],
    );
  }

  Widget _buildCareerTile(String title, String actionLabel, Color themeColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: darkSurface, border: Border.all(color: themeColor.withOpacity(0.3))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            Text(actionLabel, style: TextStyle(color: themeColor, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MAIN SCAFFOLD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: matteBlack, body: Center(child: CircularProgressIndicator(color: neonGreen)));

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        backgroundColor: matteBlack,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text("INFO BROKER", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Courier', letterSpacing: 2)),
          iconTheme: IconThemeData(color: neonGreen),
          bottom: TabBar(
            indicatorColor: neonGreen, labelColor: neonGreen, unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
            tabs: const [Tab(text: "ONION.BBS"), Tab(text: "HITLIST"), Tab(text: "CAREERS")],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                _buildTheWireTab(),
                _buildHitlistTab(),
                _buildCareersTab(),
              ],
            ),
            if (_isProcessing) Container(color: Colors.black54, child: Center(child: CircularProgressIndicator(color: neonGreen)))
          ],
        ),

        floatingActionButton: Builder(
          builder: (context) {
            final TabController tabController = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tabController.animation!,
              builder: (context, child) {
                if (tabController.index == 0) {
                  return FloatingActionButton.extended(
                    onPressed: _showAdDialog,
                    backgroundColor: neonGreen,
                    icon: const Icon(Icons.campaign, color: Colors.black),
                    label: const Text("POST AD", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  );
                } else if (tabController.index == 1) {
                  return FloatingActionButton.extended(
                    onPressed: _showBountyDialog,
                    backgroundColor: Colors.redAccent,
                    icon: const Icon(Icons.warning, color: Colors.white),
                    label: const Text("PLACE BOUNTY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  );
                }
                return const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );
  }
}