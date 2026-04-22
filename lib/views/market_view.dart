import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  String _selectedSubCategory = "ALL";
  final TextEditingController _searchController = TextEditingController();

  final List<String> _mainCategories = ["ALL", "WEAPONS", "GEAR", "CONSUMABLES", "TECH"];
  final Map<String, List<String>> _subCategories = {
    "WEAPONS": ["ALL", "MELEE", "HANDGUNS", "SMG"],
    "GEAR": ["ALL", "VESTS", "GLOVES", "TOPS"],
    "TECH": ["ALL", "HARDWARE", "SOFTWARE"],
    "CONSUMABLES": ["ALL", "BOOSTS", "MEDICAL"],
  };

  final String apiUrl = "http://10.0.2.2:3000/market";
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

  Future<void> _fetchMarket() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/list'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _allItems = jsonDecode(response.body);
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
        bool matchesSub = _selectedSubCategory == "ALL" || item['stat_modifier'].toString().toUpperCase().contains(_selectedSubCategory);
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
        total += (item['base_value'] as int) * _cart[id]!;
      }
    }
    return total;
  }

  // 🔥 Dynamic Ceiling Algorithm
  int _getMaxAllowed(Map<String, dynamic> currentItem) {
    int itemId = currentItem['item_id'];
    int itemPrice = currentItem['base_value'];
    int currentStock = currentItem['stock'] ?? 0;

    int costOfOtherItems = 0;
    _cart.forEach((id, qty) {
      if (id != itemId) {
        final otherItem = _allItems.firstWhere((e) => e['item_id'] == id, orElse: () => null);
        if (otherItem != null) {
          costOfOtherItems += (otherItem['base_value'] as int) * qty;
        }
      }
    });

    int remainingCash = widget.userData['dirty_cash'] - costOfOtherItems;
    if (remainingCash < 0) remainingCash = 0; // Failsafe

    // Prevent divide by zero error if base_value is ever 0
    int affordableQty = itemPrice > 0 ? remainingCash ~/ itemPrice : currentStock;

    // Return whichever is smaller: what they can afford, or what is actually in stock
    return affordableQty < currentStock ? affordableQty : currentStock;
  }

  Future<void> _processPurchase({Map<String, dynamic>? singleItem, int? singleQty}) async {
    List<Map<String, dynamic>> payloadCart = [];
    int expectedCost = 0;

    if (singleItem != null && singleQty != null) {
      payloadCart.add({"item_id": singleItem['item_id'], "quantity": singleQty});
      expectedCost = singleItem['base_value'] * singleQty;
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    bool hasItemsInCart = _cartTotal > 0;

    return Column(
      children: [
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

        Expanded(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)))
                : _filteredItems.isEmpty
                ? const Center(child: Text("NO ITEMS FOUND.", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)))
                : ListView.builder(
              padding: EdgeInsets.only(top: 10, left: 10, right: 10, bottom: hasItemsInCart ? 80 : 10),
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
                );
              },
            ),
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

class _MarketItemCard extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final int currentQuantity;
  final int maxAllowed;
  final Function(int) onQuantityChanged;
  final VoidCallback onBuy;

  const _MarketItemCard({
    required this.itemData,
    required this.currentQuantity,
    required this.maxAllowed,
    required this.onQuantityChanged,
    required this.onBuy,
  });

  @override
  State<_MarketItemCard> createState() => _MarketItemCardState();
}

class _MarketItemCardState extends State<_MarketItemCard> {
  bool _isExpanded = false;
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

  @override
  Widget build(BuildContext context) {
    int currentStock = widget.itemData['stock'] ?? 0;
    bool isOutOfStock = currentStock <= 0;
    int basePrice = widget.itemData['base_value'] as int;
    int totalPrice = widget.currentQuantity * basePrice;

    // FIXED: Safely parses the PostgreSQL BigInt string into a Dart integer
    int circulation = int.tryParse(widget.itemData['circulation']?.toString() ?? '0') ?? 0;

    String name = widget.itemData['name'].toString().toUpperCase();
    String type = widget.itemData['category'].toString().toUpperCase();
    String stat = widget.itemData['stat_modifier']?.toString().toUpperCase() ?? "NONE";
    String desc = widget.itemData['description']?.toString() ?? "No description available.";

    bool canBuy = !isOutOfStock && widget.currentQuantity > 0;

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
              color: isOutOfStock ? Colors.redAccent.withValues(alpha: 0.5) : (_isExpanded ? const Color(0xFF39FF14) : const Color(0xFF333333)),
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
                      Text(isOutOfStock ? "OUT OF STOCK" : "STOCK: $currentStock",
                          style: TextStyle(color: isOutOfStock ? Colors.redAccent : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text("\$$basePrice", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    const SizedBox(width: 8),
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
                        child: Text("BUY \$$totalPrice",
                            style: TextStyle(color: canBuy ? const Color(0xFF39FF14) : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
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
                  Text("VALUE: \$$basePrice", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("CIRCULATION: $circulation", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("TYPE: $type", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}