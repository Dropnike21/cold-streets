import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TradeNetworkView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final VoidCallback onBack;

  const TradeNetworkView({
    super.key,
    required this.userData,
    required this.onStateChange,
    required this.onBack,
  });

  @override
  State<TradeNetworkView> createState() => _TradeNetworkViewState();
}

class _TradeNetworkViewState extends State<TradeNetworkView> {
  bool isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageJumpController = TextEditingController();

  // 🚨 NEW NESTED FILTER STATE
  // Tracks exactly which subcategories are checked
  final Map<String, Map<String, bool>> _selectedFilters = {
    "WEAPONS": {"MELEE": true, "HANDGUNS": true, "SMG": true, "RIFLES": true},
    "GEAR": {"VESTS": true, "GLOVES": true, "TOPS": true, "MASKS": true},
    "CONSUMABLES": {"BOOSTS": true, "MEDICAL": true, "ALCOHOL": true},
    "TECH": {"HARDWARE": true, "SOFTWARE": true},
    "NARCOTICS": {"STIMULANTS": true, "DEPRESSANTS": true},
  };

  // Tracks which accordion categories are currently flipped open
  final Map<String, bool> _expandedCategories = {
    "WEAPONS": false,
    "GEAR": false,
    "CONSUMABLES": false,
    "TECH": false,
    "NARCOTICS": false,
  };

  // --- Sort State ---
  String _sortBy = "Lowest Price";
  final List<String> _sortOptions = ["Lowest Price", "Highest Price", "Newest Listings"];

  // --- Pagination State ---
  int currentPage = 1;
  final int itemsPerPage = 20;
  int totalPages = 500;

  int? expandedListingId;

  // --- Dummy Data ---
  final List<Map<String, dynamic>> dummyListings = [
    {
      "id": 101, "item_name": "Heavy Crowbar", "qty": 1, "price": 4500, "seller": "ThugLife99", "seller_id": 402,
      "category": "WEAPONS", "sub": "MELEE", "desc": "A solid iron crowbar. Good for breaking knees or crates.", "effect": "+15 Melee Damage", "base_val": 1200, "circ": "45,020"
    },
    {
      "id": 102, "item_name": "Kevlar Vest", "qty": 1, "price": 125000, "seller": "ArmorKing", "seller_id": 811,
      "category": "GEAR", "sub": "VESTS", "desc": "Standard issue police kevlar. Stops small caliber rounds.", "effect": "+40 Armor Rating", "base_val": 50000, "circ": "8,400"
    },
    {
      "id": 103, "item_name": "First Aid Kit", "qty": 5, "price": 2000, "seller": "StreetDoc", "seller_id": 15,
      "category": "CONSUMABLES", "sub": "MEDICAL", "desc": "Basic medical supplies to patch up bullet holes.", "effect": "Restores 50 HP", "base_val": 500, "circ": "120,500"
    },
    {
      "id": 104, "item_name": "Encrypted Drive", "qty": 1, "price": 850000, "seller": "ZeroDay", "seller_id": 99,
      "category": "TECH", "sub": "HARDWARE", "desc": "Contains stolen corporate data. Highly illegal.", "effect": "Used in Hacking Crimes", "base_val": 150000, "circ": "342"
    },
    {
      "id": 105, "item_name": "Rusty Machete", "qty": 1, "price": 1200, "seller": "ScrapScav", "seller_id": 551,
      "category": "WEAPONS", "sub": "MELEE", "desc": "It's dull, but the tetanus will finish the job.", "effect": "+8 Melee Damage", "base_val": 300, "circ": "89,000"
    },
  ];

  String _formatCash(int amount) {
    if (amount >= 1000000000) return '\$${(amount / 1000000000).toStringAsFixed(2)}b';
    if (amount >= 1000000) return '\$${(amount / 1000000).toStringAsFixed(2)}m';
    String formatted = amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return '\$$formatted';
  }

