import 'package:flutter/material.dart';
import '../api_config.dart';
import '../services/game_http.dart' as http;
import 'dart:convert';

class CompanyManagementView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final int companyId;
  final VoidCallback? onBack;
  final VoidCallback? onSell;

  const CompanyManagementView({super.key, required this.userData, required this.companyId, this.onBack, this.onSell});

  @override
  State<CompanyManagementView> createState() => _CompanyManagementViewState();
}

class _CompanyManagementViewState extends State<CompanyManagementView> {
  String get apiUrl => '${ApiConfig.baseUrl}/companies';
  bool _isLoading = true;
  bool _isProcessing = false;

  Map<String, dynamic> _company = {};
  List<dynamic> _roster = [];
  List<dynamic> _positions = [];
  List<dynamic> _inventory = [];
  List<dynamic> _shipments = [];
  List<dynamic> _applicants = [];
  Map<String, dynamic> _cashFlow = {};
  Map<String, dynamic> _companyCatalog = {};

  final List<String> _manageOptions = [
    'Employees', 'Company Positions', 'Pricing',
    'Stock', 'Advertising', 'Funds', 'Upgrades',
    'Edit Company Profile', 'Change Director', 'Sell Company'
  ];
  String _selectedManageOption = 'Employees';

  // UI Controllers
  final TextEditingController _nameEditController = TextEditingController();
  final TextEditingController _imageEditController = TextEditingController();
  final TextEditingController _newDirectorController = TextEditingController();
  final TextEditingController _adBudgetController = TextEditingController();
  final TextEditingController _fundsAmountController = TextEditingController();

