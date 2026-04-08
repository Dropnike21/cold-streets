import 'package:flutter/material.dart';

class MarketView extends StatefulWidget {
  const MarketView({super.key});

  @override
  State<MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<MarketView> {
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;
  String _selectedCategory = "ALL";
  String _selectedSubCategory = "ALL";

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
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

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
                      child: Row(
                        children: _mainCategories.map((cat) => _buildChip(cat, true)).toList(),
                      ),
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
                      border: Border.all(
                        color: _isSearchFocused ? const Color(0xFF39FF14) : const Color(0xFF333333),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: TextField(
                      focusNode: _searchFocusNode,
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
                      children: _subCategories[_selectedCategory]!
                          .map((sub) => _buildChip(sub, false))
                          .toList(),
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
            child: ListView(
              padding: const EdgeInsets.all(10.0),
              children: const [
                _MarketItemCard(
                  name: "BRASS KNUCKLES",
                  type: "MELEE",
                  stat: "+15% STRENGTH",
                  basePrice: 250,
                  stock: 14,
                  circulation: 12450,
                  description: "Standard issue street diplomacy.",
                ),
                _MarketItemCard(
                  name: "9MM GLOCK",
                  type: "HANDGUN",
                  stat: "12 DMG",
                  basePrice: 600,
                  stock: 5,
                  circulation: 8500,
                  description: "Reliable, cheap, and loud. The street standard.",
                  ammoType: "9mm",
                  costPerRound: 2,
                ),
                _MarketItemCard(
                  name: "KEVLAR VEST",
                  type: "VESTS",
                  stat: "+25% DEFENSE",
                  basePrice: 1200,
                  stock: 3,
                  circulation: 430,
                  description: "Lightweight woven fibers. Stops small rounds.",
                ),
                _MarketItemCard(
                  name: "ENERGY DRINK",
                  type: "CONSUMABLE",
                  stat: "RESTORES 25 ENERGY",
                  basePrice: 15,
                  stock: 0,
                  circulation: 540000,
                  description: "Tastes like battery acid.",
                ),
                SizedBox(height: 80),
              ],
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
        });
        FocusScope.of(context).unfocus();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF39FF14).withOpacity(0.1) : const Color(0xFF1E1E1E),
          border: Border.all(color: isSelected ? const Color(0xFF39FF14) : const Color(0xFF333333)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF39FF14) : Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _MarketItemCard extends StatefulWidget {
  final String name, type, stat, description;
  final int basePrice, stock, circulation;
  final String? ammoType;
  final int? costPerRound;

  const _MarketItemCard({
    required this.name,
    required this.type,
    required this.stat,
    required this.basePrice,
    required this.stock,
    required this.circulation,
    required this.description,
    this.ammoType,
    this.costPerRound,
  });

  @override
  State<_MarketItemCard> createState() => _MarketItemCardState();
}

class _MarketItemCardState extends State<_MarketItemCard> {
  bool _isExpanded = false;
  int _quantity = 1;
  late TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: widget.stock > 0 ? "1" : "0");
    _quantity = widget.stock > 0 ? 1 : 0;
    _qtyController.addListener(() {
      setState(() {
        _quantity = int.tryParse(_qtyController.text) ?? 0;
        if (_quantity > widget.stock) {
          _quantity = widget.stock;
          _qtyController.text = _quantity.toString();
        }
      });
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isOutOfStock = widget.stock == 0;
    int totalPrice = _quantity * widget.basePrice;

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
              color: isOutOfStock ? Colors.redAccent.withOpacity(0.5) : (_isExpanded ? const Color(0xFF39FF14) : const Color(0xFF333333)),
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
                      Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(isOutOfStock ? "OUT OF STOCK" : "STOCK: ${widget.stock}",
                          style: TextStyle(color: isOutOfStock ? Colors.redAccent : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text("\$${widget.basePrice}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      child: ElevatedButton(
                        onPressed: (!isOutOfStock && _quantity > 0) ? () {} : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF39FF14).withOpacity(0.1),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          side: const BorderSide(color: Color(0xFF39FF14)),
                        ),
                        child: Text("BUY \$$totalPrice",
                            style: TextStyle(color: isOutOfStock ? Colors.white24 : const Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
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
                child: Text("EFFECT: ${widget.stat}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.description, style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("VALUE: \$${widget.basePrice}", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("CIRCULATION: ${widget.circulation}", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("TYPE: ${widget.type}", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              if (widget.ammoType != null && widget.costPerRound != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("AMMO TYPE: ${widget.ammoType}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text("COST PER ROUND: \$${widget.costPerRound}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ]
            ]
          ],
        ),
      ),
    );
  }
}