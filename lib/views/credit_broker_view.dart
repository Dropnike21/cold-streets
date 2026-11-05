import 'package:flutter/material.dart';
import '../services/game_http.dart' as http;
import 'dart:convert';

import '../api_config.dart';

class CreditBrokerView extends StatefulWidget {
  final Map<String, dynamic> userData;

  const CreditBrokerView({super.key, required this.userData});

  @override
  State<CreditBrokerView> createState() => _CreditBrokerViewState();
}

class _CreditBrokerViewState extends State<CreditBrokerView> {
  static const Color cBlack = Color(0xFF121212);
  static const Color cNeonGreen = Color(0xFF39FF14);
  static const Color cDarkGrey = Color(0xFF1E1E1E);

  bool _isLoading = true;
  List<dynamic> _upgrades = [];
  int _currentCreds = 0;
  bool _purchaseAvailable = false;
  String _brokerStatus = "catalog_only";
  String _selectedCategory = "Player";

  @override
  void initState() {
    super.initState();
    _currentCreds = int.tryParse(widget.userData['cred']?.toString() ?? "0") ?? 0;
    _fetchUpgrades();
  }

  Future<void> _fetchUpgrades() async {
    setState(() => _isLoading = true);
    try {
      final String userId = widget.userData['user_id'].toString();
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/credit-broker/$userId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _upgrades = data['upgrades'];
            _currentCreds =
                int.tryParse(data['cred']?.toString() ?? "0") ?? _currentCreds;
            _purchaseAvailable = data['purchase_available'] == true;
            _brokerStatus = data['broker_status']?.toString() ?? "catalog_only";
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching broker data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUpgrades = _upgrades.where((u) => u['category'] == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: cBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: cNeonGreen),
        title: const Text(
          'THE CREDIT BROKER',
          style: TextStyle(
            color: cNeonGreen,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        elevation: 1,
        shadowColor: cNeonGreen.withValues(alpha: 0.5),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.diamond, color: Colors.cyanAccent, size: 16),
                const SizedBox(width: 6),
                Text(
                  "AVAILABLE CREDS: $_currentCreds",
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (!_purchaseAvailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                border: const Border(
                  bottom: BorderSide(color: Colors.amber, width: 1),
                ),
              ),
              child: Text(
                _brokerStatus == "catalog_only"
                    ? "CATALOG ONLY — Cred earning, pricing, and upgrade effects are under source reconciliation. Purchases are paused."
                    : "CREDIT BROKER PURCHASES ARE CURRENTLY PAUSED.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF333333))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ["Player", "Combat", "Weapon"].map((category) {
                bool isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = category),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: isSelected ? cNeonGreen.withValues(alpha: 0.1) : cDarkGrey,
                      border: Border.all(
                        color: isSelected ? cNeonGreen : Colors.grey.shade800,
                      ),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? cNeonGreen : Colors.grey.shade500,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: cNeonGreen))
                : filteredUpgrades.isEmpty
                ? Center(
              child: Text(
                "NO DATA AVAILABLE.",
                style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              itemCount: filteredUpgrades.length,
              itemBuilder: (context, index) {
                final upg = filteredUpgrades[index];
                final bool isMaxed = upg['is_maxed'] == true;
                final bool itemPurchaseAvailable =
                    _purchaseAvailable && upg['purchase_available'] == true;
                final int level = upg['level'];
                final int maxLevel = upg['max_level'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: const BoxDecoration(
                    color: Colors.transparent, // Removed background padding feel
                    border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0), // Padding only at bottom for separation
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                upg['title'].toString().toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "Cur: +${upg['current_bonus']}${upg['suffix'] ?? ''}",
                                  style: TextStyle(color: isMaxed ? Colors.amber : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                if (!isMaxed)
                                  Text(
                                    "Nxt: +${upg['next_bonus']}${upg['suffix'] ?? ''}",
                                    style: const TextStyle(color: cNeonGreen, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          upg['description'],
                          style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4), // Higher visibility white
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                children: List.generate(maxLevel, (i) {
                                  bool isFilled = i < level;
                                  return Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 3.0),
                                      height: 6, // Slightly slimmer bar
                                      decoration: BoxDecoration(
                                        color: isFilled ? cNeonGreen : Colors.grey.shade900,
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (!isMaxed)
                              Container(
                                height: 28,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: itemPurchaseAvailable
                                      ? cNeonGreen.withValues(alpha: 0.1)
                                      : Colors.grey.shade900,
                                  border: Border.all(
                                    color: itemPurchaseAvailable
                                        ? cNeonGreen
                                        : Colors.grey.shade800,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  itemPurchaseAvailable ? "AVAILABLE" : "PURCHASE PAUSED",
                                  style: TextStyle(
                                    color: itemPurchaseAvailable
                                        ? cNeonGreen
                                        : Colors.grey.shade600,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else
                              const Text(
                                "MAXED",
                                style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}