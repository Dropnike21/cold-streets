import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AchievementsView extends StatefulWidget {
  final Map<String, dynamic> userData;

  const AchievementsView({super.key, required this.userData});

  @override
  State<AchievementsView> createState() => _AchievementsViewState();
}

class _AchievementsViewState extends State<AchievementsView> {
  static const Color cBlack = Color(0xFF121212);
  static const Color cNeonGreen = Color(0xFF39FF14);
  static const Color cDarkGrey = Color(0xFF1E1E1E);

  String _selectedCategory = "LATEST";
  final List<String> _categories = ["LATEST", "ALL", "CRIMES", "GYM", "ECONOMY", "SYNDICATE"];

  int? _expandedAchievementId;

  List<Map<String, dynamic>> _achievements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAchievements();
  }

  Future<void> _fetchAchievements() async {
    setState(() => _isLoading = true);
    try {
      final String userId = widget.userData['user_id'].toString();
      final response = await http.get(Uri.parse('http://10.0.2.2:3000/achievements/$userId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _achievements = List<Map<String, dynamic>>.from(data['achievements']);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching achievements: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatNumber(int amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return '$amount';
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case "CRIMES": return Icons.local_fire_department;
      case "GYM": return Icons.fitness_center;
      case "ECONOMY": return Icons.attach_money;
      case "SYNDICATE": return Icons.group;
      default: return Icons.military_tech;
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredAchievements = [];

    if (_selectedCategory == "LATEST") {
      filteredAchievements = _achievements.where((ach) => ach['unlocked'] == true).toList();
      filteredAchievements.sort((a, b) {
        if (a['unlocked_at'] == null) return 1;
        if (b['unlocked_at'] == null) return -1;
        DateTime dtA = DateTime.tryParse(a['unlocked_at'].toString()) ?? DateTime.now();
        DateTime dtB = DateTime.tryParse(b['unlocked_at'].toString()) ?? DateTime.now();
        return dtB.compareTo(dtA);
      });
    } else if (_selectedCategory == "ALL") {
      filteredAchievements = List.from(_achievements);
    } else {
      filteredAchievements = _achievements.where((ach) => ach["category"] == _selectedCategory).toList();
    }

    int itemsPerRow = 5;
    List<List<Map<String, dynamic>>> chunkedRows = [];
    for (int i = 0; i < filteredAchievements.length; i += itemsPerRow) {
      chunkedRows.add(
        filteredAchievements.sublist(
          i,
          i + itemsPerRow > filteredAchievements.length ? filteredAchievements.length : i + itemsPerRow,
        ),
      );
    }

    return Scaffold(
      backgroundColor: cBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: cNeonGreen),
        title: const Text(
          'LIFETIME ACHIEVEMENTS',
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
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF333333))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: _categories.map((category) {
                  bool isSelected = _selectedCategory == category;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategory = category;
                        _expandedAchievementId = null;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8.0),
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                      decoration: BoxDecoration(
                        color: isSelected ? cNeonGreen.withValues(alpha: 0.1) : cDarkGrey,
                        border: Border.all(
                          color: isSelected ? cNeonGreen : Colors.grey.shade800,
                        ),
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      child: Text(
                        category,
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
          ),

          // --- BODY CONTENT ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: cNeonGreen))
                : chunkedRows.isEmpty
                ? Center(
              child: Text(
                _selectedCategory == "LATEST"
                    ? "NO ACHIEVEMENTS MADE YET."
                    : "NO ACHIEVEMENTS IN THIS CATEGORY.",
                style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              itemCount: chunkedRows.length,
              itemBuilder: (context, rowIndex) {
                List<Map<String, dynamic>> rowItems = chunkedRows[rowIndex];

                Map<String, dynamic>? expandedItemInThisRow;
                try {
                  expandedItemInThisRow = rowItems.firstWhere((item) => item['id'] == _expandedAchievementId);
                } catch (e) {
                  expandedItemInThisRow = null;
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: rowItems.map((ach) {
                          bool isUnlocked = ach["unlocked"];
                          bool isSelected = ach["id"] == _expandedAchievementId;

                          double cur = double.tryParse(ach["cur"].toString()) ?? 0;
                          double max = double.tryParse(ach["max"].toString()) ?? 1;
                          double progress = (cur / max).clamp(0.0, 1.0);

                          return Expanded(
                            child: Tooltip(
                              message: ach["title"].toString().toUpperCase(),
                              preferBelow: false,
                              textStyle: const TextStyle(color: cBlack, fontWeight: FontWeight.bold, fontSize: 12),
                              decoration: BoxDecoration(color: cNeonGreen, borderRadius: BorderRadius.circular(4)),
                              child: GestureDetector(
                                onTap: () {
                                  // V1.5 FIX: Do absolutely nothing if the achievement is locked
                                  if (!isUnlocked) return;

                                  setState(() {
                                    if (_expandedAchievementId == ach["id"]) {
                                      _expandedAchievementId = null;
                                    } else {
                                      _expandedAchievementId = ach["id"];
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: isSelected
                                        ? [BoxShadow(color: cNeonGreen.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 2)]
                                        : [],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(
                                        width: 54,
                                        height: 54,
                                        child: CircularProgressIndicator(
                                          value: progress,
                                          strokeWidth: 4.0,
                                          backgroundColor: Colors.grey.shade900,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            isUnlocked ? cNeonGreen : Colors.orangeAccent,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: cDarkGrey,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.grey.shade800),
                                        ),
                                        child: Icon(
                                          isUnlocked ? _getCategoryIcon(ach["category"]) : Icons.lock_outline,
                                          color: isUnlocked ? cNeonGreen : Colors.grey.shade700,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: expandedItemInThisRow != null
                          ? _buildExpandedDetails(expandedItemInThisRow)
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedDetails(Map<String, dynamic> ach) {
    // Safe parsing for text
    String titleText = ach["title"]?.toString().toUpperCase() ?? "UNKNOWN ACHIEVEMENT";
    String descText = ach["desc"]?.toString() ?? "No description available.";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: cDarkGrey,
            border: Border(
              left: const BorderSide(color: cNeonGreen, width: 4),
              top: BorderSide(color: Colors.grey.shade800),
              right: BorderSide(color: Colors.grey.shade800),
              bottom: BorderSide(color: Colors.grey.shade800),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                descText,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}