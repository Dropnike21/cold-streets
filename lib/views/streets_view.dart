import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api_config.dart';

// --- ADDED THIS IMPORT ---
import 'crimes_search_view.dart';

class StreetsView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final Function(int) onNavigate;

  const StreetsView({super.key, required this.userData, required this.onStateChange, required this.onNavigate});

  @override
  State<StreetsView> createState() => _StreetsViewState();
}

class _StreetsViewState extends State<StreetsView> {
  final String crimesApiUrl = "${ApiConfig.baseUrl}/crimes";

  bool _isLoading = true;
  List<MapEntry<String, List<dynamic>>> _sortedCategories = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    await _fetchJobBoard();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchJobBoard() async {
    try {
      final response = await http.get(Uri.parse('$crimesApiUrl/list'));
      if (response.statusCode == 200) {
        final List<dynamic> crimesData = jsonDecode(response.body);

        Map<String, List<dynamic>> tempGroup = {};
        for (var crime in crimesData) {
          String subCategory = crime['sub_category'] ?? "General";

          if (!tempGroup.containsKey(subCategory)) {
            tempGroup[subCategory] = [];
          }
          tempGroup[subCategory]!.add(crime);
        }

        var sortedList = tempGroup.entries.toList();
        sortedList.sort((a, b) {
          int getLowestId(List<dynamic> group) {
            return group.map((c) => (c['id'] as num).toInt()).reduce((curr, next) => curr < next ? curr : next);
          }

          int lowestIdA = getLowestId(a.value);
          int lowestIdB = getLowestId(b.value);

          return lowestIdA.compareTo(lowestIdB);
        });

        if (mounted) {
          setState(() {
            _sortedCategories = sortedList;
          });
        }
      }
    } catch (e) {
      debugPrint("Fetch Crimes Error: $e");
    }
  }

  void _openSubCategoryMechanics(String subCategoryName, List<dynamic> crimesList) {
    debugPrint("Clicked Category: $subCategoryName");

    if (subCategoryName.toLowerCase() == 'searching') {
      // We no longer push a new screen. We tell MainHub to load index 26!
      widget.onNavigate(26);
    } else if (subCategoryName.toLowerCase() == 'shoplifting') {
      // We no longer push a new screen. We tell MainHub to load index 26!
      widget.onNavigate(27);
    }  else if (subCategoryName.toLowerCase() == 'pickpocketing') {
      // We no longer push a new screen. We tell MainHub to load index 26!
      widget.onNavigate(28);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mechanics for $subCategoryName are currently under construction.', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF39FF14),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)));
    if (_sortedCategories.isEmpty) return const Center(child: Text("The streets are quiet...", style: TextStyle(color: Colors.white54)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.3)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("THE STREETS", style: TextStyle(color: Color(0xFF39FF14), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              SizedBox(height: 4),
              Text("Select an operation and hit the streets.", style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 500,
              mainAxisExtent: 140,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _sortedCategories.length,
            itemBuilder: (context, index) {
              String subCatName = _sortedCategories[index].key;
              List<dynamic> jobsInside = _sortedCategories[index].value;

              return _buildImageCard(subCatName, jobsInside);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImageCard(String title, List<dynamic> jobsList) {
    return InkWell(
      onTap: () => _openSubCategoryMechanics(title, jobsList),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFF222222),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Stack(
          children: [
            const Positioned(
              right: -20,
              bottom: -20,
              child: Icon(Icons.local_police_outlined, size: 100, color: Colors.white10),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.black.withOpacity(0.1),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}