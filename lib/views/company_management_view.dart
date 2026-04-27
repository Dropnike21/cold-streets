import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CompanyManagementView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final int companyId;

  const CompanyManagementView({super.key, required this.userData, required this.companyId});

  @override
  State<CompanyManagementView> createState() => _CompanyManagementViewState();
}

class _CompanyManagementViewState extends State<CompanyManagementView> {
  final String apiUrl = "http://10.0.2.2:3000/companies";
  bool _isLoading = true;

  Map<String, dynamic> _company = {};
  List<dynamic> _roster = [];

  final List<String> _manageOptions = [
    'Employees', 'Company Positions', 'Pricing',
    'Stock', 'Advertising', 'Funds', 'Upgrades',
    'Edit Company Profile', 'Change Director', 'Sell Company'
  ];
  String _selectedManageOption = 'Employees';

  final TextEditingController _stockOrderController = TextEditingController();
  int _orderTotal = 0;
  final int _unitCost = 2500;

  final TextEditingController _nameEditController = TextEditingController();
  final TextEditingController _imageEditController = TextEditingController();
  final TextEditingController _newDirectorController = TextEditingController();
  final TextEditingController _adBudgetController = TextEditingController();

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  final List<String> _availablePositions = ['Director', 'Manager', 'Marketer', 'Worker', 'Unassigned'];

  @override
  void initState() {
    super.initState();
    _fetchManagementData();
  }

  @override
  void dispose() {
    _stockOrderController.dispose();
    _nameEditController.dispose();
    _imageEditController.dispose();
    _newDirectorController.dispose();
    _adBudgetController.dispose();
    super.dispose();
  }

  Future<void> _fetchManagementData() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/${widget.companyId}/dashboard/${widget.userData['user_id']}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _company = data['company'] ?? {};
            _roster = data['roster'] ?? [];

            // Double check security: Kick them out if somehow they aren't the director
            if (data['user_role'] != 'Director') {
              Navigator.pop(context);
            }

