import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ManagePropertiesView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const ManagePropertiesView({super.key, required this.userData, required this.onStateChange});

  @override
  State<ManagePropertiesView> createState() => _ManagePropertiesViewState();
}

class _ManagePropertiesViewState extends State<ManagePropertiesView> {
  late String userId;
  int? currentResidenceId;
  late int cleanCash;

  bool isLoading = true;
  List<Map<String, dynamic>> ownedProperties = [];

  final List<Map<String, dynamic>> upgradeCatalog = [
    {'id': 'burner_phones', 'name': 'Burner Phone Farm', 'cost': 25000, 'desc': 'Generates Influence.', 'tiers': ['Urban Living']},
    {'id': 'advanced_locks', 'name': 'Advanced Locks', 'cost': 75000, 'desc': 'Street robbery protection.', 'tiers': ['Urban Living']},
    {'id': 'lobbying_office', 'name': 'Lobbying Office', 'cost': 2500000, 'desc': 'Generates Influence points.', 'tiers': ['Luxury Class']},
    {'id': 'police_scanner', 'name': 'Police Scanner', 'cost': 1000000, 'desc': 'Heat decays 2x faster.', 'tiers': ['Luxury Class']},
    {'id': 'panic_room', 'name': 'Panic Room', 'cost': 5000000, 'desc': 'Protects cash from raids.', 'tiers': ['Luxury Class']},
    {'id': 'command_center', 'name': 'Syndicate Command', 'cost': 150000000, 'desc': 'Generates high Influence.', 'tiers': ['The Elite']},
    {'id': 'police_payroll', 'name': 'Chief on Payroll', 'cost': 350000000, 'desc': 'Ignore minor crimes.', 'tiers': ['The Elite']},
    {'id': 'vault_basic', 'name': 'Underground Vault', 'cost': 250000000, 'desc': 'Safely store \$500M.', 'tiers': ['The Elite'], 'requires_id': [14, 15]},
    {'id': 'vault_max', 'name': 'Mega Vault', 'cost': 800000000, 'desc': 'Safely store \$2B.', 'tiers': ['The Elite'], 'requires_id': [15]},
    {'id': 'airstrip', 'name': 'Private Airstrip', 'cost': 500000000, 'desc': 'Zero customs risk travel.', 'tiers': ['The Elite'], 'requires_id': [15]},
  ];

  int _parseSafeInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _parseSafeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  void initState() {
    super.initState();
    userId = widget.userData['user_id']?.toString() ?? "0";
    cleanCash = _parseSafeInt(widget.userData['clean_cash']);
    _fetchPortfolio();
  }

