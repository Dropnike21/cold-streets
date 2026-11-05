import 'package:flutter/material.dart';
import '../services/game_http.dart' as http;
import 'dart:convert';

import '../api_config.dart';

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
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/real-estate/portfolio/$userId'));

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
            'market_price': _parseSafeInt(item['acquisition_cost_reference'] ?? item['cost']),
            'upkeep': _parseSafeInt(item['total_upkeep_reference'] ?? item['upkeep_val']),
            'hp_bonus': _parseSafeInt(item['hp_bonus_source_value'] ?? item['hp_bonus']),
            'gym_bonus': item['gym_bonus_source_value'] ?? item['gym_bonus'],
            'status': item['status'] == 'active_residence' ? 'Primary Residence' : 'Idle',
            'installed_upgrade_ids': item['installed_upgrade_ids'] ?? [],
            'available_upgrades': item['available_upgrades'] ?? [],
            'bonus_status': item['bonus_application_status'] ?? 'unresolved_source_conflict',
            'upkeep_status': item['upkeep_collection_status'] ?? 'unimplemented',
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
        Uri.parse('${ApiConfig.baseUrl}/real-estate/move-in'),
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

  String _formatCash(num amount) {
    String formatted = amount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return '\$$formatted';
  }

  double _calculateUpkeep(Map<String, dynamic> prop) {
    double cost = _parseSafeDouble(prop['cost']);
    double val = _parseSafeDouble(prop['upkeep_val']);
    if (prop['upkeep_type'] == 'daily_cash' || prop['upkeep_type'] == 'flat') return val;
    return 0;
  }

  bool _hasAccess(Map<String, dynamic> prop, String action) {
    bool isOwner = prop['owner'] == 'Player';
    if (!isOwner) return false;
    // Only Move In has an active mutation. The other actions remain visible
    // so their reconciliation status can be explained in the management panel.
    return true;
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
                                  _buildModalDetailRow("Upkeep ref:", "${_formatCash(prop['upkeep'])}/d", Colors.redAccent),
                                  _buildModalDetailRow("HP source value:", "${prop['hp_bonus']}", const Color(0xFF39FF14)),
                                  _buildModalDetailRow("Gym source value:", "${prop['gym_bonus']}", Colors.blueAccent),
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
        final availableUpgrades = prop['available_upgrades'] is List
            ? List<dynamic>.from(prop['available_upgrades'])
            : <dynamic>[];
        final installedIds = prop['installed_upgrade_ids'] is List
            ? Set<String>.from((prop['installed_upgrade_ids'] as List).map((e) => e.toString()))
            : <String>{};

        if (availableUpgrades.isEmpty) {
          return const Center(
            child: Text(
              "No recovered upgrades are defined for this property.",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          );
        }

        return ListView.builder(
          itemCount: availableUpgrades.length,
          itemBuilder: (context, index) {
            final upgrade = Map<String, dynamic>.from(availableUpgrades[index] as Map);
            final id = upgrade['id']?.toString() ?? '';
            final installed = installedIds.contains(id);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                border: Border.all(
                  color: installed ? const Color(0xFF39FF14) : Colors.white12,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            color: installed ? const Color(0xFF39FF14) : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Cost ref: ${_formatCash(upgrade['cost'])}  •  Upkeep +${_formatCash(upgrade['upkeep_increase'])}/d",
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    installed ? "INSTALLED" : "PURCHASE PAUSED",
                    style: TextStyle(
                      color: installed ? const Color(0xFF39FF14) : Colors.amber,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      case 'Sell':
        return const Center(
          child: Text(
            "SALE LISTING PAUSED\n\nPlayer-market settlement currency, fees, and cancellation rules are not yet canonical.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.5),
          ),
        );
      case 'Upkeep':
        return const Center(
          child: Text(
            "UPKEEP PAYMENT PAUSED\n\nThe source defines daily upkeep and a 7-day missed-payment consequence, but the payment currency/cadence mechanics are not yet canonical.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.5),
          ),
        );
      case 'Lease':
        return const Center(
          child: Text(
            "LEASES PAUSED\n\nContract duration, rent denomination, settlement timing, and renter rights are unresolved.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.5),
          ),
        );
      case 'Give':
        return const Center(
          child: Text(
            "GIFT TRANSFERS PAUSED\n\nTransfer restrictions and audit semantics are unresolved.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.5),
          ),
        );
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
                  const Text("CATALOG COST REFERENCE:", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
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