            _isLoading = false;
          });
        }
      } else {
        if (mounted) Navigator.pop(context);
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

    return Scaffold(
      backgroundColor: matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: neonGreen),
        title: Text("MANAGE ENTERPRISE", style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
      ),
      body: Column(
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

          Expanded(
            child: Container(
              color: matteBlack,
              child: _buildManageContent(),
            ),
          ),
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

  Widget _buildEmployeesView() {
    int maxEmployees = _safeInt(_company['max_employees'], fallback: 4);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("PERSONNEL ROSTER", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.2), side: BorderSide(color: neonGreen), minimumSize: const Size(80, 30)),
              child: Text("TRAIN ALL", style: TextStyle(color: neonGreen, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        const SizedBox(height: 12),
        ..._roster.map((emp) {
          String empName = (emp['username'] ?? "Unknown").toString();
          int eff = _safeInt(emp['effectiveness_score']);
          int days = _safeInt(emp['days_employed']);
          int salary = _safeInt(emp['daily_salary']);
          int acu = _safeInt(emp['stat_acu']);
          int pre = _safeInt(emp['stat_pre']);
          int ops = _safeInt(emp['stat_ops']);
          int res = _safeInt(emp['stat_res']);
          String pos = (emp['position_role'] ?? 'Unassigned').toString();
          bool isDirector = pos == 'Director';

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
                    const Text("Effectiveness: ", style: TextStyle(color: Colors.white70, fontSize: 10)),
                    Expanded(child: LinearProgressIndicator(value: eff / 100, backgroundColor: Colors.black, color: Colors.cyanAccent, minHeight: 6)),
                    const SizedBox(width: 8),
                    Text("$eff%", style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text("Stats: Acu $acu | Pre $pre | Ops $ops | Res $res", style: const TextStyle(color: Colors.white38, fontSize: 9)),
                const Divider(color: Color(0xFF333333), height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _availablePositions.contains(pos) ? pos : 'Unassigned',
                        dropdownColor: matteBlack,
                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder(), labelText: "Position", labelStyle: TextStyle(color: Colors.white54, fontSize: 10)),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        items: _availablePositions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                        onChanged: (val) {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: salary.toString(),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder(), labelText: "Daily Salary (\$)", labelStyle: TextStyle(color: Colors.white54, fontSize: 10)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isDirector) ...[
                      ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.withValues(alpha: 0.1), side: const BorderSide(color: Colors.amber)), child: const Text("TRAIN", style: TextStyle(color: Colors.amber, fontSize: 10))),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.redAccent)), child: const Text("FIRE", style: TextStyle(color: Colors.redAccent, fontSize: 10))),
                    ] else ...[
                      const Text("Director cannot be fired or trained.", style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic))
                    ]
                  ],
                )
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildPositionsView() {
    List<Map<String, String>> positions = [
      {'name': 'Director', 'req': 'None', 'gain': 'None', 'desc': 'Owner of the company. Does not gain stats.'},
      {'name': 'Manager', 'req': 'Operations (Prim)', 'gain': 'High Ops / Med Res', 'desc': 'Boosts company efficiency significantly.'},
      {'name': 'Marketer', 'req': 'Precision (Prim)', 'gain': 'High Pre / Low Ops', 'desc': 'Increases customer daily walk-ins.'},
      {'name': 'Worker', 'req': 'Acumen (Prim)', 'gain': 'Med Acu / Med Res', 'desc': 'Standard labor. Generates raw output.'},
      {'name': 'Unassigned', 'req': 'None', 'gain': 'None', 'desc': 'Has no effect on the company. Receives no salary.'},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("ROLE ASSIGNMENTS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("Tap or long-press a position to view its responsibilities.", style: TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 16),
        ...positions.map((pos) => Tooltip(
          message: pos['desc'],
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
                    Text("Req: ${pos['req']}", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    Text("Gain: ${pos['gain']}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
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

  Widget _buildPricingView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("MARKET PRICING", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
          child: Row(
            children: [
              const Expanded(child: Text("Finished Goods", style: TextStyle(color: Colors.white, fontSize: 12))),
              SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: "15000",
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                  decoration: const InputDecoration(isDense: true, prefixText: "\$ ", prefixStyle: TextStyle(color: Colors.greenAccent), border: OutlineInputBorder(), labelText: "Price / Unit"),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, height: 40,
          child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.1), side: BorderSide(color: neonGreen)), child: Text("UPDATE PRICES", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold))),
        )
      ],
    );
  }

  Widget _buildStockView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("INVENTORY MANAGEMENT", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("WARNING: External stock shipments suffer a 1-day delivery delay.", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontStyle: FontStyle.italic)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("RAW MATERIALS (Input)", style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              const Divider(color: Color(0xFF333333), height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("In Stock:", style: TextStyle(color: Colors.white54, fontSize: 11)), Text("450 / 1000", style: TextStyle(color: neonGreen, fontSize: 11, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 4),
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Sold/Used Daily:", style: TextStyle(color: Colors.white54, fontSize: 11)), Text("120", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Cost Per Unit:", style: TextStyle(color: Colors.white54, fontSize: 11)), Text("\$$_unitCost", style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold))]),

              const SizedBox(height: 16),
              TextFormField(
                controller: _stockOrderController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: "Order Quantity", hintText: "0"),
                onChanged: (val) {
                  int qty = int.tryParse(val) ?? 0;
                  setState(() => _orderTotal = qty * _unitCost);
                },
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("TOTAL COST:", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                Text("\$${_formatNumber(_orderTotal)} Dirty Cash", style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 40,
                child: ElevatedButton(
                    onPressed: _orderTotal > 0 ? () {} : null,
                    style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.1), side: BorderSide(color: neonGreen)),
                    child: Text("PLACE ORDER", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold))
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

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
          child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withValues(alpha: 0.1), side: BorderSide(color: neonGreen)), child: Text("SET BUDGET", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold))),
        )
      ],
    );
  }

  Widget _buildFundsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("CORPORATE VAULT", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: const BorderSide(color: Colors.greenAccent)), child: const Text("DEPOSIT", style: TextStyle(color: Colors.greenAccent)))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: const BorderSide(color: Colors.redAccent)), child: const Text("WITHDRAW", style: TextStyle(color: Colors.redAccent)))),
          ],
        )
      ],
    );
  }

  Widget _buildUpgradesView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("COMPANY UPGRADES", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildUpgradeCard("Company Size", "Increases max employees by 25%. Costs 10% of base startup cost.", "\$250,000", true),
        _buildUpgradeCard("Staff Room", "Helps maintain 100% environment as employee count grows.", "\$50,000", true),
        _buildUpgradeCard("Warehouse Space", "Expands input/output capacity.", "\$100,000", false),
      ],
    );
  }

  Widget _buildUpgradeCard(String title, String desc, String cost, bool canAfford) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                const SizedBox(height: 4),
                Text("Cost: $cost", style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ElevatedButton(onPressed: canAfford ? (){} : null, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.withValues(alpha: 0.1), side: const BorderSide(color: Colors.amber)), child: const Text("BUY", style: TextStyle(color: Colors.amber)))
        ],
      ),
    );
  }

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
        SizedBox(width: double.infinity, height: 40, child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: BorderSide(color: neonGreen)), child: Text("SAVE CHANGES", style: TextStyle(color: neonGreen)))),
      ],
    );
  }

  Widget _buildChangeDirectorView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("TRANSFER OWNERSHIP", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("WARNING: You will lose ownership and become an Unassigned employee. The new director MUST already be an Unassigned employee in this company.", style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.4)),
        const SizedBox(height: 16),
        TextFormField(controller: _newDirectorController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "New Director (Username or ID)")),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 40, child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.redAccent)), child: const Text("TRANSFER DIRECTORSHIP", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)))),
      ],
    );
  }

  Widget _buildSellCompanyView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("LIQUIDATE ASSETS", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        const Text("Selling your company to the system permanently destroys it. All employees will be fired.\n\nReturns:\n• 75% of initial cost\n• 75% of all upgrades\n• 5% of lifetime revenue\n• 100% of current vault funds", style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.5)),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.2), side: const BorderSide(color: Colors.redAccent, width: 2)), child: const Text("SELL COMPANY", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)))),
      ],
    );
  }
}