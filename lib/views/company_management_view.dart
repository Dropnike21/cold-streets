import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  final String apiUrl = "http://10.0.2.2:3000/companies";
  bool _isLoading = true;
  bool _isProcessing = false;

  Map<String, dynamic> _company = {};
  List<dynamic> _roster = [];
  List<dynamic> _positions = [];
  List<dynamic> _inventory = [];
  List<dynamic> _shipments = [];
  List<dynamic> _applicants = [];

  final List<String> _manageOptions = [
    'Employees', 'Company Positions', 'Pricing',
    'Stock', 'Advertising', 'Funds', 'Upgrades',
    'Edit Company Profile', 'Change Director', 'Sell Company'
  ];
  String _selectedManageOption = 'Employees';

  // UI Controllers
  String _fundsCurrency = 'dirty';
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
          Uri.parse('$apiUrl/$endpoint'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"company_id": widget.companyId, "user_id": widget.userData['user_id'], ...payload})
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
      final response = await http.get(Uri.parse('$apiUrl/${widget.companyId}/available-crew/${widget.userData['user_id']}'));
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
    int maxEmps = _safeInt(_company['max_employees'], fallback: 4);
    var manageableRoster = _roster.where((emp) => emp['position_role'] != 'Director').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: ElevatedButton(
                onPressed: () => _showAssignCrewModal(),
                style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: const BorderSide(color: Colors.cyanAccent)),
                child: const Text("MANAGE NPC CREW", style: TextStyle(color: Colors.cyanAccent, fontSize: 10))
            )),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(
                onPressed: () => _showApplicantsDialog(),
                style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: const BorderSide(color: Colors.amberAccent)),
                child: Text("VIEW APPLICANTS (${_applicants.length})", style: const TextStyle(color: Colors.amberAccent, fontSize: 10))
            )),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("PERSONNEL ROSTER (${_roster.length} / $maxEmps)", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.2), side: BorderSide(color: neonGreen), minimumSize: const Size(80, 30)),
              child: Text("TRAIN ALL", style: TextStyle(color: neonGreen, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        const SizedBox(height: 12),
        ...manageableRoster.map((emp) {
          String empName = (emp['username'] ?? "NPC_Worker").toString();
          int employeeId = _safeInt(emp['employee_id']);
          bool isNpc = emp['is_npc'] ?? false;
          int eff = _safeInt(emp['effectiveness_score']);
          int days = _safeInt(emp['days_employed']);
          int salary = _safeInt(emp['daily_salary']);
          int acu = _safeInt(emp['stat_acu']);
          int pre = _safeInt(emp['stat_pre']);
          int ops = _safeInt(emp['stat_ops']);
          int res = _safeInt(emp['stat_res']);
          String pos = (emp['position_role'] ?? 'Unassigned').toString();
          bool isDirector = pos == 'Director';

          _employeeEdits.putIfAbsent(empName, () => {'salary': salary, 'position': pos});

          List<String> dropDownOptions = _positions.map((e) => e['name'] as String).toList();
          if (!dropDownOptions.contains('Unassigned')) dropDownOptions.add('Unassigned');
          if (!dropDownOptions.contains('Director')) dropDownOptions.add('Director');

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(empName, style: TextStyle(color: neonGreen, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text("$days Days Old", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text("Eff: ", style: TextStyle(color: Colors.white70, fontSize: 10)),
                    Expanded(child: LinearProgressIndicator(value: eff / 100, backgroundColor: Colors.black, color: Colors.cyanAccent, minHeight: 6)),
                    const SizedBox(width: 8),
                    Text("$eff%", style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text("Stats: Acu $acu | Pre $pre | Ops $ops | Res $res", style: const TextStyle(color: Colors.white38, fontSize: 9)),
                const Divider(color: Color(0xFF333333), height: 16),

                if (!isDirector) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: dropDownOptions.contains(pos) ? pos : 'Unassigned',
                          dropdownColor: matteBlack,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder(), labelText: "Position", labelStyle: TextStyle(color: Colors.white54, fontSize: 10)),
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                          items: dropDownOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (val) => _employeeEdits[empName]!['position'] = val,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: salary.toString(),
                          keyboardType: TextInputType.number,
                          enabled: !isNpc, // NPCs don't get a salary
                          style: TextStyle(color: isNpc ? Colors.white24 : Colors.greenAccent, fontSize: 11),
                          decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.all(8), border: const OutlineInputBorder(), labelText: isNpc ? "NPCs work free" : "Salary (\$)", labelStyle: const TextStyle(color: Colors.white54, fontSize: 10)),
                          onChanged: (val) => _employeeEdits[empName]!['salary'] = int.tryParse(val) ?? 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(onPressed: () => _submitAction('manage-employee', {'employee_id': employeeId, 'is_npc': isNpc, 'target_username': empName, 'action_type': 'update', 'new_position': _employeeEdits[empName]!['position'], 'new_salary': _employeeEdits[empName]!['salary']}), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.blueAccent)), child: const Text("SAVE", style: TextStyle(color: Colors.blueAccent, fontSize: 10))),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: () => _submitAction('manage-employee', {'employee_id': employeeId, 'is_npc': isNpc, 'target_username': empName, 'action_type': 'train'}), style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.withValues(alpha: 0.1), side: const BorderSide(color: Colors.amber)), child: const Text("TRAIN", style: TextStyle(color: Colors.amber, fontSize: 10))),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: () => _submitAction('manage-employee', {'employee_id': employeeId, 'is_npc': isNpc, 'target_username': empName, 'action_type': 'fire'}), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.redAccent)), child: const Text("FIRE", style: TextStyle(color: Colors.redAccent, fontSize: 10))),
                    ],
                  )
                ] else ...[
                  const Text("The Director cannot be trained, fired, or re-assigned.", style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic))
                ]
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  // --- 2. POSITIONS (Dynamic Database List) ---
  Widget _buildPositionsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("ROLE ASSIGNMENTS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("Tap or long-press a position to view its responsibilities.", style: TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 16),
        ..._positions.where((p) => p['name'] != 'Director').map((pos) => Tooltip(
          message: pos['description'] ?? 'No description provided.',
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 4),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(pos['name'].toString(), style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Req: ${pos['req_stat_primary']}", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    Text("Gain: ${pos['stat_gain_desc']}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
                  ],
                )),
                const Icon(Icons.info_outline, color: Colors.white24, size: 16)
              ],
            ),
          ),
        )),
      ],
    );
  }

  // --- 3. PRICING (Dynamic Output Products) ---
  Widget _buildPricingView() {
    var outputProducts = _inventory.where((p) => p['is_input'] == false).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("MARKET PRICING", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        if (outputProducts.isEmpty)
          const Text("This company does not produce sellable goods.", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),

        ...outputProducts.map((prod) {
          int id = prod['item_id'];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
            child: Row(
              children: [
                Expanded(child: Text(prod['item_name'], style: const TextStyle(color: Colors.white, fontSize: 12))),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _priceControllers[id],
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                    decoration: const InputDecoration(isDense: true, prefixText: "\$ ", prefixStyle: TextStyle(color: Colors.greenAccent), border: OutlineInputBorder(), labelText: "Price / Unit"),
                  ),
                )
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        if (outputProducts.isNotEmpty)
          SizedBox(
            width: double.infinity, height: 40,
            child: ElevatedButton(
                onPressed: () {
                  for(var p in outputProducts) {
                    _submitAction('update-pricing', {'item_id': p['item_id'], 'product_price': _priceControllers[p['item_id']]!.text});
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.1), side: BorderSide(color: neonGreen)),
                child: Text("UPDATE PRICES", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold))
            ),
          )
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
        const Text("WARNING: External stock shipments suffer a 1-day delivery delay.", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontStyle: FontStyle.italic)),
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
                      const Text("System Price (+20%):", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text("\$${_formatNumber(cost * 1.20)}", style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold))
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
                      onPressed: orderTotal > 0 ? () => _submitAction('order-stock', {'item_id': id, 'order_quantity': _orderControllers[id]!.text, 'total_cost': orderTotal}) : null,
                      style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.1), side: BorderSide(color: neonGreen)),
                      child: Text("PLACE ORDER", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold))
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
        const Text("MARKETING & ADVERTISING", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("Set a daily budget to attract customers. Advertising has a base cap of 40% efficiency. This cap decays based on competition from other companies of the same type. The highest budget secures the 40% bonus, with diminishing returns for lower budgets.", style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.4)),
        const SizedBox(height: 16),
        TextFormField(
          controller: _adBudgetController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
          decoration: const InputDecoration(border: OutlineInputBorder(), prefixText: "\$ ", labelText: "Daily Ad Budget (Dirty Cash)"),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, height: 40,
          child: ElevatedButton(
              onPressed: () => _submitAction('update-advertising', {'ad_budget': _adBudgetController.text}),
              style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.1), side: BorderSide(color: neonGreen)),
              child: Text("SET BUDGET", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold))
          ),
        )
      ],
    );
  }

  // --- 6. FUNDS (Radio Buttons) ---
  Widget _buildFundsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("CORPORATE VAULT", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                const Text("Dirty Cash", style: TextStyle(color: Colors.white54, fontSize: 10)),
                Text("\$${_formatNumber(_company['bank_dirty'])}", style: TextStyle(color: neonGreen, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            Column(
              children: [
                const Text("Clean Cash", style: TextStyle(color: Colors.white54, fontSize: 10)),
                Text("\$${_formatNumber(_company['bank_clean'])}", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        const Divider(color: Color(0xFF333333), height: 32),

        // Currency Selector
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: Text("Dirty Cash", style: TextStyle(color: neonGreen, fontSize: 11)),
                value: 'dirty',
                groupValue: _fundsCurrency,
                activeColor: neonGreen,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _fundsCurrency = val!),
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: const Text("Clean Cash", style: TextStyle(color: Colors.white, fontSize: 11)),
                value: 'clean',
                groupValue: _fundsCurrency,
                activeColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _fundsCurrency = val!),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        TextFormField(
          controller: _fundsAmountController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(border: OutlineInputBorder(), prefixText: "\$ ", labelText: "Amount"),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: ElevatedButton(
                onPressed: () => _submitAction('funds', {'amount': _fundsAmountController.text, 'action_type': 'deposit', 'currency_type': _fundsCurrency}),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.greenAccent)),
                child: const Text("DEPOSIT", style: TextStyle(color: Colors.greenAccent))
            )),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(
                onPressed: () => _submitAction('funds', {'amount': _fundsAmountController.text, 'action_type': 'withdraw', 'currency_type': _fundsCurrency}),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.redAccent)),
                child: const Text("WITHDRAW", style: TextStyle(color: Colors.redAccent))
            )),
          ],
        )
      ],
    );
  }

  // --- 7. UPGRADES (Dynamic Progress Bars) ---
  Widget _buildUpgradesView() {
    int setupCost = _safeInt(_company['setup_cost'], fallback: 2500000);
    int dirtyCash = _safeInt(_company['bank_dirty']);

    int curSize = _safeInt(_company['size_upgrade_level'], fallback: 0);
    int curStaff = _safeInt(_company['staff_room_level'], fallback: 0);
    int curWare = _safeInt(_company['warehouse_level'], fallback: 0);
    bool hasWarehouse = _safeInt(_company['base_warehouse_max'], fallback: 100) > 0;

    int maxLevel = 8;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("COMPANY UPGRADES", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("Upgrades are purchased using Corporate Dirty Cash.", style: TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic)),
        const SizedBox(height: 16),

        _buildUpgradeCard("Company Size", "Increases max employees by 25%. Costs ${10 + (curSize*10)}% of base startup cost.", (setupCost * (0.10 + (curSize*0.10))).toInt(), dirtyCash, 'size', curSize, maxLevel),
        _buildUpgradeCard("Staff Room", "Helps maintain 100% environment.", (setupCost * (0.05 + (curStaff*0.05))).toInt(), dirtyCash, 'staff', curStaff, maxLevel),

        if (hasWarehouse)
          _buildUpgradeCard("Warehouse Space", "Expands input/output capacity.", (setupCost * (0.15 + (curWare*0.15))).toInt(), dirtyCash, 'warehouse', curWare, maxLevel)
        else
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("This industry does not utilize a warehouse.", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }

  Widget _buildUpgradeCard(String title, String desc, int cost, int dirtyCash, String type, int currentLevel, int maxLevel) {
    bool canAfford = dirtyCash >= cost;
    bool isMaxed = currentLevel >= maxLevel;

    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                    const SizedBox(height: 4),
                    if (!isMaxed)
                      Text("Cost: \$${_formatNumber(cost)}", style: TextStyle(color: canAfford ? Colors.white : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold))
                    else
                      const Text("MAXIMUM LEVEL REACHED", style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (!isMaxed)
                ElevatedButton(
                    onPressed: canAfford ? () => _submitAction('buy-upgrade', {'upgrade_type': type, 'cost': cost}) : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.withValues(alpha: 0.1), side: const BorderSide(color: Colors.amber)),
                    child: const Text("BUY", style: TextStyle(color: Colors.amber))
                )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(maxLevel, (index) {
              bool isUnlocked = index < currentLevel;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                      color: isUnlocked ? neonGreen : Colors.black,
                      border: Border.all(color: isUnlocked ? neonGreen : const Color(0xFF333333)),
                      borderRadius: BorderRadius.circular(2)
                  ),
                ),
              );
            }),
          )
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
        const Text("LIQUIDATE ASSETS", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        const Text("Selling your company to the system permanently destroys it. All employees will be fired.\n\nReturns:\n• 75% of initial cost\n• 75% of all upgrades\n• 5% of lifetime revenue\n• 100% of current vault funds", style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.5)),
        const SizedBox(height: 32),
        SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
                onPressed: () => _submitAction('sell-company', {}),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.2), side: const BorderSide(color: Colors.redAccent, width: 2)),
                child: const Text("SELL COMPANY", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2))
            )
        ),
      ],
    );
  }
}