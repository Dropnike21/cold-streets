import 'package:flutter/material.dart';
import '../api_config.dart';
import '../services/game_http.dart' as http;
import 'dart:convert';

class CompanyDashboardView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final int companyId;
  final VoidCallback? onBack;
  final VoidCallback? onManage;

  const CompanyDashboardView({
    super.key,
    required this.userData,
    required this.companyId,
    this.onBack,
    this.onManage
  });

  @override
  State<CompanyDashboardView> createState() => _CompanyDashboardViewState();
}

class _CompanyDashboardViewState extends State<CompanyDashboardView> {
  String get apiUrl => '${ApiConfig.baseUrl}/companies';
  bool _isLoading = true;

  // Economic Engine Data[cite: 1]
  double _runway = 0.0;
  bool _runwayAvailable = false;
  int _totalCosts = 0;

  Map<String, dynamic> _company = {};
  Map<String, dynamic> _cashFlow = {};
  List<dynamic> _roster = [];
  List<dynamic> _logs = [];
  List<dynamic> _specials = [];
  String _userRole = "Employee";
  int _userSalary = 0;

  int _selectedLogTab = 0;


  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _fetchDashboard();
  }

  // --- API LOGIC ---

  Future<void> _fetchDashboard() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/${widget.companyId}/dashboard/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _company = data['company'] ?? {};
            _roster = data['roster'] ?? [];
            _logs = data['logs'] ?? [];
            _specials = data['specials'] ?? [];
            _userRole = data['user_role'] ?? 'Employee';
            _cashFlow = data['cash_flow'] is Map
                ? Map<String, dynamic>.from(data['cash_flow'])
                : <String, dynamic>{};

            final runwayRaw = data['runway_days'];
            _runwayAvailable = runwayRaw != null;
            _runway = double.tryParse(runwayRaw?.toString() ?? '') ?? 0.0;
            _totalCosts = _safeInt(data['total_daily_costs']);

            final myData = _roster.firstWhere((emp) => emp['username'] == widget.userData['username'], orElse: () => <String, dynamic>{});
            _userSalary = _safeInt(myData['daily_salary']);

            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- HELPER METHODS ---

  String _formatDate(String isoString) {
    try {
      DateTime dt = DateTime.parse(isoString).toLocal();
      String month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1];
      String day = dt.day.toString().padLeft(2, '0');
      int hour = dt.hour;
      String period = hour >= 12 ? 'PM' : 'AM';
      if (hour == 0) hour = 12;
      if (hour > 12) hour -= 12;
      return "$month $day, ${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period";
    } catch (e) { return isoString; }
  }

  String _formatNumber(dynamic amount) {
    int val = _safeInt(amount);
    return val.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  int _safeInt(dynamic val, {int fallback = 0}) {
    if (val == null) return fallback;
    if (val is int) return val;
    if (val is double) return val.toInt();
    // Handles string decimals like "5.0" common in PostgreSQL output[cite: 5]
    return (double.tryParse(val.toString()) ?? fallback.toDouble()).toInt();
  }

  // --- UI COMPONENTS ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: matteBlack, body: Center(child: CircularProgressIndicator(color: neonGreen)));

    String headerName = (_company['company_name'] ?? "ENTERPRISE").toString().toUpperCase();

    // Bulletproof Director Check[cite: 5]
    bool isDirector = (_userRole.toString().trim().toLowerCase() == 'director') ||
        (_company['owner_id']?.toString() == widget.userData['user_id'].toString());

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: matteBlack,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: neonGreen),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack ?? () => Navigator.pop(context)),
          title: Text(headerName, style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
          actions: [
            // --- THE DIRECTOR'S SETTINGS GEAR ---
            if (isDirector)
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.cyanAccent),
                tooltip: "Manage Enterprise",
                onPressed: () {
                  if (widget.onManage != null) {
                    widget.onManage!();
                  }
                },
              ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            indicatorColor: neonGreen, labelColor: neonGreen, unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
            tabs: const [Tab(text: "DASHBOARD"), Tab(text: "AFFILIATIONS")],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDashboardTab(),
            _buildAffiliationsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCompanyHeader(),
          _buildRunwayInfo(), // Dynamic Bankruptcy Indicator[cite: 1]
          const SizedBox(height: 16),
          _buildCompanyDetailsGrid(),
          const SizedBox(height: 16),
          _buildPersonalDetails(),
          const SizedBox(height: 16),
          // --- INCOME CHART MOVED HERE ---
          _buildIncomeChartView(),
          const SizedBox(height: 16),
          _buildCompanySpecials(), // Dynamic Specials from Database[cite: 2]
          const SizedBox(height: 16),
          _buildEventLogs(), // Dynamic Logs from Database[cite: 2]
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCompanyHeader() {
    int pop = _safeInt(_company['popularity'], fallback: 0);
    int eff = _safeInt(_company['efficiency'], fallback: 0);
    int env = _safeInt(_company['environment'], fallback: 100);

    String industryStr = (_company['industry_type'] ?? "Unknown").toString();
    String tierStr = (_company['tier'] ?? "1").toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text("$industryStr (Tier $tierStr)".toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildProgressBar("POPULARITY", pop, Colors.amberAccent)),
              const SizedBox(width: 8),
              Expanded(child: _buildProgressBar("EFFICIENCY", eff, Colors.cyanAccent)),
              const SizedBox(width: 8),
              Expanded(child: _buildProgressBar("ENVIRONMENT", env, neonGreen)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, int value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text("$value%", style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: value / 100, backgroundColor: Colors.black, color: color, minHeight: 4),
      ],
    );
  }

  Widget _buildRunwayInfo() {
    if (!_runwayAvailable) {
      return const SizedBox.shrink();
    }

    final Color runwayColor =
        _runway < 2.0 ? Colors.redAccent : Colors.amber;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: runwayColor.withValues(alpha: 0.05),
        border: Border.all(color: runwayColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          const Text(
            "RUNWAY REFERENCE ONLY",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "${_runway.toStringAsFixed(1)} DAYS",
            style: TextStyle(
              color: runwayColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            "Salaries + upkeep reference: \$${_formatNumber(_totalCosts)} / day",
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
          const SizedBox(height: 4),
          const Text(
            "Automatic bankruptcy and severance settlement are paused.",
            style: TextStyle(color: Colors.white38, fontSize: 8),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyDetailsGrid() {
    int dailyInc = _safeInt(_company['daily_income']);
    int age = _safeInt(_company['age_days']);
    int stars = _safeInt(_company['star_rating']);
    int maxEmps = _safeInt(_company['max_employees']);
    final salesStatus =
        _cashFlow['sales_settlement_available'] == true ? "ACTIVE" : "PAUSED";
    final payrollStatus =
        _cashFlow['payroll_settlement_available'] == true ? "ACTIVE" : "PAUSED";

    String director = (_company['owner_name'] ?? "Unknown").toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("CORPORATE DATA", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const Divider(color: Color(0xFF333333), height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompactDetail("Director:", director),
                    _buildCompactDetail("Employees:", "${_roster.length} / $maxEmps"),
                    _buildCompactDetail("Bank (Clean):", "\$${_formatNumber(_company['bank_clean'])}", valColor: Colors.white),
                    _buildCompactDetail("Bank (Dirty):", "\$${_formatNumber(_company['bank_dirty'])}", valColor: neonGreen),
                    _buildCompactDetail("Daily Upkeep:", "-\$${_formatNumber(_company['daily_upkeep'])}", valColor: Colors.redAccent),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompactDetail(
                      "Recorded Income:",
                      "\$${_formatNumber(dailyInc)}",
                      valColor: Colors.white70,
                    ),
                    _buildCompactDetail(
                      "Sales Settlement:",
                      salesStatus,
                      valColor: salesStatus == "ACTIVE"
                          ? Colors.greenAccent
                          : Colors.amber,
                    ),
                    const SizedBox(height: 6),
                    _buildCompactDetail(
                      "Payroll Settlement:",
                      payrollStatus,
                      valColor: payrollStatus == "ACTIVE"
                          ? Colors.greenAccent
                          : Colors.amber,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompactDetail("Age:", "$age Days"),
                    const SizedBox(height: 6),
                    const Text(
                      "Rating:",
                      style: TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                    Row(
                      children: [
                        Icon(
                          stars > 0 ? Icons.star : Icons.star_border,
                          color: Colors.amberAccent,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "$stars / 10",
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDetail(String label, String value, {Color valColor = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
          Text(value, style: TextStyle(color: valColor, fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildPersonalDetails() {
    int jobPoints = _safeInt(_company['incentive_balance'], fallback: 0);
    int acu = _safeInt(widget.userData['stat_acu']);
    int ops = _safeInt(widget.userData['stat_ops']);
    int pre = _safeInt(widget.userData['stat_pre']);
    int res = _safeInt(widget.userData['stat_res']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("PERSONAL PROFILE", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const Divider(color: Color(0xFF333333), height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompactDetail("Position:", _userRole, valColor: neonGreen),
                    const SizedBox(height: 6),
                    _buildCompactDetail("Agreed Salary:", "\$${_formatNumber(_userSalary)} Clean / day", valColor: Colors.white),
                    const SizedBox(height: 6),
                    const Text("Payroll settlement paused", style: TextStyle(color: Colors.amber, fontSize: 8)),
                    const SizedBox(height: 3),
                    _buildCompactDetail("Job Incentives:", "$jobPoints Points", valColor: Colors.amberAccent),
                  ],
                ),
              ),
              Container(width: 1, height: 80, color: const Color(0xFF333333), margin: const EdgeInsets.symmetric(horizontal: 12)),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("WORKING STATS", style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCompactDetail("Acu:", _formatNumber(acu)),
                        _buildCompactDetail("Ops:", _formatNumber(ops)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCompactDetail("Pre:", _formatNumber(pre)),
                        _buildCompactDetail("Res:", _formatNumber(res)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeChartView() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: darkSurface,
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "CASH-FLOW SETTLEMENT",
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Revenue history is not authoritative yet. Tier-3 clean-ratio sales, payroll conversion, laundering tax/ACU effects, advertising spend, and bankruptcy settlement are paused until their daily settlement rules are reconciled.",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 10,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanySpecials() {
    int currentStars = _safeInt(_company['star_rating']);

    return Container(
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12), color: const Color(0xFF1A1A1A),
            child: const Text("COMPANY SPECIALS", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          if (_specials.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text("No records found.", style: TextStyle(color: Colors.white24))),
          ..._specials.map((special) {
            bool isUnlocked = currentStars >= _safeInt(special['star']);
            bool isPassive = special['is_passive'] ?? false;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF333333)))),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Column(
                      children: [
                        Icon(isUnlocked ? Icons.star : Icons.lock, color: isUnlocked ? Colors.amberAccent : Colors.white24, size: 14),
                        Text("${special['star']}", style: TextStyle(color: isUnlocked ? Colors.amberAccent : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(special['name'].toString(), style: TextStyle(color: isUnlocked ? neonGreen : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(special['effect'].toString(), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                      ],
                    ),
                  ),
                  if (isUnlocked && !isPassive)
                    ElevatedButton(
                      onPressed: () {}, // Backend execution logic goes here later
                      style: ElevatedButton.styleFrom(backgroundColor: matteBlack, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(50, 26)),
                      child: Text("${special['cost']} JP", style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                    )
                  else if (isUnlocked && isPassive)
                    const Text("PASSIVE", style: TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold))
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEventLogs() {
    // Dynamic event logs pulling from database[cite: 2]
    List<dynamic> filteredLogs = _logs.where((log) {
      if (_selectedLogTab == 0) return true; // MAIN
      if (_selectedLogTab == 1 && log['log_type'] == 'FUNDS') return true;
      if (_selectedLogTab == 2 && log['log_type'] == 'TRAINING') return true;
      if (_selectedLogTab == 3 && log['log_type'] == 'STAFF') return true;
      return false;
    }).toList();

    return Container(
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        children: [
          Container(
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                _buildLogTabButton("MAIN", 0),
                _buildLogTabButton("FUNDS", 1),
                _buildLogTabButton("TRAINING", 2),
                _buildLogTabButton("STAFF", 3),
              ],
            ),
          ),
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            child: filteredLogs.isEmpty
                ? const Center(child: Text("No records found.", style: TextStyle(color: Colors.white24)))
                : ListView.builder(
              itemCount: filteredLogs.length,
              itemBuilder: (context, index) {
                var log = filteredLogs[index];
                Color logColor = Colors.white70;
                if (log['log_type'] == 'FUNDS') logColor = Colors.greenAccent;
                if (log['log_type'] == 'STAFF') logColor = Colors.cyanAccent;
                if (log['log_type'] == 'TRAINING') logColor = Colors.amberAccent;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("[${_formatDate(log['created_at'])}] ", style: const TextStyle(color: Colors.white38, fontSize: 9)),
                      Expanded(child: Text(log['log_text'].toString(), style: TextStyle(color: logColor, fontSize: 10))),
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLogTabButton(String label, int index) {
    bool isSelected = _selectedLogTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedLogTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isSelected ? neonGreen : Colors.transparent, width: 2))),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: isSelected ? neonGreen : Colors.white54, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _buildAffiliationsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.handshake, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          const Text("SYNDICATE AFFILIATIONS", style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 8),
          const Text("Corporate protection and racketeering coming soon.", style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(backgroundColor: matteBlack, side: BorderSide(color: neonGreen.withOpacity(0.5))),
            child: Text("VIEW FACTIONS", style: TextStyle(color: neonGreen, fontSize: 11, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}