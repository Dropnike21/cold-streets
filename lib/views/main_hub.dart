import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'auth_view.dart';
import 'dashboard_view.dart';
import 'streets_view.dart';
import 'market_view.dart';
import 'gym_view.dart';
import 'syndicate_view.dart';
import 'inventory_view.dart';
import 'achievements_view.dart';
import 'events_view.dart'; // V1.6: Added Events View import

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

  List<Map<String, dynamic>> _activeCooldowns = [];

  // V1.6: Track unread events
  int _unreadEventsCount = 0;

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

  String _formatCash(int amount) {
    if (amount >= 1000000000) {
      return '\$${(amount / 1000000000).toStringAsFixed(2)}b';
    } else if (amount >= 1000000) {
      return '\$${(amount / 1000000).toStringAsFixed(2)}m';
    } else if (amount >= 1000) {
      return '\$${(amount / 1000).toStringAsFixed(1)}k';
    } else {
      return '\$$amount';
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

      // We can hit both endpoints in parallel to keep it fast
      final responses = await Future.wait([
        http.get(Uri.parse('http://10.0.2.2:3000/auth/status/$userId')),
        http.get(Uri.parse('http://10.0.2.2:3000/events/$userId?limit=1')) // Just need the unread count
      ]);

      final statusResponse = responses[0];
      final eventsResponse = responses[1];

      if (statusResponse.statusCode == 200) {
        final data = jsonDecode(statusResponse.body);
        if (mounted) {
          _updateUserStats(data['user']);

          List<Map<String, dynamic>> safeCooldowns = [];
          if (data['cooldowns'] != null) {
            for (var c in data['cooldowns']) {
              safeCooldowns.add({
                'type': c['type'].toString(),
                'seconds_left': double.parse(c['seconds_left'].toString()).toInt(),
              });
            }
          } else if (data['cooldown'] != null) {
            safeCooldowns.add({
              'type': data['cooldown']['type'].toString(),
              'seconds_left': double.parse(data['cooldown']['seconds_left'].toString()).toInt(),
            });
          }

          setState(() {
            _activeCooldowns = safeCooldowns;
          });
        }
      }

      // Parse the unread events count
      if (eventsResponse.statusCode == 200) {
        final eventData = jsonDecode(eventsResponse.body);
        if (mounted) {
          setState(() {
            _unreadEventsCount = eventData['unread_count'] ?? 0;
          });
        }
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

  Widget _buildCurrentScreen() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        DashboardView(userData: widget.userData),
        StreetsView(userData: widget.userData, onStateChange: _updateUserStats),
        MarketView(userData: widget.userData, onStateChange: _updateUserStats),
        SyndicateView(userData: widget.userData, onStateChange: _updateUserStats),
        InventoryView(userData: widget.userData, onStateChange: _updateUserStats),
      ],
    );
  }

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
        automaticallyImplyLeading: false,
        titleSpacing: 16,

        title: Row(
          children: [
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
                    _formatCash(dirtyCash),
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

            const Spacer(),

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
                  if (_activeCooldowns.any((cd) => cd['seconds_left'] > 0))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _activeCooldowns.where((cd) => cd['seconds_left'] > 0).map((cd) {
                          String type = cd['type'];
                          int sec = cd['seconds_left'];
                          String label = type == 'hospital' ? 'Hospital' : (type == 'jail' ? 'Jailed' : type[0].toUpperCase() + type.substring(1));

                          return SizedBox(
                            width: 130,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1)),
                                Text(_formatTime(sec), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // SLEEK PROFILE HEADER WITH NOTIFICATION BELL
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF252525),
                          border: Border.all(color: const Color(0xFF39FF14), width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.person, color: Colors.grey, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(username, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),

                                // V1.6: THE NOTIFICATION BELL
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context); // Close Drawer
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => EventsView(userData: widget.userData))
                                    ).then((_) {
                                      // When returning from Events view, clear the badge locally immediately
                                      setState(() { _unreadEventsCount = 0; });
                                    });
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(Icons.notifications, color: Colors.white54, size: 24),
                                      if (_unreadEventsCount > 0)
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                              color: Colors.redAccent,
                                              shape: BoxShape.circle,
                                            ),
                                            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                            child: Text(
                                              _unreadEventsCount > 9 ? '9+' : '$_unreadEventsCount',
                                              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.local_hospital, color: hp < 25 ? Colors.redAccent : Colors.grey[800], size: 14),
                                const SizedBox(width: 6),
                                Icon(Icons.gavel, color: _activeCooldowns.any((cd) => cd['type'] == 'jail') ? Colors.blueAccent : Colors.grey[800], size: 14),
                                const SizedBox(width: 6),
                                const Icon(Icons.wifi, color: Color(0xFF39FF14), size: 14),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // ACCORDION CITY NAVIGATION
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      iconColor: const Color(0xFF39FF14),
                      collapsedIconColor: Colors.grey[600],
                      title: Row(
                        children: [
                          const Expanded(child: Divider(color: Color(0xFF333333))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                                "CITY NAVIGATION",
                                style: TextStyle(color: Colors.grey[500], fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)
                            ),
                          ),
                          const Expanded(child: Divider(color: Color(0xFF333333))),
                        ],
                      ),
                      children: [
                        _buildMenuTile(
                            icon: Icons.fitness_center,
                            color: Colors.orangeAccent,
                            title: "The Gym",
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => GymView(userData: widget.userData, onStateChange: _updateUserStats))
                              );
                            }
                        ),
                        _buildMenuTile(
                            icon: Icons.local_hospital,
                            color: Colors.redAccent,
                            title: "Hospital",
                            onTap: () {}
                        ),
                        _buildMenuTile(
                            icon: Icons.account_balance,
                            color: Colors.blueAccent,
                            title: "Bank",
                            onTap: () {}
                        ),
                        _buildMenuTile(
                            icon: Icons.gavel,
                            color: Colors.grey,
                            title: "Jail",
                            onTap: () {}
                        ),
                      ],
                    ),
                  ),

                  const Divider(color: Color(0xFF333333)),

                  // PLAYER MENUS
                  _buildMenuTile(
                      icon: Icons.military_tech,
                      color: const Color(0xFF39FF14),
                      title: "Achievements",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => AchievementsView(userData: widget.userData))
                        );
                      }
                  ),
                  _buildMenuTile(
                      icon: Icons.backpack,
                      color: Colors.white,
                      title: "Inventory",
                      onTap: () {
                        setState(() => _selectedIndex = 4);
                        Navigator.pop(context);
                      }
                  ),
                  _buildMenuTile(
                      icon: Icons.settings,
                      color: Colors.grey,
                      title: "Settings",
                      onTap: () {}
                  ),
                  _buildMenuTile(
                      icon: Icons.exit_to_app,
                      color: Colors.redAccent,
                      title: "Log Out",
                      onTap: _logout,
                      textColor: Colors.redAccent
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
          selectedFontSize: 11,
          unselectedFontSize: 11,
          iconSize: 22,
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

  // Reusable slim list tile for menus
  Widget _buildMenuTile({required IconData icon, required Color color, required String title, required VoidCallback onTap, Color textColor = Colors.white}) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
      leading: Icon(icon, color: color, size: 18),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}