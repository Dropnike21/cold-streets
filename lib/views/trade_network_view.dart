import 'dart:convert';

import 'package:flutter/material.dart';
import '../api_config.dart';
import '../services/game_http.dart' as http;

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
  static const Color cBlack = Color(0xFF121212);
  static const Color cGreen = Color(0xFF39FF14);
  static const Color cPanel = Color(0xFF1A1A1A);

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _networkStatus = 'reconciliation_paused';
  String _currencyStatus = 'unresolved';
  String _bazaarStatus = 'unresolved';
  String _escrowStatus = 'not_created';
  bool _hasBazaarFlag = false;
  List<dynamic> _inventory = [];
  List<dynamic> _sellerListings = [];
  List<dynamic> _blockers = [];

  @override
  void initState() {
    super.initState();
    _fetchTradeNetwork();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTradeNetwork() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final userId = widget.userData['user_id'].toString();
      final response =
          await http.get(Uri.parse('${ApiConfig.baseUrl}/trade-network/$userId'));

      if (response.statusCode != 200) {
        throw Exception('Trade Network returned ${response.statusCode}.');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['success'] != true) {
        throw Exception('Invalid Trade Network response.');
      }

      if (!mounted) return;
      setState(() {
        _networkStatus =
            data['network_status']?.toString() ?? 'reconciliation_paused';
        _currencyStatus =
            data['settlement_currency_status']?.toString() ?? 'unresolved';
        _bazaarStatus =
            data['bazaar_access_status']?.toString() ?? 'unresolved';
        _escrowStatus =
            data['escrow_status']?.toString() ?? 'not_created';
        _hasBazaarFlag = data['has_bazaar_flag'] == true;
        _inventory = data['tradable_inventory'] is List
            ? List<dynamic>.from(data['tradable_inventory'])
            : <dynamic>[];
        _sellerListings = data['seller_listings'] is List
            ? List<dynamic>.from(data['seller_listings'])
            : <dynamic>[];
        _blockers = data['blockers'] is List
            ? List<dynamic>.from(data['blockers'])
            : <dynamic>[];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatIntegerLike(dynamic value) {
    final raw = value?.toString() ?? '0';
    if (!RegExp(r'^\d+$').hasMatch(raw)) return raw;

    final buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(',');
      buffer.write(raw[i]);
    }
    return buffer.toString();
  }

  List<dynamic> get _filteredInventory {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _inventory;
    return _inventory.where((raw) {
      if (raw is! Map) return false;
      final name = raw['name']?.toString().toLowerCase() ?? '';
      final category = raw['category']?.toString().toLowerCase() ?? '';
      final sub = raw['sub_category']?.toString().toLowerCase() ?? '';
      return name.contains(query) ||
          category.contains(query) ||
          sub.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredInventory;

    return Scaffold(
      backgroundColor: cBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: cGreen),
          onPressed: widget.onBack,
        ),
        title: const Text(
          'TRADE NETWORK',
          style: TextStyle(
            color: cGreen,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _fetchTradeNetwork,
            icon: const Icon(Icons.refresh),
            color: cGreen,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: cGreen))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _fetchTradeNetwork,
                  color: cGreen,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatusCard(),
                      if (_sellerListings.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildSellerListings(),
                      ],
                      const SizedBox(height: 12),
                      _buildSearch(),
                      const SizedBox(height: 12),
                      Text(
                        'TRADABLE STASH  •  ${filtered.length} ITEMS',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        _buildEmptyState()
                      else
                        ...filtered.map(_buildInventoryRow),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Colors.redAccent, size: 32),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Unable to load Trade Network.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchTradeNetwork,
              style: ElevatedButton.styleFrom(
                backgroundColor: cGreen,
                foregroundColor: Colors.black,
              ),
              child: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.07),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SETTLEMENT PAUSED — SOURCE RECONCILIATION',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Your real tradable inventory is shown below. The escrow/listing schema now exists, but listing, buying and cancellation remain disabled until settlement currency, fees, partial-fill and expiry rules are reconciled.',
            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.45),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _statusChip('NETWORK', _networkStatus),
              _statusChip('CURRENCY', _currencyStatus),
              _statusChip('ESCROW', _escrowStatus),
              _statusChip('BAZAAR ACCESS', _bazaarStatus),
              _statusChip(
                'HAS_BAZAAR FLAG',
                _hasBazaarFlag ? 'true' : 'false',
              ),
            ],
          ),
          if (_blockers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Blocked by: ${_blockers.map((e) => e.toString().replaceAll('_', ' ')).join(', ')}',
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cPanel,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: ${value.toUpperCase()}',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSellerListings() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cPanel,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECORDED SELLER LISTINGS',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ..._sellerListings.map((raw) {
            final row = raw is Map<String, dynamic>
                ? raw
                : Map<String, dynamic>.from(raw as Map);
            final price = row['asking_price'];
            final currency = row['settlement_currency'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['name']?.toString() ?? 'Unknown item',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'QTY ${_formatIntegerLike(row['quantity_remaining'])} / ${_formatIntegerLike(row['quantity_total'])} • ${(row['status'] ?? 'unknown').toString().toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    price == null
                        ? 'PRICE UNRESOLVED'
                        : '\$${_formatIntegerLike(price)} ${currency?.toString().toUpperCase() ?? ''}',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search your tradable stash...',
        hintStyle: const TextStyle(color: Colors.white30),
        prefixIcon: const Icon(Icons.search, color: Colors.white38),
        filled: true,
        fillColor: cPanel,
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white12),
          borderRadius: BorderRadius.circular(5),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: cGreen),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: cPanel,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Column(
        children: [
          Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 30),
          SizedBox(height: 10),
          Text(
            'NO MATCHING TRADABLE ITEMS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryRow(dynamic raw) {
    final item = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw as Map);

    final equipped = item['is_equipped'] == true;
    final category = item['category']?.toString() ?? 'UNCATEGORIZED';
    final sub = item['sub_category']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cPanel,
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.inventory_2, color: cGreen, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name']?.toString().toUpperCase() ?? 'UNKNOWN ITEM',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub == null || sub.isEmpty ? category : '$category • $sub',
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
                if (equipped) ...[
                  const SizedBox(height: 5),
                  const Text(
                    'EQUIPPED — future listing behavior still unresolved',
                    style: TextStyle(color: Colors.amber, fontSize: 9),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'QTY ${_formatIntegerLike(item['quantity'])}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'BASE REF \${_formatIntegerLike(item['base_value_reference'])}',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
              const SizedBox(height: 5),
              const Text(
                'LISTING PAUSED',
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
