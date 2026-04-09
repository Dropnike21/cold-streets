import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class InventoryView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const InventoryView({super.key, required this.userData, required this.onStateChange});

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  final String apiUrl = "http://10.0.2.2:3000/inventory";
  bool _isLoading = true;

  List<dynamic> _allItems = [];
  List<dynamic> _filteredItems = [];

  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;
  String _selectedCategory = "ALL";
  String _selectedSubCategory = "ALL";
  final TextEditingController _searchController = TextEditingController();

  final List<String> _mainCategories = ["ALL", "WEAPONS", "GEAR", "CONSUMABLES", "TECH"];
  final Map<String, List<String>> _subCategories = {
    "WEAPONS": ["ALL", "MELEE", "HANDGUNS", "SMG"],
    "GEAR": ["ALL", "VESTS", "GLOVES", "TOPS"],
    "TECH": ["ALL", "HARDWARE", "SOFTWARE"],
    "CONSUMABLES": ["ALL", "BOOSTS", "MEDICAL"],
  };

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
    });
    _searchController.addListener(_applyFilters);
    _fetchInventory();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchInventory() async {
    try {
      final String userId = widget.userData['user_id'].toString();
      final response = await http.get(Uri.parse('$apiUrl/$userId'));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _allItems = jsonDecode(response.body);
            _isLoading = false;
            _applyFilters();
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _allItems.where((item) {
        bool matchesSearch = item['name'].toString().toLowerCase().contains(query);
        bool matchesMain = _selectedCategory == "ALL" || item['category'].toString().toUpperCase() == _selectedCategory;
        bool matchesSub = _selectedSubCategory == "ALL" || item['stat_modifier'].toString().toUpperCase().contains(_selectedSubCategory);
        return matchesSearch && matchesMain && matchesSub;
      }).toList();
    });
  }

  Future<void> _useItem(Map<String, dynamic> item) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))),
    );

    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:3000/inventory/use'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userData['user_id'], "item_id": item['item_id']}),
      );

      if (!mounted) return;
      Navigator.pop(context);

      final result = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (result['user'] != null) widget.onStateChange(result['user']);
        _fetchInventory();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']), backgroundColor: Colors.greenAccent));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error'] ?? "Failed to use item."), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection lost."), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      children: [
        // --- SEARCH & CATEGORY BAR ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: _mainCategories.map((cat) => _buildChip(cat, true)).toList()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutQuad,
                    width: _isSearchFocused ? screenWidth * 0.45 : 36,
                    height: 36,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      border: Border.all(color: _isSearchFocused ? const Color(0xFF39FF14) : const Color(0xFF333333)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: TextField(
                      focusNode: _searchFocusNode,
                      controller: _searchController,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(color: Color(0xFF39FF14), fontSize: 12),
                      cursorColor: const Color(0xFF39FF14),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: "SEARCH",
                        hintStyle: TextStyle(color: Colors.white24, fontSize: 10),
                        prefixIcon: Icon(Icons.search, size: 16, color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedCategory != "ALL" && _subCategories.containsKey(_selectedCategory)) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _subCategories[_selectedCategory]!.map((sub) => _buildChip(sub, false)).toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(color: Color(0xFF333333), height: 1),

        // --- INVENTORY LIST ---
        Expanded(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)))
                : _filteredItems.isEmpty
                ? const Center(child: Text("YOUR STASH IS EMPTY.", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)))
                : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                return _InventoryItemCard(
                  itemData: _filteredItems[index],
                  onUse: () => _useItem(_filteredItems[index]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, bool isMain) {
    bool isSelected = isMain ? (_selectedCategory == label) : (_selectedSubCategory == label);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isMain) {
            _selectedCategory = label;
            _selectedSubCategory = "ALL";
          } else {
            _selectedSubCategory = label;
          }
          _applyFilters();
        });
        FocusScope.of(context).unfocus();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF39FF14).withValues(alpha: 0.1) : const Color(0xFF1E1E1E),
          border: Border.all(color: isSelected ? const Color(0xFF39FF14) : const Color(0xFF333333)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? const Color(0xFF39FF14) : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _InventoryItemCard extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final VoidCallback onUse;

  const _InventoryItemCard({
    required this.itemData,
    required this.onUse,
  });

  @override
  State<_InventoryItemCard> createState() => _InventoryItemCardState();
}

class _InventoryItemCardState extends State<_InventoryItemCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    int quantity = widget.itemData['quantity'] ?? 0;

    // 🔥 THE FIXES: Read the dynamic Street Value, and safely parse Circulation!
    // FIXED: Safely parses the PostgreSQL NUMERIC string into a Dart integer
    int streetValue = int.tryParse(widget.itemData['current_value']?.toString() ?? widget.itemData['base_value']?.toString() ?? '0') ?? 0;
    int circulation = int.tryParse(widget.itemData['circulation']?.toString() ?? '0') ?? 0;

    String name = widget.itemData['name'].toString().toUpperCase();
    String type = widget.itemData['category'].toString().toUpperCase();
    String stat = widget.itemData['stat_modifier']?.toString().toUpperCase() ?? "NONE";
    String desc = widget.itemData['description']?.toString() ?? "No description available.";

    bool isConsumable = type == 'CONSUMABLES';

    return GestureDetector(
      onTap: () {
        setState(() => _isExpanded = !_isExpanded);
        FocusScope.of(context).unfocus();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border(left: BorderSide(
              color: _isExpanded ? const Color(0xFF39FF14) : const Color(0xFF333333),
              width: 3
          )),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text("OWNED: $quantity", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (isConsumable)
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: widget.onUse,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        side: const BorderSide(color: Color(0xFF39FF14)),
                      ),
                      child: const Text("USE", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  )
                else
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Equipping gear coming soon.")));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        side: const BorderSide(color: Colors.blueAccent),
                      ),
                      child: const Text("EQUIP", style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  )
              ],
            ),

            if (_isExpanded) ...[
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF333333), height: 1),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text("EFFECT: $stat", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 🔥 RENAMED TO STREET VALUE
                  Text("STREET VALUE: \$$streetValue", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("CIRCULATION: $circulation", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("TYPE: $type", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Black Market Fence coming soon.")));
                      },
                      icon: const Icon(Icons.attach_money, size: 14, color: Colors.orangeAccent),
                      label: const Text("SELL", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent.withValues(alpha: 0.1),
                        side: const BorderSide(color: Colors.orangeAccent),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: "Syndicate Trading coming soon",
                      triggerMode: TooltipTriggerMode.tap,
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.swap_horiz, size: 14, color: Colors.white24),
                        label: const Text("TRADE", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: const BorderSide(color: Colors.white12),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }
}