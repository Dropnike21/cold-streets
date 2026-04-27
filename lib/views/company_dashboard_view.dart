import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'company_management_view.dart';

class CompanyDashboardView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final int companyId;
  final VoidCallback? onBack;

  const CompanyDashboardView({super.key, required this.userData, required this.companyId, this.onBack});

  @override
  State<CompanyDashboardView> createState() => _CompanyDashboardViewState();
}

class _CompanyDashboardViewState extends State<CompanyDashboardView> {
  final String apiUrl = "http://10.0.2.2:3000/companies";
  bool _isLoading = true;

  Map<String, dynamic> _company = {};
  List<dynamic> _roster = [];
  String _userRole = "Employee";
  int _userSalary = 0;

  int _selectedLogTab = 0;
  String _chartFilter = 'All Time';

  final List<Map<String, dynamic>> _companySpecials = [
    {"star": 1, "name": "Free Samples", "effect": "Gain 1x Random Item", "cost": 5, "is_passive": false},
    {"star": 3, "name": "Overtime", "effect": "Trade points for Clean Cash", "cost": 10, "is_passive": false},
    {"star": 5, "name": "Insider Info", "effect": "Boosts Crime Success Rate by 5%", "cost": 0, "is_passive": true},
    {"star": 7, "name": "Tax Fraud", "effect": "Launder \$10,000 Dirty Cash instantly", "cost": 25, "is_passive": false},
    {"star": 10, "name": "The Kingpin", "effect": "+10% Max Nerve permanently", "cost": 0, "is_passive": true},
  ];

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _fetchDashboard();
  }

  Future<void> _fetchDashboard() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/${widget.companyId}/dashboard/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _company = data['company'] ?? {};
            _roster = data['roster'] ?? [];
            _userRole = data['user_role'] ?? 'Employee';

            final myData = _roster.firstWhere((emp) => emp['username'] == widget.userData['username'], orElse: () => <String, dynamic>{});
            _userSalary = myData.isNotEmpty ? (myData['daily_salary'] as int? ?? 0) : 0;

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

  String _formatNumber(dynamic amount) {
    int val = amount is int ? amount : int.tryParse(amount.toString()) ?? 0;
    return val.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  int _safeInt(dynamic val, {int fallback = 0}) {
    if (val == null) return fallback;
    if (val is int) return val;
    return int.tryParse(val.toString()) ?? fallback;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: matteBlack, body: Center(child: CircularProgressIndicator(color: neonGreen)));

    String headerName = (_company['company_name'] ?? "ENTERPRISE").toString().toUpperCase();

    return DefaultTabController(
      length: 2, // Only 2 tabs for public view
      child: Scaffold(
        backgroundColor: matteBlack,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: neonGreen),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack ?? () => Navigator.pop(context)),
          title: Text(headerName, style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
          actions: [
            // --- THE DIRECTOR'S SETTINGS GEAR ---
            if (_userRole == 'Director')
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.cyanAccent),
                tooltip: "Manage Enterprise",
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CompanyManagementView(userData: widget.userData, companyId: widget.companyId))
                  ).then((_) => _fetchDashboard()); // Refresh state when closing management screen
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
          const SizedBox(height: 16),
          _buildCompanyDetailsGrid(),
          const SizedBox(height: 16),
          _buildPersonalDetails(),
          const SizedBox(height: 16),
          // --- INCOME CHART MOVED HERE ---
          _buildIncomeChartView(),
          const SizedBox(height: 16),
          _buildCompanySpecials(),
          const SizedBox(height: 16),
          _buildEventLogs(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCompanyHeader() {
    int pop = _safeInt(_company['popularity'], fallback: 65);
    int eff = _safeInt(_company['efficiency'], fallback: 82);
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

  Widget _buildCompanyDetailsGrid() {
    int dailyInc = _safeInt(_company['daily_income'], fallback: 67481250);
    int weeklyInc = _safeInt(_company['weekly_income'], fallback: 462605700);
    int dailyCust = _safeInt(_company['daily_customers'], fallback: 3);
    int weeklyCust = _safeInt(_company['weekly_customers'], fallback: 22);
    int age = _safeInt(_company['age_days'], fallback: 14);
    int trains = _safeInt(_company['trains_available'], fallback: 0);
    int maxTrains = 20;
    int stars = _safeInt(_company['star_rating'], fallback: 0);
    int maxEmps = _safeInt(_company['max_employees'], fallback: 4);

    String industryStr = (_company['industry_type'] ?? "Unknown").toString();
    String director = "Unknown";
    try {
      final dirData = _roster.firstWhere((e) => e['position_role'] == 'Director');
      director = (dirData['username'] ?? "Unknown").toString();
    } catch (e) {}

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
                    _buildCompactDetail("Type:", industryStr),
                    _buildCompactDetail("Director:", director),
                    _buildCompactDetail("Employees:", "${_roster.length} / $maxEmps"),
                    const SizedBox(height: 6),
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
                    _buildCompactDetail("Daily Income:", "\$${_formatNumber(dailyInc)}", valColor: Colors.greenAccent),
                    _buildCompactDetail("Daily Cust.:", _formatNumber(dailyCust)),
                    const SizedBox(height: 6),
                    _buildCompactDetail("Weekly Income:", "\$${_formatNumber(weeklyInc)}", valColor: Colors.greenAccent),
                    _buildCompactDetail("Weekly Cust.:", _formatNumber(weeklyCust)),
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
                    _buildCompactDetail("Trains:", "$trains / $maxTrains"),
                    const SizedBox(height: 6),
                    const Text("Rating:", style: TextStyle(color: Colors.white54, fontSize: 9)),
                    Row(
                      children: [
                        Icon(stars > 0 ? Icons.star : Icons.star_border, color: Colors.amberAccent, size: 12),
                        const SizedBox(width: 4),
                        Text("$stars / 10", style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
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
                    _buildCompactDetail("Daily Salary:", "\$${_formatNumber(_userSalary)}", valColor: Colors.white),
                    const SizedBox(height: 6),
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
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("REVENUE HISTORY", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: _chartFilter,
                dropdownColor: matteBlack,
                style: TextStyle(color: neonGreen, fontSize: 10, fontWeight: FontWeight.bold),
                underline: const SizedBox(),
                items: ['1 Month', '1 Year', 'All Time'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                onChanged: (val) => setState(() => _chartFilter = val!),
              )
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 150, width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: matteBlack, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                double heightRatio = (index + 1) * 0.12 + 0.1;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(width: 20, height: 110 * heightRatio, color: Colors.greenAccent.withValues(alpha: 0.8)),
                    const SizedBox(height: 4),
                    Text("Day ${index+1}", style: const TextStyle(color: Colors.white38, fontSize: 8)),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanySpecials() {
    int currentStars = _safeInt(_company['star_rating'], fallback: 0);

    return Container(
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12), color: const Color(0xFF1A1A1A),
            child: const Text("COMPANY SPECIALS", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          ..._companySpecials.map((special) {
            int reqStars = special['star'] as int;
            bool isUnlocked = currentStars >= reqStars;
            bool isPassive = special['is_passive'] as bool;

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
                        Text("$reqStars", style: TextStyle(color: isUnlocked ? Colors.amberAccent : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(special['name'].toString(), style: TextStyle(color: isUnlocked ? (isPassive ? Colors.cyanAccent : neonGreen) : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(special['effect'].toString(), style: TextStyle(color: isUnlocked ? Colors.white70 : Colors.white38, fontSize: 10)),
                      ],
                    ),
                  ),
                  if (isUnlocked && !isPassive)
                    ElevatedButton(
                      onPressed: () {},
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
            child: ListView(
              children: [
                _buildLogItem("2026-10-24 14:02", "Company incorporated by ${_roster.isNotEmpty ? _roster[0]['username'] : 'Director'}."),
                if (_selectedLogTab == 0 || _selectedLogTab == 1)
                  _buildLogItem("2026-10-25 00:00", "Daily income of \$67,481,250 deposited to Bank (Clean).", color: Colors.greenAccent),
                if (_selectedLogTab == 0 || _selectedLogTab == 3)
                  _buildLogItem("2026-10-25 09:15", "New employee hired: StreetThug99.", color: Colors.cyanAccent),
                if (_selectedLogTab == 0 || _selectedLogTab == 2)
                  _buildLogItem("2026-10-26 11:30", "Director trained StreetThug99. Effectiveness increased.", color: Colors.amberAccent),
              ],
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

  Widget _buildLogItem(String timestamp, String message, {Color color = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("[$timestamp] ", style: const TextStyle(color: Colors.white38, fontSize: 9)),
          Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 10))),
        ],
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
            style: ElevatedButton.styleFrom(backgroundColor: matteBlack, side: BorderSide(color: neonGreen.withValues(alpha: 0.5))),
            child: Text("VIEW FACTIONS", style: TextStyle(color: neonGreen, fontSize: 11, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}