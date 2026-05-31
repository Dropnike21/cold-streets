// File Path: lib/views/market_view.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api_config.dart';

class MarketView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const MarketView({super.key, required this.userData, required this.onStateChange});

  @override
  State<MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<MarketView> {
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;

  String _selectedCategory = "ALL";
  // V1.6: Upgraded to a Set to allow multiple active filters simultaneously
  Set<String> _activeFilters = {};

  final TextEditingController _searchController = TextEditingController();

  List<String> _dynamicCategories = ["ALL"];
  Map<String, List<String>> _dynamicSubCategories = {};

  final String apiUrl = "${ApiConfig.baseUrl}/market";
  bool _isLoading = true;
  List<dynamic> _allItems = [];
  List<dynamic> _filteredItems = [];

  final Map<int, int> _cart = {};

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
    });
    _searchController.addListener(_applyFilters);
    _fetchMarket();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toUpperCase()) {
      case "WEAPONS": return Icons.hardware;
      case "GEAR": return Icons.shield;
      case "TECH": return Icons.memory;
      case "CONSUMABLES": return Icons.medical_services;
      case "ALL": return Icons.apps;
      default: return Icons.category;
    }
  }

  void _extractCategories() {
    Set<String> mains = {"ALL"};
    Map<String, Set<String>> subs = {};

    for (var item in _allItems) {
      String cat = item['category']?.toString().toUpperCase() ?? "UNKNOWN";
      String sub = item['sub_category']?.toString().toUpperCase() ?? "";

      mains.add(cat);
      if (!subs.containsKey(cat)) {
        subs[cat] = {"ALL"};
      }
      if (sub.isNotEmpty && sub != "NULL") {
        subs[cat]!.add(sub);
      }
    }

    _dynamicCategories = mains.toList();
    _dynamicSubCategories = subs.map((key, value) => MapEntry(key, value.toList()));
  }

  // V1.6: Instead of a raw string, we return a Map so the UI can format it cleanly
  Map<String, dynamic> _getEffectsMap(dynamic item) {
    final effects = item['effects'];
    if (effects == null || (effects is Map && effects.isEmpty)) return {};
    if (effects is Map) return Map<String, dynamic>.from(effects);
    return {};
  }

  Future<void> _fetchMarket() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/list'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _allItems = jsonDecode(response.body);
            _extractCategories();
            _isLoading = false;
            _cart.clear();
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

        String subCat = item['sub_category']?.toString().toUpperCase() ?? "";

        // V1.6 FIX: Check if the item's sub-category is in the active filters set
        bool matchesSub = _activeFilters.isEmpty || _activeFilters.contains(subCat);

        return matchesSearch && matchesMain && matchesSub;
      }).toList();
    });
  }

  void _updateCart(int itemId, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _cart.remove(itemId);
      } else {
        _cart[itemId] = quantity;
      }
    });
  }

  int get _cartTotal {
    int total = 0;
    for (var item in _allItems) {
      int id = item['item_id'];
      if (_cart.containsKey(id)) {
        total += (int.tryParse(item['base_value'].toString()) ?? 0) * _cart[id]!;
      }
    }
    return total;
  }

  int _getMaxAllowed(Map<String, dynamic> currentItem) {
    int itemId = currentItem['item_id'];
    int itemPrice = int.tryParse(currentItem['base_value'].toString()) ?? 0;
    int currentStock = currentItem['stock'] ?? 0;

    int costOfOtherItems = 0;
    _cart.forEach((id, qty) {
      if (id != itemId) {
        final otherItem = _allItems.firstWhere((e) => e['item_id'] == id, orElse: () => null);
        if (otherItem != null) {
          costOfOtherItems += (int.tryParse(otherItem['base_value'].toString()) ?? 0) * qty;
        }
      }
    });

    int remainingCash = widget.userData['dirty_cash'] - costOfOtherItems;
    if (remainingCash < 0) remainingCash = 0;

    int affordableQty = itemPrice > 0 ? remainingCash ~/ itemPrice : currentStock;
    return affordableQty < currentStock ? affordableQty : currentStock;
  }

  Future<void> _processPurchase({Map<String, dynamic>? singleItem, int? singleQty}) async {
    List<Map<String, dynamic>> payloadCart = [];
    int expectedCost = 0;

    if (singleItem != null && singleQty != null) {
      payloadCart.add({"item_id": singleItem['item_id'], "quantity": singleQty});
      expectedCost = (int.tryParse(singleItem['base_value'].toString()) ?? 0) * singleQty;
    } else {
      _cart.forEach((itemId, qty) {
        payloadCart.add({"item_id": itemId, "quantity": qty});
      });
      expectedCost = _cartTotal;
    }

    if (payloadCart.isEmpty) return;

    if (widget.userData['dirty_cash'] < expectedCost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Not enough Dirty Cash!"), backgroundColor: Colors.orangeAccent));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))),
    );

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/buy-bulk'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.userData['user_id'],
          "cart": payloadCart
        }),
      );

      if (!mounted) return;
      Navigator.pop(context);

      final result = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (result['user'] != null) widget.onStateChange(result['user']);
        _fetchMarket();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']), backgroundColor: Colors.greenAccent));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error'] ?? "Purchase failed."), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection lost."), backgroundColor: Colors.redAccent));
    }
  }

  // V1.6: The new mobile Bottom Sheet for filtering
  void _showMobileFilterMenu(BuildContext context) {
    List<String> availableSubs = _dynamicSubCategories[_selectedCategory] ?? [];
    if (availableSubs.isEmpty || (availableSubs.length == 1 && availableSubs.first == "ALL")) return;

    showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E1E1E),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setSheetState) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("FILTER BY TYPE", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFF333333), height: 1),
                      Expanded(
                        child: ListView.builder(
                          itemCount: availableSubs.length,
                          itemBuilder: (context, index) {
                            String sub = availableSubs[index];
                            if (sub == "ALL") return const SizedBox.shrink(); // Skip 'ALL' in checkboxes

                            bool isChecked = _activeFilters.contains(sub);
                            return CheckboxListTile(
                              title: Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                              value: isChecked,
                              activeColor: const Color(0xFF39FF14),
                              checkColor: Colors.black,
                              side: const BorderSide(color: Color(0xFF333333)),
                              onChanged: (bool? value) {
                                setSheetState(() {
                                  if (value == true) {
                                    _activeFilters.add(sub);
                                  } else {
                                    _activeFilters.remove(sub);
                                  }
                                });
                                setState(() => _applyFilters()); // Update main UI
                              },
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14)),
                          onPressed: () => Navigator.pop(context),
                          child: const Text("APPLY FILTERS", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                );
              }
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    bool hasItemsInCart = _cartTotal > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 800;

        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- DESKTOP NAVIGATION RAIL ---
                  if (isDesktop) ...[
                    NavigationRail(
                      backgroundColor: const Color(0xFF121212),
                      indicatorColor: const Color(0xFF39FF14).withValues(alpha: 0.2),
                      selectedLabelTextStyle: const TextStyle(color: Color(0xFF39FF14), fontSize: 11, fontWeight: FontWeight.bold),
                      unselectedLabelTextStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                      selectedIconTheme: const IconThemeData(color: Color(0xFF39FF14)),
                      unselectedIconTheme: const IconThemeData(color: Colors.white54),
                      selectedIndex: _dynamicCategories.indexOf(_selectedCategory).clamp(0, _dynamicCategories.length),
                      onDestinationSelected: (int index) {
                        setState(() {
                          _selectedCategory = _dynamicCategories[index];
                          _activeFilters.clear(); // Reset filters when changing main category
                          _applyFilters();
                        });
                      },
                      labelType: NavigationRailLabelType.all,
                      destinations: _dynamicCategories.map((cat) {
                        return NavigationRailDestination(
                          icon: Icon(_getCategoryIcon(cat)),
                          label: Text(cat),
                        );
                      }).toList(),
                    ),
                    const VerticalDivider(thickness: 1, width: 1, color: Color(0xFF333333)),
                  ],

                  // --- MAIN INVENTORY AREA ---
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Mobile Main Categories
                              if (!isDesktop) ...[
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _dynamicCategories.map((cat) => _buildMainCategoryChip(cat)).toList(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],

                              // Search Bar & Mobile Filter Icon Row
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
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
                                          hintText: "SEARCH DATABASE...",
                                          hintStyle: TextStyle(color: Colors.white24, fontSize: 10),
                                          prefixIcon: Icon(Icons.search, size: 16, color: Colors.white54),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Mobile Filter Menu Trigger
                                  if (!isDesktop && _selectedCategory != "ALL") ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      height: 36,
                                      width: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1A1A1A),
                                        border: Border.all(color: const Color(0xFF333333)),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.tune, color: Colors.white54, size: 18),
                                        onPressed: () => _showMobileFilterMenu(context),
                                      ),
                                    )
                                  ]
                                ],
                              ),

                              // Active Filters Display (Appears at the top if any filters are checked)
                              if (_activeFilters.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 8.0,
                                  children: _activeFilters.map((filter) {
                                    return InputChip(
                                      label: Text(filter, style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                                      backgroundColor: const Color(0xFF39FF14),
                                      deleteIconColor: Colors.black,
                                      onDeleted: () {
                                        setState(() {
                                          _activeFilters.remove(filter);
                                          _applyFilters();
                                        });
                                      },
                                    );
                                  }).toList(),
                                )
                              ],

                              // Desktop Sub Categories (Wrap style, multi-select support added)
                              if (isDesktop && _selectedCategory != "ALL" && _dynamicSubCategories.containsKey(_selectedCategory)) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Divider(color: Color(0xFF333333), height: 1),
                                ),
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 8.0,
                                  children: _dynamicSubCategories[_selectedCategory]!.where((sub) => sub != "ALL").map((sub) => _buildDesktopSubChip(sub)).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(color: Color(0xFF333333), height: 1),

                        Expanded(
                          child: GestureDetector(
                            onTap: () => FocusScope.of(context).unfocus(),
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)))
                                : _filteredItems.isEmpty
                                ? const Center(child: Text("NO ITEMS FOUND.", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)))
                                : GridView.builder(
                              padding: EdgeInsets.only(top: 10, left: 10, right: 10, bottom: hasItemsInCart ? 80 : 10),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 450,
                                mainAxisExtent: 110,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = _filteredItems[index];
                                final itemId = item['item_id'];
                                final currentQty = _cart[itemId] ?? 0;
                                final maxAllowed = _getMaxAllowed(item);

                                return _MarketItemCard(
                                  itemData: item,
                                  currentQuantity: currentQty,
                                  maxAllowed: maxAllowed,
                                  onQuantityChanged: (newQty) => _updateCart(itemId, newQty),
                                  onBuy: () => _processPurchase(singleItem: item, singleQty: currentQty),
                                  effectsMap: _getEffectsMap(item),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (hasItemsInCart)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  border: Border(top: BorderSide(color: Color(0xFF39FF14), width: 1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("TOTAL COST", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                        Text("\$$_cartTotal", style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _processPurchase(),
                      icon: const Icon(Icons.shopping_cart_checkout, size: 16, color: Colors.black),
                      label: const Text("BUY CART", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF39FF14),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    )
                  ],
                ),
              )
          ],
        );
      },
    );
  }

  Widget _buildMainCategoryChip(String label) {
    bool isSelected = _selectedCategory == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = label;
          _activeFilters.clear();
          _applyFilters();
        });
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

  Widget _buildDesktopSubChip(String label) {
    bool isSelected = _activeFilters.contains(label);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _activeFilters.remove(label);
          } else {
            _activeFilters.add(label);
          }
          _applyFilters();
        });
      },
      child: Container(
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

class _MarketItemCard extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final int currentQuantity;
  final int maxAllowed;
  final Function(int) onQuantityChanged;
  final VoidCallback onBuy;
  final Map<String, dynamic> effectsMap; // V1.6 Changed to Raw Map

  const _MarketItemCard({
    required this.itemData,
    required this.currentQuantity,
    required this.maxAllowed,
    required this.onQuantityChanged,
    required this.onBuy,
    required this.effectsMap,
  });

  @override
  State<_MarketItemCard> createState() => _MarketItemCardState();
}

