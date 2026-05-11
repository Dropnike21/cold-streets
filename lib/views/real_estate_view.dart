import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

import '../api_config.dart';

class RealEstateView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const RealEstateView({super.key, required this.userData, required this.onStateChange});

  @override
  State<RealEstateView> createState() => _RealEstateViewState();
}

class _RealEstateViewState extends State<RealEstateView> {
  late int currentPropertyId;
  late int cleanCash;
  late String userId;

  bool isLoading = true;
  bool isAgencyView = true;
  int playerMarketPage = 1;
  final int itemsPerPage = 30;

  bool filterShowSales = true;
  bool filterShowRentals = true;
  bool filterOnlyUpgraded = false;

  List<Map<String, dynamic>> properties = [];
  List<Map<String, dynamic>> playerListings = [];
  Map<int, int> ownedCounts = {}; // NEW: Tracks how many of each property the player owns

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
    _syncState();
    _fetchMarketData();
  }

  void _syncState() {
    userId = widget.userData['user_id']?.toString() ?? "0";
    currentPropertyId = _parseSafeInt(widget.userData['property_id']);
    if (currentPropertyId == 0) currentPropertyId = 1;
    cleanCash = _parseSafeInt(widget.userData['clean_cash']);
  }

  Future<void> _fetchMarketData() async {
    try {
      final catRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/real-estate/catalog'));
      if (catRes.statusCode == 200) {
        properties = List<Map<String, dynamic>>.from(jsonDecode(catRes.body)['catalog']);
      }

      final mktRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/real-estate/market'));
      if (mktRes.statusCode == 200) {
        playerListings = List<Map<String, dynamic>>.from(jsonDecode(mktRes.body)['listings']);
      }

      // NEW: Fetch portfolio just to get the ownership counts for the badges
      final portRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/real-estate/portfolio/$userId'));
      if (portRes.statusCode == 200) {
        final portData = jsonDecode(portRes.body)['portfolio'];
        ownedCounts.clear();
        for (var item in portData) {
          int tId = _parseSafeInt(item['property_type_id']);
          ownedCounts[tId] = (ownedCounts[tId] ?? 0) + 1;
        }
      }

    } catch (e) {
      debugPrint("Market Fetch Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _formatCash(num amount) {
    if (amount == 0) return 'Free';
    String formatted = amount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return '\$$formatted';
  }

  double _calculateUpkeep(Map<String, dynamic> prop) {
    double cost = _parseSafeDouble(prop['cost']);
    double val = _parseSafeDouble(prop['upkeep_val']);
    if (prop['upkeep_type'] == 'flat') return val;
    return cost * val;
  }

  // --- NEW PURCHASE PROMPT ---
  void _promptPurchaseOptions(Map<String, dynamic> prop) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF333333))),
          title: const Text("FINALIZE PURCHASE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          content: const Text("Would you like to move into this property immediately, or stay in your current residence?", style: TextStyle(color: Colors.white70, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(ctx); _buyAgencyProperty(prop, autoMoveIn: false); },
              child: const Text("BUY & STAY", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14), foregroundColor: Colors.black),
              onPressed: () { Navigator.pop(ctx); _buyAgencyProperty(prop, autoMoveIn: true); },
              child: const Text("BUY & MOVE IN", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        )
    );
  }

  Future<void> _buyAgencyProperty(Map<String, dynamic> prop, {required bool autoMoveIn}) async {
    int propCost = _parseSafeInt(prop['cost']);
    if (cleanCash < propCost) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))));

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/real-estate/buy-agency'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'propertyTypeId': prop['id'],
          'autoMoveIn': autoMoveIn // NEW API ARGUMENT
        }),
      );

      if (mounted) Navigator.pop(context);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          cleanCash -= propCost;
          widget.userData['clean_cash'] = cleanCash;

          // Increment local badge count
          int tId = prop['id'];
          ownedCounts[tId] = (ownedCounts[tId] ?? 0) + 1;

          if (data['status'] == 'active_residence') {
            currentPropertyId = prop['id'];
            widget.userData['property_id'] = currentPropertyId;
          }
          widget.onStateChange(widget.userData);
        });

        if (mounted) {
          Navigator.pop(context); // Close the bottom sheet modal
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message']), backgroundColor: const Color(0xFF39FF14)));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'] ?? "Purchase failed."), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Network error: $e"), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _showFilterModal() {
    showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF333333))),
                  title: const Text("MARKET FILTERS", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        title: const Text("Show Properties For Sale", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        value: filterShowSales, activeColor: const Color(0xFF39FF14), checkColor: Colors.black, dense: true, controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setDialogState(() => filterShowSales = val ?? true),
                      ),
                      CheckboxListTile(
                        title: const Text("Show Properties For Rent", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        value: filterShowRentals, activeColor: Colors.cyanAccent, checkColor: Colors.black, dense: true, controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setDialogState(() => filterShowRentals = val ?? true),
                      ),
                      CheckboxListTile(
                        title: const Text("Only Show Upgraded Properties", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        value: filterOnlyUpgraded, activeColor: Colors.amberAccent, checkColor: Colors.black, dense: true, controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setDialogState(() => filterOnlyUpgraded = val ?? false),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() => playerMarketPage = 1);
                        Navigator.pop(context);
                      },
                      child: const Text("APPLY FILTERS", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              }
          );
        }
    );
  }

  void _showAgencyDetails(Map<String, dynamic> prop) {
    double dailyUpkeep = _calculateUpkeep(prop);
    int propCost = _parseSafeInt(prop['cost']);
    bool canAfford = cleanCash >= propCost;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(16)), border: Border(top: BorderSide(color: Color(0xFF39FF14), width: 2))),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prop['name'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        const Text("AGENCY LISTING", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ],
                    ),
                  ),
                  Text(_formatCash(propCost), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildStatBox("BASE UPKEEP", _formatCash(dailyUpkeep), Colors.redAccent)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatBox("MAX HP BONUS", "+${_parseSafeInt(prop['hp_bonus'])}%", const Color(0xFF39FF14))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatBox("GYM BONUS", "+${_parseSafeDouble(prop['gym_bonus'])}%", Colors.blueAccent)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAfford ? const Color(0xFF39FF14) : Colors.grey[800],
                    foregroundColor: canAfford ? Colors.black : Colors.white54,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  // Users can always buy properties now!
                  onPressed: canAfford ? () => _promptPurchaseOptions(prop) : null,
                  child: Text(
                    canAfford ? "PURCHASE PROPERTY" : "INSUFFICIENT BANK FUNDS",
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black, elevation: 0, titleSpacing: 16, centerTitle: false,
        title: const Text("REAL ESTATE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 16)),
        iconTheme: const IconThemeData(color: Color(0xFF39FF14)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 12, bottom: 12),
            child: Container(
              width: 150,
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white12)),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isAgencyView = true),
                      child: Container(
                        decoration: BoxDecoration(color: isAgencyView ? const Color(0xFF39FF14).withOpacity(0.1) : Colors.transparent, borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)), border: Border(right: BorderSide(color: isAgencyView ? const Color(0xFF39FF14) : Colors.white12))),
                        child: Center(child: Text("AGENCY", style: TextStyle(color: isAgencyView ? const Color(0xFF39FF14) : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isAgencyView = false),
                      child: Container(
                        decoration: BoxDecoration(color: !isAgencyView ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent, borderRadius: const BorderRadius.horizontal(right: Radius.circular(5))),
                        child: Center(child: Text("MARKET", style: TextStyle(color: !isAgencyView ? Colors.cyanAccent : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
      body: isAgencyView ? _buildAgencyGrid() : _buildPlayerMarketList(),
    );
  }

  Widget _buildAgencyGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85),
      itemCount: properties.length,
      itemBuilder: (context, index) {
        var prop = properties[index];
        int count = ownedCounts[prop['id']] ?? 0;
        bool hasAny = count > 0;

        return GestureDetector(
          onTap: () => _showAgencyDetails(prop),
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: hasAny ? const Color(0xFF39FF14).withOpacity(0.5) : Colors.white12, width: 1), borderRadius: BorderRadius.circular(8)),
            child: Stack(
              children: [
                Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Container(color: const Color(0xFF252525), child: const Center(child: Icon(Icons.domain, color: Colors.white12, size: 40))))),
                // NEW: Quantity Badge
                if (hasAny)
                  Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF39FF14), borderRadius: BorderRadius.circular(4)), child: Text("OWNED: $count", style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)))),
                Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6), decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)), gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.9), Colors.transparent])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(prop['name'].toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), Text(_formatCash(_parseSafeInt(prop['cost'])), style: TextStyle(color: hasAny ? const Color(0xFF39FF14) : Colors.grey, fontSize: 9, fontWeight: FontWeight.w600))]))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerMarketList() {
    List<Map<String, dynamic>> filteredListings = playerListings.where((l) {
      if (!filterShowSales && l['listing_type'] == 'SALE') return false;
      if (!filterShowRentals && l['listing_type'] == 'RENT') return false;
      bool hasUpgrades = l['upgrades'] != null && (l['upgrades'] as Map).isNotEmpty;
      if (filterOnlyUpgraded && !hasUpgrades) return false;
      return true;
    }).toList();

    int totalPages = max(1, (filteredListings.length / itemsPerPage).ceil());
    if (playerMarketPage > totalPages) playerMarketPage = totalPages;

    List<Map<String, dynamic>> currentPageItems = filteredListings.sublist((playerMarketPage - 1) * itemsPerPage, min(playerMarketPage * itemsPerPage, filteredListings.length));

    return Column(
      children: [
        Container(
          height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left, size: 18), color: Colors.cyanAccent, padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: playerMarketPage > 1 ? () => setState(() => playerMarketPage--) : null, disabledColor: Colors.white12),
                  const SizedBox(width: 12),
                  Text("PAGE $playerMarketPage OF $totalPages", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(width: 12),
                  IconButton(icon: const Icon(Icons.chevron_right, size: 18), color: Colors.cyanAccent, padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: playerMarketPage < totalPages ? () => setState(() => playerMarketPage++) : null, disabledColor: Colors.white12),
                ],
              ),
              InkWell(
                onTap: _showFilterModal,
                child: Row(children: [Icon(Icons.filter_list, size: 14, color: (filterOnlyUpgraded || !filterShowSales || !filterShowRentals) ? const Color(0xFF39FF14) : Colors.grey), const SizedBox(width: 4), Text("FILTER", style: TextStyle(color: (filterOnlyUpgraded || !filterShowSales || !filterShowRentals) ? const Color(0xFF39FF14) : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))]),
              )
            ],
          ),
        ),
        Expanded(
          child: filteredListings.isEmpty
              ? const Center(child: Text("No properties found matching your filters.", style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)))
              : ListView.separated(
            padding: const EdgeInsets.only(bottom: 24), itemCount: currentPageItems.length, separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
            itemBuilder: (context, index) {
              var listing = currentPageItems[index];
              bool isSale = listing['listing_type'] == 'SALE';
              Color badgeColor = isSale ? const Color(0xFF39FF14) : Colors.cyanAccent;
              int upgradeCount = listing['upgrades'] != null ? (listing['upgrades'] as Map).length : 0;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: index % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(listing['prop_name'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), if (upgradeCount > 0) ...[const SizedBox(width: 6), const Icon(Icons.build, color: Colors.amberAccent, size: 10), Text("+$upgradeCount", style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold))]]), const SizedBox(height: 2), Text("Owner: ${listing['owner_name']}", style: const TextStyle(color: Colors.grey, fontSize: 9))])),
                    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(listing['listing_type'], style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)), const SizedBox(height: 2), Text(isSale ? _formatCash(_parseSafeInt(listing['asking_price'])) : "${_formatCash(_parseSafeInt(listing['asking_price']))}/day", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))])),
                    Expanded(flex: 1, child: Container(alignment: Alignment.centerRight, child: SizedBox(height: 26, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), foregroundColor: badgeColor, side: BorderSide(color: badgeColor), padding: const EdgeInsets.symmetric(horizontal: 10)), onPressed: () {}, child: Text(isSale ? "BUY" : "RENT", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))))),
                  ],
                ),
              );
            },
          ),
        )
      ],
    );
  }

  Widget _buildStatBox(String label, String value, Color valColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), decoration: BoxDecoration(color: const Color(0xFF121212), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white12)),
      child: Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)), const SizedBox(height: 4), Text(value, style: TextStyle(color: valColor, fontSize: 14, fontWeight: FontWeight.w900))]),
    );
  }
}