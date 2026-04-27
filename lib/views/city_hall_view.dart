import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CityHallView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>)? onStateChange;
  final Function(int)? onViewCompany;

  const CityHallView({super.key, required this.userData, this.onStateChange, this.onViewCompany});

  @override
  State<CityHallView> createState() => _CityHallViewState();
}

class _CityHallViewState extends State<CityHallView> {
  final String apiUrl = "http://10.0.2.2:3000/cityhall";
  final String companiesApiUrl = "http://10.0.2.2:3000/companies";

  bool _isLoading = true;
  bool _isProcessing = false;

  bool _showBlueprints = false;

  List<dynamic> _levelLeaders = [];
  List<dynamic> _irsWatchlist = [];
  List<dynamic> _threatMatrix = [];

  List<dynamic> _blueprints = [];
  List<dynamic> _myCompanies = [];

  final int _itemsPerPage = 7;
  int _levelPage = 0;
  int _irsPage = 0;
  int _threatPage = 0;

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final leaderboardsRes = await http.get(Uri.parse('$apiUrl/leaderboards'));
      if (leaderboardsRes.statusCode == 200) {
        final lData = jsonDecode(leaderboardsRes.body);
        _levelLeaders = lData['records_level'] ?? [];
        _irsWatchlist = lData['irs_watchlist'] ?? [];
        _threatMatrix = lData['threat_matrix'] ?? [];
      } else {
        debugPrint("Failed Leaderboards: ${leaderboardsRes.statusCode}");
      }

      final blueprintsRes = await http.get(Uri.parse('$companiesApiUrl/blueprints'));
      if (blueprintsRes.statusCode == 200) {
        final bData = jsonDecode(blueprintsRes.body);
        _blueprints = bData['blueprints'] ?? [];
      } else {
        debugPrint("Failed Blueprints: ${blueprintsRes.statusCode}");
      }

      final myCompaniesRes = await http.get(Uri.parse('$companiesApiUrl/my-companies/${widget.userData['user_id']}'));
      if (myCompaniesRes.statusCode == 200) {
        final cData = jsonDecode(myCompaniesRes.body);
        _myCompanies = cData['companies'] ?? [];
      } else {
        debugPrint("Failed My Companies: ${myCompaniesRes.statusCode}");
      }