class _MarketItemCardState extends State<_MarketItemCard> {
  late TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: widget.currentQuantity.toString());
  }

  @override
  void didUpdateWidget(covariant _MarketItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentQuantity != oldWidget.currentQuantity || widget.maxAllowed != oldWidget.maxAllowed) {
      if (_qtyController.text != widget.currentQuantity.toString()) {
        _qtyController.text = widget.currentQuantity.toString();
      }
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  // V1.6: The Custom Stat Renderer. Parses specific keys into a beautiful grid.
  Widget _buildStatBlock() {
    if (widget.effectsMap.isEmpty) return const SizedBox.shrink();

    List<Widget> rows = [];

    widget.effectsMap.forEach((key, value) {
      // Ignore nulls or zeros so the UI stays clean
      if (value == null || value == 0 || value == "0") return;

      // Clean the key (e.g., "ranged_damage" -> "RANGED DAMAGE")
      String cleanKey = key.replaceAll('_', ' ').toUpperCase();
      String displayValue = value.toString().toUpperCase();

      // RPG formatting touches
      if (cleanKey.contains("DAMAGE")) displayValue = "$displayValue DMG";
      if (cleanKey.contains("MITIGATION") || cleanKey.contains("ACCURACY")) displayValue = "$displayValue%";

      rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(cleanKey, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                Text(displayValue, style: const TextStyle(color: Color(0xFF39FF14), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          )
      );
    });

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0xFF333333), height: 16),
        const Text("STATISTICS", style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    int currentStock = widget.itemData['stock'] ?? 0;
    bool isOutOfStock = currentStock <= 0;

    int basePrice = int.tryParse(widget.itemData['base_value'].toString()) ?? 0;
    int totalPrice = widget.currentQuantity * basePrice;
    int circulation = int.tryParse(widget.itemData['circulation']?.toString() ?? '0') ?? 0;

    String name = widget.itemData['name'].toString().toUpperCase();
    String type = widget.itemData['category'].toString().toUpperCase();
    String desc = widget.itemData['description']?.toString() ?? "No description available.";

    bool canBuy = !isOutOfStock && widget.currentQuantity > 0;

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: Color(0xFF333333))),
            title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 12),

                  // V1.6: Injecting the new dynamic stat block
                  _buildStatBlock(),

                  const Divider(color: Color(0xFF333333), height: 16),
                  Text("VALUE: \$$basePrice", style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text("CIRCULATION: $circulation", style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text("TYPE: $type", style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CLOSE", style: TextStyle(color: Colors.white54)),
              )
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border(left: BorderSide(
              color: isOutOfStock ? Colors.redAccent.withValues(alpha: 0.5) : const Color(0xFF333333),
              width: 3
          )),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(isOutOfStock ? "OUT OF STOCK" : "STOCK: $currentStock",
                          style: TextStyle(color: isOutOfStock ? Colors.redAccent : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Text("\$$basePrice", style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 38,
                  height: 24,
                  child: TextField(
                    controller: _qtyController,
                    enabled: !isOutOfStock,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: Color(0xFF121212),
                      border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF333333))),
                    ),
                    onChanged: (val) {
                      int parsed = int.tryParse(val) ?? 0;
                      if (parsed > widget.maxAllowed) {
                        parsed = widget.maxAllowed;
                        _qtyController.text = parsed.toString();
                        _qtyController.selection = TextSelection.fromPosition(TextPosition(offset: _qtyController.text.length));
                      }
                      widget.onQuantityChanged(parsed);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: canBuy ? widget.onBuy : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canBuy ? const Color(0xFF39FF14).withValues(alpha: 0.1) : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      side: BorderSide(color: canBuy ? const Color(0xFF39FF14) : Colors.white12),
                    ),
                    child: Text("BUY",
                        style: TextStyle(color: canBuy ? const Color(0xFF39FF14) : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}