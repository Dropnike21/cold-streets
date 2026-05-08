import 'package:flutter/material.dart';
import 'cas_perya.dart';

class CasinoHubView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final Function(int) onNavigate;
  const CasinoHubView({super.key, required this.userData, required this.onStateChange, required this.onNavigate});

  @override
  State<CasinoHubView> createState() => _CasinoHubViewState();
}

class _CasinoHubViewState extends State<CasinoHubView> {
  late int casinoTokens;

  // --- MODULAR GAME CATALOGS ---
  final List<Map<String, dynamic>> tokenGames = [
    {'id': 'perya', 'name': 'Perya Color Game', 'icon': Icons.casino},
    {'id': 'slots', 'name': 'Syndicate Slots', 'icon': Icons.games},
    {'id': 'high_low', 'name': 'High-Low', 'icon': Icons.swap_vert},
    {'id': 'blackjack_npc', 'name': 'Blackjack 21', 'icon': Icons.style},
    {'id': 'scratchers', 'name': 'Scratchers', 'icon': Icons.receipt},
  ];

  final List<Map<String, dynamic>> vipGames = [
    {'id': 'poker', 'name': 'Texas Hold\'em', 'icon': Icons.view_carousel},
    {'id': 'roulette', 'name': 'Russian Roulette', 'icon': Icons.warning},
    {'id': 'wager_board', 'name': 'Wager Board', 'icon': Icons.format_list_numbered},
    {'id': 'liars_dice', 'name': 'Liar\'s Dice', 'icon': Icons.grid_view},
    {'id': 'death_race', 'name': 'Chicken Race', 'icon': Icons.directions_car},
    {'id': 'sabong', 'name': 'Pit Derby', 'icon': Icons.pets},
    {'id': 'blackjack_pvp', 'name': 'Player Banked 21', 'icon': Icons.monetization_on},
    {'id': 'baccarat', 'name': 'Baccarat', 'icon': Icons.account_balance},
  ];

  int _parseSafeInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _syncState();
  }

  void _syncState() {
    casinoTokens = _parseSafeInt(widget.userData['casino_tokens']);
    if (casinoTokens == 0) casinoTokens = 100; // Default daily mock
  }

  void _openGameModule(String gameId, String gameName) {
    if (gameId == 'perya') {
      widget.onNavigate(21); // This seamlessly swaps the view while keeping the top HUD!
    } else if (gameId == 'slots') {
      widget.onNavigate(22); // 👈 ADD THIS
    } else if (gameId == 'high_low') {
      widget.onNavigate(23); // 👈 ADD THIS
    }else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$gameName is still under construction."), backgroundColor: Colors.white24));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black, elevation: 0, titleSpacing: 16, centerTitle: false,
        title: const Text("THE UNDERGROUND", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 16)),
        iconTheme: const IconThemeData(color: Color(0xFF39FF14)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 12, bottom: 12),
            child: _buildWalletBadge("DAILY TOKENS", "$casinoTokens / 100", Colors.cyanAccent),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCategorySection(
              title: "PVS (PLAYER VS SYSTEM)",
              subtitle: "SYSTEM BANKED. BET TOKENS OR DIRTY CASH, WIN CLEAN CASH.",
              accentColor: Colors.cyanAccent,
              games: tokenGames,
            ),
            const SizedBox(height: 32),
            _buildCategorySection(
              title: "PVP (PLAYER VS PLAYER)",
              subtitle: "HIGH STAKES PvP. 1% TAX UNDER \$10M. 3% TAX ON \$10M+.",
              accentColor: Colors.redAccent,
              games: vipGames,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- UI COMPONENTS ---
  Widget _buildWalletBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3))
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildCategorySection({required String title, required String subtitle, required Color accentColor, required List<Map<String, dynamic>> games}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.stop, color: accentColor, size: 16),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24.0, top: 2, bottom: 16),
          child: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: games.length,
          itemBuilder: (context, index) {
            var game = games[index];
            return _buildGridCard(game, accentColor);
          },
        ),
      ],
    );
  }

  Widget _buildGridCard(Map<String, dynamic> game, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openGameModule(game['id'], game['name']),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF121212), shape: BoxShape.circle, border: Border.all(color: accentColor.withOpacity(0.3))),
                  child: Icon(game['icon'], color: accentColor, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  game['name'].toString().toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}