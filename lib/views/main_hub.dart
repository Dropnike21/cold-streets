import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'auth_view.dart';
import 'dashboard_view.dart';
import 'streets_view.dart';
import 'market_view.dart';
import 'syndicate_view.dart';
import 'inventory_view.dart';

class MainHub extends StatefulWidget {
  final Map<String, dynamic> userData;

  const MainHub({super.key, required this.userData});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  late String username;
  late int dirtyCash;
  late int energy;
  late int nerve;
  late int maxNerve;
  late int hp;

  int _selectedIndex = 0;

  Timer? _syncTimer;
  Timer? _countdownTimer;

  // FIXED: Now an array of active cooldowns
  List<Map<String, dynamic>> _activeCooldowns = [];

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
    username = widget.userData['username']?.toString() ?? "Unknown";
    dirtyCash = _parseSafeInt(widget.userData['dirty_cash']);
    energy = _parseSafeInt(widget.userData['energy']);
    nerve = _parseSafeInt(widget.userData['nerve']);
    hp = _parseSafeInt(widget.userData['hp']);
    maxNerve = _parseSafeInt(widget.userData['max_nerve']);
    if (maxNerve == 0) maxNerve = 10;

    _startTelemetrySync();
  }
  //  MMO Number Formatter (Prevents Billionaire UI Overflow)
  String _formatCash(int amount) {
    if (amount >= 1000000000) {
      return '\$${(amount / 1000000000).toStringAsFixed(2)}b'; // 1.32B
    } else if (amount >= 1000000) {
      return '\$${(amount / 1000000).toStringAsFixed(2)}m';    // 1.25M
    } else if (amount >= 1000) {
      return '\$${(amount / 1000).toStringAsFixed(1)}k';       // 15.5K
    } else {
      return '\$$amount';                                      // $500
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startTelemetrySync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLiveStatus());

    // Decrement all active cooldowns by 1 second locally
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeCooldowns.isNotEmpty && mounted) {
        bool updated = false;
        for (var cd in _activeCooldowns) {
          if (cd['seconds_left'] > 0) {
            cd['seconds_left']--;
            updated = true;
          }
        }
        if (updated) setState(() {});
      }
    });
  }

  Future<void> _fetchLiveStatus() async {
    try {
      final String userId = widget.userData['user_id'].toString();
      final response = await http.get(Uri.parse('http://10.0.2.2:3000/auth/status/$userId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 🟢 Check your Flutter console! It should print the array here.
        debugPrint("🟢 SYNC SUCCESS: $data");

        if (mounted) {
          _updateUserStats(data['user']);

          // Safely parse the cooldowns array without triggering Dart type errors
          List<Map<String, dynamic>> safeCooldowns = [];

          if (data['cooldowns'] != null) {
            for (var c in data['cooldowns']) {
              safeCooldowns.add({
                'type': c['type'].toString(),
                'seconds_left': double.parse(c['seconds_left'].toString()).toInt(),
              });
            }
          }
          // Fallback just in case your Node server is still using the old code!
          else if (data['cooldown'] != null) {
            safeCooldowns.add({
              'type': data['cooldown']['type'].toString(),
              'seconds_left': double.parse(data['cooldown']['seconds_left'].toString()).toInt(),
            });
          }

          setState(() {
            _activeCooldowns = safeCooldowns;
          });
        }
      } else {
        debugPrint("🔴 SYNC API ERROR: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("🔴 SYNC NETWORK ERROR: $e");
    }
  }

  void _updateUserStats(Map<String, dynamic> updatedStats) {
    if (!mounted) return;
    setState(() {
      dirtyCash = _parseSafeInt(updatedStats['dirty_cash'] ?? dirtyCash);
      energy = _parseSafeInt(updatedStats['energy'] ?? energy);
      nerve = _parseSafeInt(updatedStats['nerve'] ?? nerve);
      maxNerve = _parseSafeInt(updatedStats['max_nerve'] ?? maxNerve);
      hp = _parseSafeInt(updatedStats['hp'] ?? hp);

      widget.userData['dirty_cash'] = dirtyCash;
      widget.userData['energy'] = energy;
      widget.userData['nerve'] = nerve;
      widget.userData['max_nerve'] = maxNerve;
      widget.userData['hp'] = hp;
    });
  }

  void _logout() {
    _syncTimer?.cancel();
    _countdownTimer?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const AuthView()),
    );
  }

  void _onNavTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // FIXED: IndexedStack keeps all tabs alive in the background simultaneously
  Widget _buildCurrentScreen() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        DashboardView(userData: widget.userData),
        StreetsView(userData: widget.userData, onStateChange: _updateUserStats),
        MarketView(userData: widget.userData, onStateChange: _updateUserStats),
        SyndicateView(userId: widget.userData['user_id'].toString()),
        InventoryView(userData: widget.userData, onStateChange: _updateUserStats),
      ],
    );
  }

  // FIXED: Formats time to H:MM:SS or MM:SS dynamically
  String _formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    if (h > 0) {
      return "$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),

      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 2,
        shadowColor: const Color(0xFF39FF14).withValues(alpha: 0.5),
        automaticallyImplyLeading: false, // Prevents default back button spacing
        titleSpacing: 16, // Gives clean padding on the left edge

        title: Row(
          children: [
            // 1. THE LOGO
            const Text(
              "CS",
              style: TextStyle(
                  color: Color(0xFF39FF14),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  fontStyle: FontStyle.italic
              ),
            ),
            const SizedBox(width: 12),

            // 2. THE DYNAMIC MONEY BADGE
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF39FF14).withValues(alpha: 0.1),
                border: Border.all(color: const Color(0xFF39FF14).withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Text(
                    _formatCash(dirtyCash), // 🔥 Your formatted billion-dollar variable
                    style: const TextStyle(
                      color: Color(0xFF39FF14),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(), // 🔥 Pushes the remaining stats to the right!

            // 3. THE REMAINING STATS
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildStatItem(Icons.bolt, "$energy/100", Colors.yellowAccent),
                const SizedBox(width: 8),
                _buildStatItem(Icons.psychology, "$nerve/$maxNerve", Colors.purpleAccent),
                const SizedBox(width: 8),
                _buildStatItem(Icons.favorite, "$hp", Colors.redAccent),
              ],
            ),
          ],
        ),
      ),

      endDrawer: Drawer(
        backgroundColor: const Color(0xFF1A1A1A),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, left: 16, right: 16, bottom: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF39FF14), width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // --- MULTI-COOLDOWN 2-COLUMN UI ---
                  // --- MULTI-COOLDOWN 2-COLUMN UI ---
                  if (_activeCooldowns.any((cd) => cd['seconds_left'] > 0))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _activeCooldowns.where((cd) => cd['seconds_left'] > 0).map((cd) {
                          String type = cd['type'];
                          int sec = cd['seconds_left'];

                          // FIXED: Shortened to "Hospital"
                          String label = type == 'hospital' ? 'Hospital' : (type == 'jail' ? 'Jailed' : type[0].toUpperCase() + type.substring(1));

                          return SizedBox(
                            // FIXED: Strict width guarantees no overflow tape
                            width: 130,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1)),
                                Text(_formatTime(sec), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // --- SYNDICATE PROFILE TEXT ---
                  const Text("SYNDICATE PROFILE", style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(username, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Icon(Icons.local_hospital, color: hp < 25 ? Colors.redAccent : Colors.grey[800], size: 20),
                      const SizedBox(width: 8),
                      Icon(Icons.gavel, color: _activeCooldowns.any((cd) => cd['type'] == 'jail') ? Colors.blueAccent : Colors.grey[800], size: 20),
                      const SizedBox(width: 8),
                      const Icon(Icons.wifi, color: Color(0xFF39FF14), size: 20),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // --- CITY NAVIGATION ---
                  const Padding(
                    padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
                    child: Text("CITY NAVIGATION", style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.fitness_center, color: Colors.orangeAccent),
                    title: const Text("The Gym", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context); // Close Drawer
                      // Navigator.push(context, MaterialPageRoute(builder: (context) => const GymView())); // Uncomment when Gym is ready
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.local_hospital, color: Colors.redAccent),
                    title: const Text("Hospital", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance, color: Colors.blueAccent),
                    title: const Text("Bank", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.gavel, color: Colors.grey),
                    title: const Text("Jail", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onTap: () {},
                  ),

                  const Divider(color: Color(0xFF333333)),

                  // --- PLAYER MENUS ---
                  ListTile(
                    leading: const Icon(Icons.backpack, color: Colors.white),
                    title: const Text("Stash / Inventory", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onTap: () {
                      setState(() => _selectedIndex = 4); // Switch to Inventory Tab
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Colors.grey),
                    title: const Text("Settings", style: TextStyle(color: Colors.white)),
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                    title: const Text("Log Out", style: TextStyle(color: Colors.redAccent)),
                    onTap: _logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      body: _buildCurrentScreen(),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF39FF14), width: 0.5)),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.black,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF39FF14),
          unselectedItemColor: Colors.grey[700],
          currentIndex: _selectedIndex > 3 ? 0 : _selectedIndex,
          onTap: _onNavTapped,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Hub"),
            BottomNavigationBarItem(icon: Icon(Icons.local_fire_department), label: "Streets"),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Market"),
            BottomNavigationBarItem(icon: Icon(Icons.group), label: "Syndicate"),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}