  Map<String, Map<String, dynamic>> _employeeEdits = {};
  Map<int, TextEditingController> _orderControllers = {};
  Map<int, TextEditingController> _priceControllers = {};
  Map<int, int> _dynamicOrderTotals = {};

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _fetchManagementData();
  }

  @override
  void dispose() {
    _nameEditController.dispose();
    _imageEditController.dispose();
    _newDirectorController.dispose();
    _adBudgetController.dispose();
    _fundsAmountController.dispose();
    for (var c in _orderControllers.values) { c.dispose(); }
    for (var c in _priceControllers.values) { c.dispose(); }
    super.dispose();
  }

  // ==========================================
  // API CALLS
  // ==========================================

  Future<void> _fetchManagementData() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/${widget.companyId}/dashboard/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _company = data['company'] ?? {};
            _roster = data['roster'] ?? [];
            _positions = data['positions'] ?? [];
            _inventory = data['inventory'] ?? [];
            _shipments = data['shipments'] ?? [];
            _applicants = data['applicants'] ?? [];
            _cashFlow = data['cash_flow'] is Map
                ? Map<String, dynamic>.from(data['cash_flow'])
                : <String, dynamic>{};
            _companyCatalog = data['company_catalog'] is Map
                ? Map<String, dynamic>.from(data['company_catalog'])
                : <String, dynamic>{};

            _nameEditController.text = _company['company_name'] ?? "";
            _imageEditController.text = _company['logo_url'] ?? "";
            _adBudgetController.text = _safeInt(_company['advertising_budget']).toString();

            // Setup dynamic item controllers
            for (var item in _inventory) {
              int id = item['item_id'];
              _orderControllers.putIfAbsent(id, () => TextEditingController());
              _priceControllers.putIfAbsent(id, () => TextEditingController(text: item['price_per_unit'].toString()));
              _dynamicOrderTotals.putIfAbsent(id, () => 0);
            }

            // BULLETPROOF KICK-OUT CHECK
            bool isDirector = (data['user_role']?.toString().trim().toLowerCase() == 'director') ||
                (_company['owner_id']?.toString() == widget.userData['user_id'].toString());

            if (!isDirector) {
              if (widget.onBack != null) widget.onBack!();
            }

            _isLoading = false;
          });
        }
      } else {
        if (mounted && widget.onBack != null) widget.onBack!();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAction(String endpoint, Map<String, dynamic> payload) async {
    setState(() => _isProcessing = true);
    try {
      final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/company-management/$endpoint'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"company_id": widget.companyId, ...payload})
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'], style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green));

        if (endpoint == 'sell-company' || endpoint == 'change-director') {
          if (widget.onSell != null) widget.onSell!();
        } else {
          _fundsAmountController.clear();
          for (var c in _orderControllers.values) { c.clear(); }
          _dynamicOrderTotals.clear();
          await _fetchManagementData();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'], style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Network Error.", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================
  String _formatDate(String isoString) {
    try {
      DateTime dt = DateTime.parse(isoString).toLocal();

      const List<String> months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];

      String month = months[dt.month - 1];
      String day = dt.day.toString().padLeft(2, '0');

      int hour = dt.hour;
      String period = hour >= 12 ? 'PM' : 'AM';

      if (hour == 0) hour = 12;
      if (hour > 12) hour -= 12;

      String hourStr = hour.toString().padLeft(2, '0');
      String minStr = dt.minute.toString().padLeft(2, '0');

      return "$month $day, $hourStr:$minStr $period";
    } catch (e) {
      return isoString; // Fallback if parsing fails
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

  // ==========================================
  // MODALS & DIALOGS
  // ==========================================

  void _showAssignCrewModal() async {
    // 1. Fetch available crew first
    List<dynamic> activeCrew = [];
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/company-management/${widget.companyId}/available-crew/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        activeCrew = jsonDecode(response.body)['crew'] ?? [];
      }
    } catch (e) {
      debugPrint("Fetch Crew Error: $e");
    }

    if (!mounted) return;

    // 2. Show the Modal (Matching the StreetsView style)
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
                    Expanded(child: Text("ASSIGN NPC CREW", style: TextStyle(color: neonGreen, fontSize: 14, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context))
                  ],
                ),
              ),
              if (activeCrew.isEmpty)
                const Expanded(child: Center(child: Text("YOU HAVE NO CREW MEMBERS.", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))))
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: activeCrew.length,
                    itemBuilder: (context, index) {
                      var npc = activeCrew[index];
                      bool isAssignedHere = npc['assignment'] == 'Company: ${widget.companyId}';
                      bool isAssignedElsewhere = npc['assignment'] != 'Idle' && !isAssignedHere;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          border: Border.all(color: isAssignedHere ? Colors.cyanAccent : const Color(0xFF333333)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(npc['npc_name'].toString().toUpperCase(), style: TextStyle(color: isAssignedHere ? Colors.cyanAccent : Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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
                                if (isAssignedHere) {
                                  _submitAction('recall-crew', {'crew_id': npc['crew_id']});
                                } else {
                                  _submitAction('assign-crew', {'crew_id': npc['crew_id']});
                                }
                                if (!context.mounted) return;
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isAssignedHere ? Colors.redAccent.withValues(alpha: 0.1) : neonGreen.withValues(alpha: 0.1),
                                side: BorderSide(color: isAssignedHere ? Colors.redAccent : neonGreen),
                              ),
                              child: Text(isAssignedHere ? "RECALL" : (isAssignedElsewhere ? "SWAP HERE" : "ASSIGN"), style: TextStyle(color: isAssignedHere ? Colors.redAccent : neonGreen, fontSize: 10, fontWeight: FontWeight.bold)),
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

  void _showApplicantsDialog() {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: matteBlack,
            title: Text("JOB APPLICANTS", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold, fontSize: 14)),
            content: SizedBox(
              width: double.maxFinite,
              child: _applicants.isEmpty
                  ? const Text("No pending applicants.", style: TextStyle(color: Colors.white54))
                  : ListView(
                shrinkWrap: true,
                children: _applicants.map((app) {
                  int acu = _safeInt(app['stat_acu']);
                  int ops = _safeInt(app['stat_ops']);
                  int pre = _safeInt(app['stat_pre']);
                  int res = _safeInt(app['stat_res']);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFF333333))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Level ${app['level']} - ${app['username']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        Text("Acu: $acu | Ops: $ops | Pre: $pre | Res: $res", style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
                        if (app['pitch_message'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('"${app['pitch_message']}"', style: const TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic)),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton(onPressed: () { Navigator.pop(context); _submitAction('manage-applicant', {'application_id': app['application_id'], 'target_user_id': app['user_id'], 'action': 'reject'}); }, style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: const BorderSide(color: Colors.redAccent)), child: const Text("REJECT", style: TextStyle(color: Colors.redAccent, fontSize: 10))),
                            const SizedBox(width: 8),
                            ElevatedButton(onPressed: () { Navigator.pop(context); _submitAction('manage-applicant', {'application_id': app['application_id'], 'target_user_id': app['user_id'], 'action': 'accept'}); }, style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: BorderSide(color: neonGreen)), child: Text("ACCEPT", style: TextStyle(color: neonGreen, fontSize: 10))),
                          ],
                        )
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE", style: TextStyle(color: Colors.white54)))],
          );
        }
    );
  }


  // ==========================================
  // MAIN BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: matteBlack, body: Center(child: CircularProgressIndicator(color: neonGreen)));

    return Scaffold(
      backgroundColor: matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: neonGreen),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack ?? () => Navigator.pop(context)),
        title: Text("MANAGE ENTERPRISE", style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                color: const Color(0xFF1A1A1A),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("ADMINISTRATION MODULE", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedManageOption,
                          isExpanded: true,
                          dropdownColor: matteBlack,
                          icon: Icon(Icons.arrow_drop_down, color: neonGreen),
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          items: _manageOptions.map((String option) => DropdownMenuItem<String>(value: option, child: Text(option))).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) setState(() => _selectedManageOption = newValue);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: Container(color: matteBlack, child: _buildManageContent())),
            ],
          ),
          if (_isProcessing) Container(color: Colors.black54, child: Center(child: CircularProgressIndicator(color: neonGreen)))
        ],
      ),
    );
  }

  Widget _buildManageContent() {
    switch (_selectedManageOption) {
      case 'Employees': return _buildEmployeesView();
      case 'Company Positions': return _buildPositionsView();
      case 'Pricing': return _buildPricingView();
      case 'Stock': return _buildStockView();
      case 'Advertising': return _buildAdvertisingView();
      case 'Funds': return _buildFundsView();
      case 'Upgrades': return _buildUpgradesView();
      case 'Edit Company Profile': return _buildEditProfileView();
      case 'Change Director': return _buildChangeDirectorView();
      case 'Sell Company': return _buildSellCompanyView();
      default: return const Center(child: Text("Under Construction", style: TextStyle(color: Colors.white54)));
    }
  }

  // --- 1. EMPLOYEES & APPLICANTS ---
  Widget _buildEmployeesView() {
    int maxEmps = _safeInt(_company['max_employees'], fallback: 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.07),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text(
            "EMPLOYEE MANAGEMENT PAUSED\n\nPosition definitions are now source-normalized, but salary negotiation, training settlement, NPC assignment, firing consequences, and contract acceptance are not fully reconciled. Roster data remains visible; mutations stay disabled.",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 10,
              height: 1.45,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "PERSONNEL ROSTER (${_roster.length} / $maxEmps)",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: _showApplicantsDialog,
              child: Text(
                "APPLICANTS (${_applicants.length})",
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._roster.map((emp) {
          final empName = (emp['username'] ?? "NPC Worker").toString();
          final isNpc = emp['is_npc'] == true;
          final pos = (emp['position_role'] ?? 'Unassigned').toString();
          final salary = _safeInt(emp['daily_salary']);
          final acu = _safeInt(emp['stat_acu']);
          final pre = _safeInt(emp['stat_pre']);
          final ops = _safeInt(emp['stat_ops']);
          final res = _safeInt(emp['stat_res']);

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: darkSurface,
              border: Border.all(color: const Color(0xFF333333)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        empName,
                        style: TextStyle(
                          color: neonGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      isNpc ? "NPC" : "PLAYER",
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Position: $pos",
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                Text(
                  isNpc ? "Salary: \$0 (design reference)" : "Recorded salary: \$${_formatNumber(salary)} Clean Cash",
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
                const SizedBox(height: 5),
                Text(
                  "Stats: ACU $acu | PRE $pre | OPS $ops | RES $res",
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // --- 2. POSITIONS (SOURCE-NORMALIZED) ---
  Widget _buildPositionsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "SOURCE-NORMALIZED POSITIONS",
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Requirements and Working Stat gains come directly from the recovered company spreadsheet. Assignment/training remains paused.",
          style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.4),
        ),
        const SizedBox(height: 16),
        ..._positions.map((pos) {
          final pStat = (pos['req_stat_primary'] ?? '').toString().toUpperCase();
          final sStat = (pos['req_stat_secondary'] ?? '').toString().toUpperCase();
          final pReq = _safeInt(pos['req_amount_primary']);
          final sReq = _safeInt(pos['req_amount_secondary']);
          final pGain = _safeInt(pos['gain_primary']);
          final sGain = _safeInt(pos['gain_secondary']);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: darkSurface,
              border: Border.all(color: const Color(0xFF333333)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pos['name'].toString().replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: neonGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  "Requires: $pStat ${_formatNumber(pReq)} + $sStat ${_formatNumber(sReq)}",
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                Text(
                  "Source gain values: +$pGain $pStat / +$sGain $sStat",
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 10),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // --- 3. PRICING ---
  Widget _buildPricingView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "PRODUCT PRICING",
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.07),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            "PRICING PAUSED\n\nThe recovered 120-company supply-chain source uses a broader product generation than the legacy 20-row normalized product table. Pricing cannot be authoritative until those product generations are reconciled.",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 10,
              height: 1.45,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // --- 4. STOCK & SHIPMENTS (Dynamic Input Products) ---
  Widget _buildStockView() {
    var inputProducts = _inventory.where((p) => p['is_input'] == true).toList();
    int maxCap = _safeInt(_company['base_warehouse_max']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("INVENTORY MANAGEMENT", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("STOCK ORDERING PAUSED: supplier contracts, system markup, delivery timing, and authoritative product blueprints are not yet reconciled.", style: TextStyle(color: Colors.amber, fontSize: 10, fontStyle: FontStyle.italic, height: 1.4)),
        const SizedBox(height: 16),

        if (inputProducts.isEmpty)
          const Text("This company does not require raw material inputs.", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),

        ...inputProducts.map((prod) {
          int id = prod['item_id'];
          int inStock = _safeInt(prod['quantity']);
          int cost = _safeInt(prod['price_per_unit'], fallback: 2500);
          int orderTotal = _dynamicOrderTotals[id] ?? 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prod['item_name'].toString().toUpperCase(), style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                const Divider(color: Color(0xFF333333), height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("In Stock:", style: TextStyle(color: Colors.white54, fontSize: 11)), Text("${_formatNumber(inStock)} / ${_formatNumber(maxCap)}", style: TextStyle(color: neonGreen, fontSize: 11, fontWeight: FontWeight.bold))]),
                const SizedBox(height: 4),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Recorded Unit Price:", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text("\$${_formatNumber(cost)}", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))
                    ]
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _orderControllers[id],
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: "Order Quantity", hintText: "0"),
                  onChanged: (val) {
                    setState(() => _dynamicOrderTotals[id] = (int.tryParse(val) ?? 0) * cost);
                  },
                ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("TOTAL COST:", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text("\$${_formatNumber(orderTotal)} Dirty Cash", style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 40,
                  child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.1), side: BorderSide(color: neonGreen)),
                      child: const Text("ORDERING PAUSED", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold))
                  ),
                )
              ],
            ),
          );
        }),

        const SizedBox(height: 24),
        const Text("INCOMING SHIPMENTS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_shipments.isEmpty)
          const Text("No active shipments.", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
        ..._shipments.map((ship) {
          String formattedArrival = _formatDate(ship['arrival_date'].toString());

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${ship['quantity']}x ${ship['item_name']}", style: TextStyle(color: neonGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text("-\$${_formatNumber(ship['total_cost'])}", style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text("Arrival: $formattedArrival", style: const TextStyle(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        })
      ],
    );
  }

  // --- 5. ADVERTISING ---
  Widget _buildAdvertisingView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "MARKETING & ADVERTISING",
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.07),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            "ADVERTISING SETTLEMENT PAUSED\n\nThe old client claimed a 40% competition-based efficiency cap and daily Dirty Cash spend, but those formulas and the daily settlement worker are not source-reconciled. The stored budget is shown for reference only.",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 10,
              height: 1.45,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Recorded daily budget: \$${_formatNumber(_company['advertising_budget'])}",
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  // --- 6. COMPANY CASH FUNDING ---
  Widget _buildFundsView() {
    final dirtyFundingAvailable =
        _cashFlow['owner_dirty_funding_available'] == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "CORPORATE VAULT",
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                const Text(
                  "Dirty Cash",
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
                Text(
                  "\$${_formatNumber(_company['bank_dirty'])}",
                  style: TextStyle(
                    color: neonGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Column(
              children: [
                const Text(
                  "Clean Cash",
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
                Text(
                  "\$${_formatNumber(_company['bank_clean'])}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        const Divider(color: Color(0xFF333333), height: 32),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.07),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text(
            "SOURCE-RECONCILED FUNDING ONLY\n\nThe owner may commit Dirty Cash to the company bank. This does not convert it to Clean Cash. Clean deposits, withdrawals, payroll conversion, sales settlement, laundering tax, and bankruptcy distribution are paused.",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 10,
              height: 1.45,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _fundsAmountController,
          enabled: dirtyFundingAvailable && !_isProcessing,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixText: "\$ ",
            labelText: "Dirty Cash Amount",
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton(
            onPressed: dirtyFundingAvailable && !_isProcessing
                ? () => _submitAction(
                      'funds',
                      {
                        'amount': _fundsAmountController.text,
                        'action_type': 'deposit',
                        'currency_type': 'dirty',
                      },
                    )
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: neonGreen.withValues(alpha: 0.1),
              side: BorderSide(color: neonGreen),
            ),
            child: Text(
              dirtyFundingAvailable
                  ? "COMMIT DIRTY CASH TO COMPANY BANK"
                  : "FUNDING PAUSED",
              style: TextStyle(
                color: dirtyFundingAvailable ? neonGreen : Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "Company withdrawals are intentionally disabled until settlement provenance and laundering rules are canonical.",
          style: TextStyle(
            color: Colors.white38,
            fontSize: 9,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  // --- 7. UPGRADES ---
  Widget _buildUpgradesView() {
    final rawUpgrade = _companyCatalog['upgrade'];
    final upgrade = rawUpgrade is Map
        ? Map<String, dynamic>.from(rawUpgrade)
        : <String, dynamic>{};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "COMPANY UPGRADE SOURCE",
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (upgrade.isNotEmpty) ...[
          _buildInfoRow(
            "Upgrade",
            (upgrade['upgrade_key'] ?? 'unknown')
                .toString()
                .replaceAll('_', ' ')
                .toUpperCase(),
          ),
          _buildInfoRow(
            "Source cost",
            "\$${_formatNumber(upgrade['cost'])}",
          ),
          _buildInfoRow(
            "Upkeep increase",
            "\$${_formatNumber(upgrade['upkeep_increase'])} / day",
          ),
          _buildInfoRow(
            "Bonus source value",
            "${upgrade['bonus_key']}: ${upgrade['bonus_value']}",
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.07),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            "PURCHASE PAUSED\n\nUpgrade cost and upkeep are source-normalized. The bonus key/value is preserved exactly but its runtime semantics, stacking, settlement, and effect consumer are not yet reconciled.",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 10,
              height: 1.45,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 8. EDIT PROFILE ---
  Widget _buildEditProfileView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("COMPANY PROFILE", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextFormField(controller: _nameEditController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Company Name")),
        const SizedBox(height: 12),
        TextFormField(controller: _imageEditController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Logo URL (Optional)")),
        const SizedBox(height: 16),
        SizedBox(
            width: double.infinity, height: 40,
            child: ElevatedButton(
                onPressed: () => _submitAction('update-profile', {'company_name': _nameEditController.text, 'logo_url': _imageEditController.text}),
                style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: BorderSide(color: neonGreen)),
                child: Text("SAVE CHANGES", style: TextStyle(color: neonGreen))
            )
        ),
      ],
    );
  }

  // --- 9. CHANGE DIRECTOR ---
  Widget _buildChangeDirectorView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("TRANSFER OWNERSHIP", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("WARNING: You will lose ownership and become an Unassigned employee. The new director MUST already be an Unassigned employee in this company.", style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.4)),
        const SizedBox(height: 16),
        TextFormField(controller: _newDirectorController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "New Director (Username)")),
        const SizedBox(height: 16),
        SizedBox(
            width: double.infinity, height: 40,
            child: ElevatedButton(
                onPressed: () => _submitAction('change-director', {'new_director_username': _newDirectorController.text}),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.redAccent)),
                child: const Text("TRANSFER DIRECTORSHIP", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
            )
        ),
      ],
    );
  }

  // --- 10. SELL COMPANY ---
  Widget _buildSellCompanyView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "COMPANY LIQUIDATION",
          style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.06),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            "LIQUIDATION PAUSED\n\nThe legacy 75% setup/upgrade refund, 5% lifetime-revenue return, vault distribution, employee severance, and bankruptcy settlement are not source-reconciled. No liquidation payout is currently calculated or displayed.",
            style: TextStyle(color: Colors.redAccent, fontSize: 10, height: 1.5, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}