  void _buyItem(int listingId) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Purchase logic will go here!"), backgroundColor: Color(0xFF39FF14))
    );
  }

  void _jumpToPage(int page) {
    if (page >= 1 && page <= totalPages) {
      setState(() {
        currentPage = page;
        _pageJumpController.clear();
      });
    }
  }

  List<int> _getVisiblePages() {
    int start = currentPage - 2;
    int end = currentPage + 2;

    if (start < 1) {
      end += (1 - start);
      start = 1;
    }
    if (end > totalPages) {
      start -= (end - totalPages);
      end = totalPages;
    }
    if (start < 1) start = 1;

    return List.generate(end - start + 1, (i) => start + i);
  }

  void _openMobileFilterSheet() {
    showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A1A1A),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 16, left: 16, right: 16),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("FILTERS & SORT", style: TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                            IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                          ],
                        ),
                        const Divider(color: Colors.white24),
                        _buildFilterAndSortContent(
                            onUpdate: () {
                              setModalState(() {});
                              setState(() {});
                            }
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14), foregroundColor: Colors.black),
                            onPressed: () => Navigator.pop(context),
                            child: const Text("APPLY FILTERS", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              }
          );
        }
    );
  }

  // 🚨 THE TRISTATE LOGIC HELPER
  bool? _isMainCategoryChecked(String mainCat) {
    final subs = _selectedFilters[mainCat]!.values;
    if (subs.every((e) => e)) return true; // All checked
    if (subs.every((e) => !e)) return false; // None checked
    return null; // Indeterminate (Partially checked)
  }

  void _toggleMainCategory(String mainCat, bool? value) {
    // If it was partial (null) or false, we turn it completely true. Otherwise false.
    bool targetState = value ?? false;
    _selectedFilters[mainCat]!.updateAll((key, val) => targetState);
  }

  // 🚨 THE NEW NESTED FILTER WIDGET
  Widget _buildFilterAndSortContent({required VoidCallback onUpdate}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("CATEGORIES", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),

        Column(
          children: _selectedFilters.keys.map((String mainCat) {
            bool? mainChecked = _isMainCategoryChecked(mainCat);
            bool isExpanded = _expandedCategories[mainCat] ?? false;

            return Column(
              children: [
                Row(
                  children: [
                    // Expand/Collapse Arrow
                    IconButton(
                      icon: Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, color: Colors.white54, size: 18),
                      onPressed: () {
                        _expandedCategories[mainCat] = !isExpanded;
                        onUpdate();
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      splashRadius: 16,
                    ),
                    // Main Category Checkbox
                    Expanded(
                      child: Theme(
                        data: ThemeData(unselectedWidgetColor: Colors.white54),
                        child: CheckboxListTile(
                          title: Text(mainCat, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          value: mainChecked,
                          tristate: true, // Allows the "Dash" if partially selected
                          activeColor: const Color(0xFF39FF14), checkColor: Colors.black,
                          dense: true, contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? value) {
                            _toggleMainCategory(mainCat, value);
                            onUpdate();
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                // The Subcategories (Slide down when expanded)
                if (isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: Column(
                      children: _selectedFilters[mainCat]!.keys.map((String subCat) {
                        return Theme(
                          data: ThemeData(unselectedWidgetColor: Colors.white54),
                          child: CheckboxListTile(
                            title: Text(subCat, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                            value: _selectedFilters[mainCat]![subCat],
                            activeColor: const Color(0xFF39FF14), checkColor: Colors.black,
                            dense: true, contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (bool? value) {
                              _selectedFilters[mainCat]![subCat] = value ?? false;
                              onUpdate();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  )
              ],
            );
          }).toList(),
        ),

        const SizedBox(height: 24),
        const Divider(color: Colors.white24),
        const SizedBox(height: 12),

        const Text("SORT BY", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        Column(
          children: _sortOptions.map((String option) {
            return Theme(
              data: ThemeData(unselectedWidgetColor: Colors.white54),
              child: RadioListTile<String>(
                title: Text(option, style: const TextStyle(color: Colors.white, fontSize: 12)),
                value: option,
                groupValue: _sortBy,
                activeColor: const Color(0xFF39FF14),
                dense: true, contentPadding: EdgeInsets.zero,
                onChanged: (String? value) {
                  _sortBy = value!;
                  onUpdate();
                },
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPaginationControls(bool isTop) {
    List<int> visiblePages = _getVisiblePages();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
          bottom: isTop ? const BorderSide(color: Color(0xFF39FF14), width: 1) : BorderSide.none,
          top: !isTop ? const BorderSide(color: Color(0xFF39FF14), width: 1) : BorderSide.none,
        ),
      ),
      child: SafeArea(
        top: false, bottom: !isTop,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: currentPage > 1 ? () => _jumpToPage(currentPage - 1) : null,
                visualDensity: VisualDensity.compact,
              ),

              ...visiblePages.map((p) {
                bool isCurrent = p == currentPage;
                return GestureDetector(
                  onTap: () => _jumpToPage(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFF39FF14).withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isCurrent ? const Color(0xFF39FF14) : Colors.transparent)
                    ),
                    child: Text(
                      p.toString(),
                      style: TextStyle(
                          color: isCurrent ? const Color(0xFF39FF14) : Colors.white70,
                          fontSize: 12, fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold
                      ),
                    ),
                  ),
                );
              }),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text("of $totalPages", style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
              ),

              Container(
                width: 50,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  controller: _pageJumpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    hintText: "...",
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: Colors.black,
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(4)),
                    focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF39FF14)), borderRadius: BorderRadius.circular(4)),
                  ),
                  onSubmitted: (val) {
                    int? p = int.tryParse(val);
                    if (p != null) _jumpToPage(p);
                  },
                ),
              ),

              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: currentPage < totalPages ? () => _jumpToPage(currentPage + 1) : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 800;

          return Scaffold(
            backgroundColor: const Color(0xFF121212),
            appBar: AppBar(
              backgroundColor: Colors.black,
              elevation: 2,
              toolbarHeight: 60,
              shadowColor: const Color(0xFF39FF14).withValues(alpha: 0.5),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF39FF14)),
                onPressed: widget.onBack,
              ),
              title: Row(
                children: [
                  const Text("TRADE NETWORK", style: TextStyle(color: Color(0xFF39FF14), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const Spacer(),

                  Container(
                    width: isDesktop ? 300 : 150,
                    height: 36,
                    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(4)),
                    child: TextField(
                      controller: _searchController,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        hintText: "Search item name...", hintStyle: TextStyle(color: Colors.white30),
                        prefixIcon: Icon(Icons.search, color: Colors.white54, size: 16),
                        prefixIconConstraints: BoxConstraints(minWidth: 40, maxHeight: 36),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (val) {
                        setState(() {});
                      },
                    ),
                  ),

                  if (!isDesktop) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.tune, color: Color(0xFF39FF14)),
                      onPressed: _openMobileFilterSheet,
                      tooltip: "Filters & Sort",
                    )
                  ]
                ],
              ),
            ),

            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDesktop)
                  Container(
                    width: 280,
                    height: double.infinity,
                    color: const Color(0xFF1A1A1A),
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                        child: _buildFilterAndSortContent(
                            onUpdate: () => setState(() {})
                        )
                    ),
                  ),

                Expanded(
                  child: Column(
                    children: [
                      _buildPaginationControls(true),

                      Expanded(
                        child: isLoading
                            ? const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)))
                            : _buildMarketBoard(isDesktop),
                      ),

                      _buildPaginationControls(false),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
    );
  }

  Widget _buildMarketBoard(bool isDesktop) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: isDesktop ? 20 : 0),
      itemCount: dummyListings.length,
      itemBuilder: (context, index) {
        final item = dummyListings[index];
        final int itemId = item['id'];
        final bool isExpanded = expandedListingId == itemId;

        // 🚨 THE NEW FILTER LOGIC
        // It checks if the specific subcategory inside the main category is marked true!
        bool shouldShow = false;
        if (_selectedFilters.containsKey(item['category'])) {
          shouldShow = _selectedFilters[item['category']]![item['sub']] ?? false;
        }

        if (!shouldShow) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isExpanded) {
                expandedListingId = null;
              } else {
                expandedListingId = itemId;
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: isExpanded ? const Color(0xFF39FF14) : Colors.white12, width: isExpanded ? 1.5 : 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: Icon(Icons.image, color: Colors.white24, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(item['item_name'], style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 6),
                                Text("x${item['qty']}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.w900)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.person, color: Colors.white30, size: 10),
                                const SizedBox(width: 4),
                                Text("${item['seller']} [${item['seller_id']}]", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatCash(item['price']), style: const TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 24, width: 60,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1),
                                foregroundColor: const Color(0xFF39FF14),
                                side: const BorderSide(color: Color(0xFF39FF14)),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () => _buyItem(itemId),
                              child: const Text("BUY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                if (isExpanded)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF121212),
                      border: Border(top: BorderSide(color: Colors.white12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("EFFECT: ${item['effect']}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(item['desc'], style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildMiniStat("BASE VALUE", _formatCash(item['base_val'])),
                            _buildMiniStat("CIRCULATION", item['circ']),
                            _buildMiniStat("TYPE", "${item['category']} / ${item['sub']}"),
                          ],
                        )
                      ],
                    ),
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white30, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}