      if (mounted) setState(() => _isLoading = false);

    } catch (e) {
      debugPrint("Error fetching city hall data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCash(dynamic amount) {
    int val = amount is int ? amount : int.tryParse(amount.toString()) ?? 0;
    if (val >= 1000000000) return '\$${(val / 1000000000).toStringAsFixed(2)}B';
    if (val >= 1000000) return '\$${(val / 1000000).toStringAsFixed(2)}M';
    return '\$${val.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier')),
        backgroundColor: isError ? Colors.redAccent.shade700 : neonGreen.withOpacity(0.8)));
  }

  void _openCityGrantsDialog() {
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            backgroundColor: darkSurface,
            shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(8)),
            title: const Row(
              children: [
                Icon(Icons.public, color: Colors.cyanAccent, size: 20),
                SizedBox(width: 8),
                Text("GLOBAL CITY GRANT", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), border: Border.all(color: Colors.cyanAccent.withOpacity(0.5))),
                  child: const Text("NO ACTIVE GRANTS\n\nThere are currently no cooperative server events running. Check back later.",
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Courier')),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CLOSE", style: TextStyle(color: Colors.white54)))
            ],
          );
        }
    );
  }

  void _openIncorporationDialog(Map<String, dynamic> blueprint) {
    final TextEditingController nameController = TextEditingController();

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return AlertDialog(
            backgroundColor: darkSurface,
            shape: RoundedRectangleBorder(side: BorderSide(color: neonGreen), borderRadius: BorderRadius.circular(8)),
            title: Text("REGISTER ENTERPRISE", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Industry: ${blueprint['industry_type']}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text("Filing Fee: ${_formatCash(blueprint['setup_cost'])} Dirty Cash", style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text("ENTER COMPANY NAME:", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  maxLength: 30,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: Colors.black,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF39FF14))),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withOpacity(0.1), side: BorderSide(color: neonGreen)),
                onPressed: () async {
                  if (nameController.text.trim().length < 3) {
                    _showSnackbar("Name must be at least 3 characters long.", isError: true);
                    return;
                  }
                  Navigator.pop(ctx);
                  _processIncorporation(blueprint['type_id'], nameController.text.trim());
                },
                child: Text("PAY & REGISTER", style: TextStyle(color: neonGreen, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
    );
  }

  Future<void> _processIncorporation(int typeId, String companyName) async {
    setState(() => _isProcessing = true);
    try {
      final response = await http.post(Uri.parse('$companiesApiUrl/incorporate'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id'], "type_id": typeId, "company_name": companyName}));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _showSnackbar(data['message']);
        setState(() => _showBlueprints = false);
        await _fetchData();
        if (widget.onStateChange != null) widget.onStateChange!(widget.userData);
      } else {
        _showSnackbar(data['error'], isError: true);
      }
    } catch (e) {
      _showSnackbar("Network error submitting registration.", isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: matteBlack, body: Center(child: CircularProgressIndicator(color: neonGreen)));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: matteBlack,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text("CITY HALL", style: TextStyle(color: neonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
          iconTheme: IconThemeData(color: neonGreen),
          actions: [
            IconButton(icon: const Icon(Icons.emoji_events, color: Colors.cyanAccent), tooltip: "City Grants", onPressed: _openCityGrantsDialog),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            indicatorColor: neonGreen,
            labelColor: neonGreen,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
            tabs: const [
              Tab(text: "LEADERBOARDS"),
              Tab(text: "REGISTRY"),
              Tab(text: "MAYOR'S OFFICE"),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                _buildLeaderboardsTab(),
                _buildRegistryTab(),
                _buildMayorOfficeTab(),
              ],
            ),
            if (_isProcessing) Container(color: Colors.black54, child: Center(child: CircularProgressIndicator(color: neonGreen)))
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPaginatedCard(
              title: "HALL OF RECORDS (Highest Level)",
              description: "Public records of the most experienced citizens.",
              headers: ["Rank", "Citizen", "Level"],
              data: _levelLeaders,
              currentPage: _levelPage,
              onNext: () => setState(() => _levelPage++),
              onPrev: () => setState(() => _levelPage--),
              rowBuilder: (index, user) {
                bool isMe = user['username'] == widget.userData['username'];
                return [
                  Text("#${index + 1}", style: TextStyle(color: index < 3 ? Colors.amberAccent : Colors.white54, fontWeight: FontWeight.bold)),
                  Text(user['username'], style: TextStyle(color: isMe ? neonGreen : Colors.white, fontWeight: FontWeight.bold)),
                  Text("Lv. ${user['level']}", style: TextStyle(color: isMe ? neonGreen : Colors.cyanAccent, fontWeight: FontWeight.bold)),
                ];
              }
          ),
          const SizedBox(height: 24),
          _buildPaginatedCard(
              title: "IRS WATCHLIST (Net Worth)",
              description: "Wealthiest citizens. Names redacted for privacy. Syndicates public.",
              headers: ["Rank", "Syndicate", "Net Worth"],
              data: _irsWatchlist,
              currentPage: _irsPage,
              onNext: () => setState(() => _irsPage++),
              onPrev: () => setState(() => _irsPage--),
              rowBuilder: (index, user) {
                bool isMe = user['is_me'] ?? false;
                String syndicateText = user['syndicate_id'] != null ? "Faction #${user['syndicate_id']}" : "Unaffiliated";
                return [
                  Text("#${index + 1}", style: TextStyle(color: index < 3 ? Colors.amberAccent : Colors.white54, fontWeight: FontWeight.bold)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        color: isMe ? neonGreen : Colors.white,
                        child: Text(isMe ? widget.userData['username'] : "[REDACTED]", style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      ),
                      const SizedBox(height: 2),
                      Text(syndicateText, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                    ],
                  ),
                  Text(_formatCash(user['net_worth']), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                ];
              }
          ),
          const SizedBox(height: 24),
          _buildPaginatedCard(
              title: "THREAT MATRIX (Combat Power)",
              description: "Classified ranking of the most dangerous individuals based on stats.",
              headers: ["Rank", "Threat Profile", "Status"],
              data: _threatMatrix,
              currentPage: _threatPage,
              onNext: () => setState(() => _threatPage++),
              onPrev: () => setState(() => _threatPage--),
              rowBuilder: (index, user) {
                bool isMe = user['is_me'] ?? false;
                return [
                  Text("#${index + 1}", style: TextStyle(color: index < 3 ? Colors.amberAccent : Colors.white54, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: isMe ? neonGreen : Colors.white,
                    child: Text(isMe ? widget.userData['username'] : "[REDACTED]", style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                  const Text("CLASSIFIED", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ];
              }
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPaginatedCard({required String title, required String description, required List<String> headers, required List<dynamic> data, required int currentPage, required VoidCallback onNext, required VoidCallback onPrev, required List<Widget> Function(int globalIndex, dynamic item) rowBuilder}) {
    int totalItems = data.length;
    int totalPages = (totalItems / _itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    int startIndex = currentPage * _itemsPerPage;
    int endIndex = startIndex + _itemsPerPage;
    if (endIndex > totalItems) endIndex = totalItems;
    List<dynamic> currentView = data.isEmpty ? [] : data.sublist(startIndex, endIndex);

    return Container(
      decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12), color: const Color(0xFF1A1A1A),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF333333)))),
            child: Row(
              children: headers.asMap().entries.map((entry) {
                int flex = entry.key == 1 ? 3 : 2;
                return Expanded(flex: flex, child: Text(entry.value, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)));
              }).toList(),
            ),
          ),
          if (currentView.isEmpty) const Padding(padding: EdgeInsets.all(16.0), child: Center(child: Text("No records found.", style: TextStyle(color: Colors.white54)))),
          ...currentView.asMap().entries.map((entry) {
            int localIndex = entry.key;
            int globalIndex = startIndex + localIndex;
            var item = entry.value;
            List<Widget> columns = rowBuilder(globalIndex, item);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: localIndex % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02), border: const Border(bottom: BorderSide(color: Color(0xFF333333)))),
              child: Row(
                children: columns.asMap().entries.map((colEntry) {
                  int flex = colEntry.key == 1 ? 3 : 2;
                  return Expanded(flex: flex, child: colEntry.value);
                }).toList(),
              ),
            );
          }),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white), onPressed: currentPage > 0 ? onPrev : null, disabledColor: Colors.white24, constraints: const BoxConstraints(), padding: EdgeInsets.zero),
                Text("PAGE ${currentPage + 1} OF $totalPages", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white), onPressed: currentPage < totalPages - 1 ? onNext : null, disabledColor: Colors.white24, constraints: const BoxConstraints(), padding: EdgeInsets.zero),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRegistryTab() {
    if (_showBlueprints) {
      return _buildBlueprintsView();
    } else {
      return _buildMyEnterprisesView();
    }
  }

  Widget _buildMyEnterprisesView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333))),
            child: const Text("COMMERCIAL REGISTRY\nManage your corporate portfolio or file for new enterprise licensing.", style: TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("YOUR ENTERPRISES", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
              SizedBox(
                height: 26,
                child: ElevatedButton(
                  onPressed: () => setState(() => _showBlueprints = true),
                  style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withOpacity(0.2), side: BorderSide(color: neonGreen)),
                  child: Text("+ NEW", style: TextStyle(color: neonGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
          const SizedBox(height: 12),

          if (_myCompanies.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
              child: const Column(
                children: [
                  Icon(Icons.domain_disabled, color: Colors.white24, size: 48),
                  SizedBox(height: 12),
                  Text("NO REGISTERED BUSINESSES", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: const Color(0xFF1A1A1A),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: Text("Company", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text("Industry", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text("Rating", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  ..._myCompanies.map((comp) {
                    bool isActive = comp['is_active'];
                    return InkWell(
                      onTap: () {
                        if (widget.onViewCompany != null) {
                          widget.onViewCompany!(comp['company_id']);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF333333)))),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(comp['company_name'], style: TextStyle(color: isActive ? neonGreen : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(isActive ? "Active" : "Closed", style: TextStyle(color: isActive ? Colors.greenAccent : Colors.redAccent, fontSize: 9)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(comp['industry_type'], style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text("Tier ${comp['tier']}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 9)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amberAccent, size: 12),
                                  const SizedBox(width: 4),
                                  Text("${comp['star_rating']}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
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

  Widget _buildBlueprintsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white54),
                onPressed: () => setState(() => _showBlueprints = false),
              ),
              const Text("COMMERCIAL BLUEPRINTS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 16),

          ..._blueprints.map((bp) {
            Color tierColor = bp['tier'] == 3 ? Colors.purpleAccent : (bp['tier'] == 2 ? Colors.cyanAccent : Colors.white70);
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: darkSurface, border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(4)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(color: Color(0xFF1A1A1A), border: Border(bottom: BorderSide(color: Color(0xFF333333)))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(bp['industry_type'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        Text("TIER ${bp['tier']}", style: TextStyle(color: tierColor, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bp['description'], style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildRegistryStat("Setup Cost", _formatCash(bp['setup_cost']), Colors.redAccent)),
                            Expanded(child: _buildRegistryStat("Daily Upkeep", _formatCash(bp['daily_upkeep']), Colors.orangeAccent)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildRegistryStat("Max Employees", "${bp['max_employees']}", Colors.white)),
                            Expanded(child: _buildRegistryStat("Warehouse Cap", "${bp['base_warehouse_max']} Units", Colors.white54)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity, height: 36,
                          child: ElevatedButton(
                            onPressed: () => _openIncorporationDialog(bp),
                            style: ElevatedButton.styleFrom(backgroundColor: darkSurface, side: BorderSide(color: neonGreen.withOpacity(0.5))),
                            child: Text("INCORPORATE ENTERPRISE", style: TextStyle(color: neonGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRegistryStat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMayorOfficeTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance, color: Colors.white24, size: 64),
          SizedBox(height: 16),
          Text("MAYORAL ELECTIONS PENDING", style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
          SizedBox(height: 8),
          Text("The active administration is currently locked.", style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}