  Future<void> _fetchPortfolio() async {
    try {
      final response = await http.get(Uri.parse('http://10.0.2.2:3000/real-estate/portfolio/$userId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> fetchedProps = [];

        for (var item in data['portfolio']) {
          if (item['status'] == 'active_residence') {
            currentResidenceId = _parseSafeInt(item['instance_id']);
          }

          fetchedProps.add({
            'instance_id': _parseSafeInt(item['instance_id']),
            'type_id': _parseSafeInt(item['property_type_id']),
            'tier': item['tier'],
            'name': item['name'],
            'owner': 'Player',
            'market_price': _parseSafeInt(item['cost']),
            'upkeep': _calculateUpkeep(item),
            'hp_bonus': _parseSafeInt(item['hp_bonus']),
            'gym_bonus': _parseSafeDouble(item['gym_bonus']),
            'staff_cost': 0,
            'status': item['status'] == 'active_residence' ? 'Primary Residence' : 'Idle',
            'upgrades': item['upgrades'] ?? {},
          });
        }

        if (mounted) {
          setState(() {
            ownedProperties = fetchedProps;
            isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("Fetch Portfolio Error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _moveToProperty(int instanceId) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))));

    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:3000/real-estate/move-in'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'instanceId': instanceId}),
      );

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        setState(() {
          currentResidenceId = instanceId;
          for (var p in ownedProperties) {
            if (p['instance_id'] == instanceId) {
              p['status'] = 'Primary Residence';
            } else if (p['status'] == 'Primary Residence') {
              p['status'] = 'Idle';
            }
          }
        });
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Moved into new residence."), backgroundColor: Color(0xFF39FF14)));
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'] ?? "Failed to move in."), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Network error: $e"), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _purchaseUpgrade(Map<String, dynamic> prop, Map<String, dynamic> upgrade, StateSetter setModalState) async {
    if (cleanCash < upgrade['cost']) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))));

    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:3000/real-estate/upgrade'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'instanceId': prop['instance_id'],
          'upgradeId': upgrade['id'],
          'cost': upgrade['cost']
        }),
      );

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        setState(() {
          cleanCash -= upgrade['cost'] as int;
          widget.userData['clean_cash'] = cleanCash;

          prop['upgrades'][upgrade['id']] = true;
          widget.onStateChange(widget.userData);
        });
        setModalState(() {});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${upgrade['name']} installed successfully."), backgroundColor: const Color(0xFF39FF14)));
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'] ?? "Purchase failed."), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Network error: $e"), backgroundColor: Colors.redAccent));
      }
    }
  }

  String _formatCash(num amount) {
    String formatted = amount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return '\$$formatted';
  }

  double _calculateUpkeep(Map<String, dynamic> prop) {
    double cost = _parseSafeDouble(prop['cost']);
    double val = _parseSafeDouble(prop['upkeep_val']);
    if (prop['upkeep_type'] == 'flat') return val;
    return cost * val;
  }

  bool _hasAccess(Map<String, dynamic> prop, String action) {
    bool isOwner = prop['owner'] == 'Player';
    bool isTrailer = prop['type_id'] == 1;

    // RULE: You cannot sell, lease, or give away the Default Trailer
    if (isTrailer && ['Sell', 'Lease', 'Give'].contains(action)) {
      return false;
    }

    if (isOwner) return true;
    if (['Move In', 'Customize', 'Upkeep'].contains(action)) return true;
    return false;
  }

  void _showPropertyModal(Map<String, dynamic> prop, {String initialAction = 'Overview'}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (BuildContext context) {
        String selectedAction = initialAction;
        final actions = ['Overview', 'Move In', 'Customize', 'Upkeep', 'Sell', 'Lease', 'Give'];

        return StatefulBuilder(
          builder: (context, setModalState) {
            bool isResidence = prop['instance_id'] == currentResidenceId;
            return Dialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF333333))),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: SizedBox(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Container(
                      height: 180,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 140,
                            decoration: BoxDecoration(color: const Color(0xFF252525), borderRadius: BorderRadius.circular(8), border: Border.all(color: isResidence ? const Color(0xFF39FF14) : Colors.white12, width: isResidence ? 2 : 1)),
                            child: Stack(
                              children: [
                                const Center(child: Icon(Icons.domain, color: Colors.white12, size: 56)),
                                if (isResidence)
                                  Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF39FF14), borderRadius: BorderRadius.circular(4)), child: const Text("LIVING HERE", style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)))),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(prop['name'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
                                  const Divider(color: Color(0xFF333333), height: 16),
                                  _buildModalDetailRow("Owner:", prop['owner'], Colors.white),
                                  _buildModalDetailRow("Value:", _formatCash(prop['market_price']), Colors.white),
                                  _buildModalDetailRow("Upkeep:", "${_formatCash(prop['upkeep'])}/d", Colors.redAccent),
                                  _buildModalDetailRow("Staff:", "${_formatCash(prop['staff_cost'])}/d", Colors.orangeAccent),
                                  _buildModalDetailRow("Gains:", "+${prop['hp_bonus']}% HP | +${prop['gym_bonus']}% GYM", const Color(0xFF39FF14)),
                                  _buildModalDetailRow("Status:", prop['status'], Colors.cyanAccent),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF333333), height: 1),
                    Container(
                      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF121212), border: Border(bottom: BorderSide(color: Colors.grey.shade900))),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: actions.map((action) {
                            bool hasPermission = _hasAccess(prop, action);
                            bool isSelected = selectedAction == action;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text(action.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: hasPermission ? (isSelected ? Colors.black : Colors.white70) : Colors.white24)),
                                selected: isSelected && hasPermission, selectedColor: const Color(0xFF39FF14), backgroundColor: const Color(0xFF1A1A1A), disabledColor: const Color(0xFF121212), side: BorderSide(color: hasPermission ? (isSelected ? const Color(0xFF39FF14) : Colors.white24) : Colors.transparent),
                                onSelected: hasPermission ? (bool selected) { if (selected) setModalState(() => selectedAction = action); } : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: double.infinity, padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(bottom: Radius.circular(12))),
                        child: _buildDynamicActionArea(selectedAction, prop, setModalState),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDynamicActionArea(String action, Map<String, dynamic> prop, StateSetter setModalState) {
    switch (action) {
      case 'Move In':
        bool isAlreadyLivingHere = prop['instance_id'] == currentResidenceId;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.house, color: isAlreadyLivingHere ? Colors.grey : const Color(0xFF39FF14), size: 40),
            const SizedBox(height: 16),
            Text(isAlreadyLivingHere ? "You already live here." : "Set this property as your primary residence to receive its HP and Gym bonuses.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const Spacer(),
            SizedBox(
              width: double.infinity, height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                onPressed: isAlreadyLivingHere ? null : () => _moveToProperty(prop['instance_id']),
                child: const Text("MOVE IN NOW", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              ),
            )
          ],
        );
      case 'Customize':
        List<Map<String, dynamic>> availableUpgrades = upgradeCatalog.where((u) {
          bool correctTier = u['tiers'].contains(prop['tier']);
          bool correctProperty = u['requires_id'] == null || (u['requires_id'] as List).contains(prop['type_id']);
          return correctTier && correctProperty;
        }).toList();

        if (availableUpgrades.isEmpty) {
          return const Center(child: Text("This property tier does not support upgrades.", style: TextStyle(color: Colors.white54, fontSize: 12)));
        }

        return ListView.builder(
          itemCount: availableUpgrades.length,
          itemBuilder: (context, index) {
            var upgrade = availableUpgrades[index];
            bool hasUpgrade = (prop['upgrades'] as Map).containsKey(upgrade['id']);
            bool canAfford = cleanCash >= _parseSafeInt(upgrade['cost']);

            return Container(
              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF121212), border: Border.all(color: hasUpgrade ? const Color(0xFF39FF14) : Colors.white12), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(upgrade['name'], style: TextStyle(color: hasUpgrade ? const Color(0xFF39FF14) : Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(upgrade['desc'], style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (hasUpgrade)
                    const Icon(Icons.check_circle, color: Color(0xFF39FF14), size: 24)
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: canAfford ? Colors.grey[800] : Colors.transparent, foregroundColor: canAfford ? Colors.white : Colors.white24),
                      onPressed: canAfford ? () => _purchaseUpgrade(prop, upgrade, setModalState) : null,
                      child: Text(_formatCash(upgrade['cost']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                ],
              ),
            );
          },
        );
      case 'Sell':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("LIST PROPERTY ON MARKET", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 16),
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(filled: true, fillColor: const Color(0xFF121212), hintText: "Asking Price", hintStyle: const TextStyle(color: Colors.white24), prefixIcon: const Icon(Icons.attach_money, color: Color(0xFF39FF14), size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12))),
              keyboardType: TextInputType.number,
            ),
            const Spacer(),
            SizedBox(width: double.infinity, height: 45, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))), onPressed: () {}, child: const Text("CONFIRM SALE", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1))))
          ],
        );
      case 'Upkeep':
      case 'Lease':
      case 'Give':
        return Center(child: Text("$action management coming soon.", style: const TextStyle(color: Colors.white54, fontStyle: FontStyle.italic, fontSize: 12)));
      default:
        return const Center(child: Text("Select an action from the menu above to manage this property.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)));
    }
  }

  Widget _buildModalDetailRow(String label, String value, Color valColor) {
    return Padding(padding: const EdgeInsets.only(bottom: 6.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)), Text(value, style: TextStyle(color: valColor, fontSize: 12, fontWeight: FontWeight.w900))]));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))));
    }

    int portfolioValue = ownedProperties.fold(0, (sum, item) => sum + _parseSafeInt(item['market_price']));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black, elevation: 0,
        title: const Text("PORTFOLIO", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        centerTitle: true, iconTheme: const IconThemeData(color: Color(0xFF39FF14)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("PORTFOLIO VALUE:", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  Text(_formatCash(portfolioValue), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (ownedProperties.isEmpty)
              const Expanded(child: Center(child: Text("You do not own any properties.\nVisit the Real Estate Agency.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, height: 1.5))))
            else
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.55),
                  itemCount: ownedProperties.length,
                  itemBuilder: (context, index) {
                    var prop = ownedProperties[index];
                    bool isResidence = prop['instance_id'] == currentResidenceId;

                    return GestureDetector(
                      onTap: () => _showPropertyModal(prop),
                      child: Container(
                        decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: isResidence ? const Color(0xFF39FF14) : Colors.white12, width: isResidence ? 2 : 1), borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 3, child: Stack(children: [Container(decoration: const BoxDecoration(color: Color(0xFF252525), borderRadius: BorderRadius.vertical(top: Radius.circular(6))), child: const Center(child: Icon(Icons.domain, color: Colors.white12, size: 28))), if (isResidence) Positioned(top: 4, right: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF39FF14), borderRadius: BorderRadius.circular(4)), child: const Text("LIVING", style: TextStyle(color: Colors.black, fontSize: 7, fontWeight: FontWeight.bold))))])),
                            Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(prop['name'].toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 2), Text(prop['owner'].toString(), style: const TextStyle(color: Colors.grey, fontSize: 8))]))),
                            Container(padding: const EdgeInsets.symmetric(vertical: 4), decoration: const BoxDecoration(color: Color(0xFF121212), borderRadius: BorderRadius.vertical(bottom: Radius.circular(6))), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildGridActionIcon(Icons.house, prop, 'Move In'), _buildGridActionIcon(Icons.build, prop, 'Customize'), _buildGridActionIcon(Icons.payment, prop, 'Upkeep')]), const SizedBox(height: 6), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildGridActionIcon(Icons.attach_money, prop, 'Sell'), _buildGridActionIcon(Icons.handshake, prop, 'Lease'), _buildGridActionIcon(Icons.card_giftcard, prop, 'Give')])]))
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridActionIcon(IconData icon, Map<String, dynamic> prop, String action) {
    bool hasPermission = _hasAccess(prop, action);
    return InkWell(onTap: hasPermission ? () => _showPropertyModal(prop, initialAction: action) : null, child: Padding(padding: const EdgeInsets.all(2.0), child: Icon(icon, color: hasPermission ? Colors.white70 : Colors.white10, size: 14)));
  }
}