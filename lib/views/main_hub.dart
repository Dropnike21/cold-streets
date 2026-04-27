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
import 'events_view.dart';
import 'credit_broker_view.dart';
import 'jobs_view.dart';
import 'city_hall_view.dart';
import 'company_dashboard_view.dart'; // --- NEW IMPORT ---

class MainHub extends StatefulWidget {
  final Map<String, dynamic> userData;

  const MainHub({super.key, required this.userData});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  late String userId;
  late String username;
  late int dirtyCash;
  late int cleanCash;
  late int creds;

  int goldBars = 0;
  int influence = 0;

  bool hasBazaar = false;

  late int energy;
  late int nerve;
  late int maxNerve;
  late int hp;

  int currentJobId = 0;

  // --- MASTER NAVIGATION INDEX ---
  int _selectedIndex = 0;
  int _bottomNavIndex = 0;
  int _activeCompanyId = 0; // Tracks which company to show in dashboard

  Timer? _syncTimer;
  Timer? _countdownTimer;

  int _regenSecondsLeft = 30;

  List<Map<String, dynamic>> _activeCooldowns = [];
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
    userId = widget.userData['user_id']?.toString() ?? "0";
    username = widget.userData['username']?.toString() ?? "Unknown";

    hasBazaar = widget.userData['has_bazaar'] == true;

    dirtyCash = _parseSafeInt(widget.userData['dirty_cash']);
    cleanCash = _parseSafeInt(widget.userData['clean_cash']);
    creds = _parseSafeInt(widget.userData['cred']);

    energy = _parseSafeInt(widget.userData['energy']);
    nerve = _parseSafeInt(widget.userData['nerve']);
    hp = _parseSafeInt(widget.userData['hp']);
    maxNerve = _parseSafeInt(widget.userData['max_nerve']);
    if (maxNerve == 0) maxNerve = 10;

    currentJobId = _parseSafeInt(widget.userData['current_job_id']);

    _startTelemetrySync();
  }

  String _formatCash(int amount) {
    if (amount >= 1000000000) {
      return '\$${(amount / 1000000000).toStringAsFixed(2)}b';
    } else if (amount >= 1000000) {
      return '\$${(amount / 1000000).toStringAsFixed(2)}m';
    } else {
      String formatted = amount.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => '${m[1]},'
      );
      return '\$$formatted';
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
      if (!mounted) return;
      bool updated = false;

      if (_regenSecondsLeft > 0) {
        _regenSecondsLeft--;
        updated = true;
      } else {
        _regenSecondsLeft = 30;
        updated = true;
      }

      if (_activeCooldowns.isNotEmpty) {
        for (var cd in _activeCooldowns) {
          if (cd['seconds_left'] > 0) {
            cd['seconds_left']--;
            updated = true;
          }
        }
      }

      if (updated) setState(() {});
    });
  }

  Future<void> _fetchLiveStatus() async {
    try {
      final String id = widget.userData['user_id'].toString();

      final responses = await Future.wait([
        http.get(Uri.parse('http://10.0.2.2:3000/auth/status/$id')),
        http.get(Uri.parse('http://10.0.2.2:3000/events/$id?limit=1'))
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
      cleanCash = _parseSafeInt(updatedStats['clean_cash'] ?? cleanCash);
      creds = _parseSafeInt(updatedStats['cred'] ?? creds);

      energy = _parseSafeInt(updatedStats['energy'] ?? energy);
      nerve = _parseSafeInt(updatedStats['nerve'] ?? nerve);
      maxNerve = _parseSafeInt(updatedStats['max_nerve'] ?? maxNerve);
      hp = _parseSafeInt(updatedStats['hp'] ?? hp);

      currentJobId = _parseSafeInt(updatedStats['current_job_id'] ?? currentJobId);

      widget.userData['dirty_cash'] = dirtyCash;
      widget.userData['clean_cash'] = cleanCash;
      widget.userData['cred'] = creds;
      widget.userData['energy'] = energy;
      widget.userData['nerve'] = nerve;
      widget.userData['max_nerve'] = maxNerve;
      widget.userData['hp'] = hp;
      widget.userData['current_job_id'] = currentJobId;
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

  // --- NAVIGATION ROUTING LOGIC ---
  void _navigateTo(int index) {
    setState(() {
      _selectedIndex = index;
      if (index <= 3) {
        _bottomNavIndex = index;
      }
    });
    if (Scaffold.of(context).isEndDrawerOpen) {
      Navigator.pop(context);
    }
  }

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0: return DashboardView(userData: widget.userData);
      case 1: return StreetsView(userData: widget.userData, onStateChange: _updateUserStats);
      case 2: return MarketView(userData: widget.userData, onStateChange: _updateUserStats);
      case 3: return SyndicateView(userData: widget.userData, onStateChange: _updateUserStats);
      case 4: return InventoryView(userData: widget.userData, onStateChange: _updateUserStats);
      case 5: return GymView(userData: widget.userData, onStateChange: _updateUserStats);
      case 6: return CreditBrokerView(userData: widget.userData);
      case 7: return JobsView(userData: widget.userData, onStateChange: _updateUserStats);
      case 8: return CityHallView(
        userData: widget.userData,
        onStateChange: _updateUserStats,
        onViewCompany: (int companyId) {
          setState(() {
            _activeCompanyId = companyId;
            _selectedIndex = 11; // Open Dashboard
          });
        },
      );
      case 9: return AchievementsView(userData: widget.userData);
      case 10: return EventsView(userData: widget.userData);
      case 11: return CompanyDashboardView(
        userData: widget.userData,
        companyId: _activeCompanyId,
        onBack: () => _navigateTo(8), // Returns to City Hall
      );
      default: return DashboardView(userData: widget.userData);
    }
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
    bool showBottomNav = _selectedIndex <= 3;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),

      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 2,
        toolbarHeight: 65,
        shadowColor: const Color(0xFF39FF14).withValues(alpha: 0.5),
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "CS",
                  style: TextStyle(color: Color(0xFF39FF14), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2, fontStyle: FontStyle.italic),
                ),
                const SizedBox(width: 8),
                Text(
                  "$username [$userId]",
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _buildStatItem(Icons.bolt, "$energy/100", Colors.yellowAccent, "ENERGY\nUsed for committing crimes.\nRegens +5 in ${_formatTime(_regenSecondsLeft)}"),
                const SizedBox(width: 8),
                _buildStatItem(Icons.psychology, "$nerve/$maxNerve", Colors.purpleAccent, "NERVE\nUsed for serious crimes.\nRegens +2 in ${_formatTime(_regenSecondsLeft)}"),
                const SizedBox(width: 8),
                _buildStatItem(Icons.favorite, "$hp", Colors.redAccent, "HEALTH POINTS\nDon't let this hit 0.\nRegens +10 in ${_formatTime(_regenSecondsLeft)}"),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCurrencyItem(Icons.view_agenda, "$goldBars", Colors.amber, "GOLD BARS\nPremium currency."),
                _buildCurrencyItem(Icons.attach_money, _formatCash(dirtyCash), const Color(0xFF39FF14), "DIRTY CASH\nUntraceable street money."),
                _buildCurrencyItem(Icons.attach_money, _formatCash(cleanCash), Colors.white, "CLEAN CASH\nSafely laundered in the bank."),
                if (creds > 0) _buildCurrencyItem(Icons.diamond, "$creds", Colors.cyanAccent, "CREDS\nEarned from achievements."),
                _buildCurrencyItem(Icons.how_to_vote, "$influence", Colors.deepPurpleAccent, "INFLUENCE\nSyndicate political power."),
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
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF39FF14), width: 2))),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: const Color(0xFF252525), border: Border.all(color: const Color(0xFF39FF14), width: 1.5), borderRadius: BorderRadius.circular(6)),
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
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    _navigateTo(10);
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(Icons.notifications, color: Colors.white54, size: 24),
                                      if (_unreadEventsCount > 0)
                                        Positioned(
                                          right: -2, top: -2,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
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
                                if (currentJobId > 0) ...[
                                  const Tooltip(message: "Employed", child: Icon(Icons.work, color: Colors.tealAccent, size: 14)),
                                  const SizedBox(width: 6),
                                ],
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
                  Container(
                    color: const Color(0xFF121212),
                    child: _buildMenuTile(
                        icon: Icons.dashboard,
                        color: const Color(0xFF39FF14),
                        title: "Return to City Hub",
                        onTap: () {
                          Navigator.pop(context);
                          _navigateTo(0);
                        }
                    ),
                  ),
                  const Divider(color: Color(0xFF333333), height: 1),

                  _buildDistrictAccordion(
                      title: "LOCAL NEIGHBORHOOD",
                      initiallyExpanded: true,
                      children: [
                        _buildMenuTile(icon: Icons.fitness_center, color: Colors.orangeAccent, title: "The Gym", onTap: () {
                          Navigator.pop(context);
                          _navigateTo(5);
                        }),
                        _buildMenuTile(icon: Icons.local_hospital, color: Colors.redAccent, title: "The Clinic", onTap: () {}),
                        _buildMenuTile(icon: Icons.church, color: Colors.yellow, title: "Church", onTap: () {}),
                      ]
                  ),

                  _buildDistrictAccordion(
                      title: "THE UNDERWORLD",
                      children: [
                        _buildMenuTile(icon: Icons.diamond, color: Colors.cyanAccent, title: "Credit Broker", onTap: () {
                          Navigator.pop(context);
                          _navigateTo(6);
                        }),
                        _buildMenuTile(icon: Icons.security, color: Colors.grey, title: "Underground Munitions", onTap: () {}),
                        _buildMenuTile(icon: Icons.casino, color: Colors.purpleAccent, title: "The Casino", onTap: () {}),
                      ]
                  ),

                  _buildDistrictAccordion(
                      title: "FINANCIAL DISTRICT",
                      children: [
                        _buildMenuTile(icon: Icons.account_balance, color: Colors.blueAccent, title: "The Bank", onTap: () {}),
                        _buildMenuTile(icon: Icons.show_chart, color: Colors.greenAccent, title: "Stock Market", onTap: () {}),
                        _buildMenuTile(icon: Icons.domain, color: Colors.tealAccent, title: "Real Estate", onTap: () {}),
                        _buildMenuTile(icon: Icons.shopping_bag, color: Colors.amber, title: "Trade Network", onTap: () {}),
                        _buildMenuTile(icon: Icons.gavel, color: Colors.orange, title: "Auction House", onTap: () {}),
                      ]
                  ),

                  _buildDistrictAccordion(
                      title: "CIVIC CENTER",
                      children: [
                        _buildMenuTile(icon: Icons.newspaper, color: Colors.white, title: "Info Broker", onTap: () {}),
                        _buildMenuTile(icon: Icons.school, color: Colors.lightBlueAccent, title: "University", onTap: () {}),
                        _buildMenuTile(icon: Icons.work, color: Colors.tealAccent, title: "Career Center", onTap: () {
                          Navigator.pop(context);
                          _navigateTo(7);
                        }),
                        _buildMenuTile(icon: Icons.gavel, color: Colors.grey, title: "State Jail", onTap: () {}),
                        _buildMenuTile(icon: Icons.location_city, color: Colors.deepPurpleAccent, title: "City Hall", onTap: () {
                          Navigator.pop(context);
                          _navigateTo(8);
                        }),
                      ]
                  ),

                  _buildDistrictAccordion(
                      title: "TRANSIT & AUTO",
                      children: [
                        _buildMenuTile(icon: Icons.map, color: const Color(0xFF39FF14), title: "City Map", onTap: () {}),
                        _buildMenuTile(icon: Icons.flight_takeoff, color: Colors.white70, title: "Airport", onTap: () {}),
                        _buildMenuTile(icon: Icons.car_repair, color: Colors.grey, title: "The Chop Shop", onTap: () {}),
                        _buildMenuTile(icon: Icons.sports_score, color: Colors.yellow, title: "The Street Circuit", onTap: () {}),
                      ]
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),

            Container(
              decoration: BoxDecoration(color: const Color(0xFF121212), border: Border(top: BorderSide(color: Colors.grey.shade800, width: 1))),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16), color: const Color(0xFF1A1A1A),
                      child: Text("PERSONAL DASHBOARD", style: TextStyle(color: Colors.grey[500], fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold), textAlign: TextAlign.left),
                    ),
                    _buildMenuTile(icon: Icons.backpack, color: Colors.white, title: "Inventory", onTap: () {
                      Navigator.pop(context);
                      _navigateTo(4);
                    }),
                    _buildMenuTile(icon: Icons.military_tech, color: const Color(0xFF39FF14), title: "Achievements", onTap: () {
                      Navigator.pop(context);
                      _navigateTo(9);
                    }),
                    _buildMenuTile(icon: Icons.house, color: Colors.brown.shade300, title: "My Properties", onTap: () {}),
                    if (hasBazaar) _buildMenuTile(icon: Icons.storefront, color: Colors.amber, title: "My Bazaar", onTap: () {}),
                    _buildMenuTile(icon: Icons.assignment, color: Colors.amberAccent, title: "Mission Board", onTap: () {}),
                    _buildMenuTile(icon: Icons.settings, color: Colors.grey, title: "Settings", onTap: () {}),
                    _buildMenuTile(icon: Icons.exit_to_app, color: Colors.redAccent, title: "Log Out", onTap: _logout, textColor: Colors.redAccent),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      body: _buildCurrentScreen(),

      bottomNavigationBar: showBottomNav
          ? Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF39FF14), width: 0.5))),
        child: BottomNavigationBar(
          backgroundColor: Colors.black,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF39FF14),
          unselectedItemColor: Colors.grey[700],
          selectedFontSize: 11,
          unselectedFontSize: 11,
          iconSize: 22,
          currentIndex: _bottomNavIndex,
          onTap: (index) => _navigateTo(index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Hub"),
            BottomNavigationBarItem(icon: Icon(Icons.local_fire_department), label: "Streets"),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Market"),
            BottomNavigationBarItem(icon: Icon(Icons.group), label: "Syndicate"),
          ],
        ),
      )
          : null,
    );
  }

  Widget _buildStatItem(IconData icon, String value, Color color, String tooltipText) {
    return Tooltip(
      message: tooltipText, showDuration: const Duration(seconds: 10), triggerMode: TooltipTriggerMode.longPress,
      padding: const EdgeInsets.all(12), margin: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: const Color(0xFF39FF14), width: 1), borderRadius: BorderRadius.circular(6)),
      child: Row(children: [Icon(icon, color: color, size: 16), const SizedBox(width: 2), Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))]),
    );
  }

  Widget _buildCurrencyItem(IconData icon, String value, Color color, String tooltipText) {
    return Tooltip(
      message: tooltipText, showDuration: const Duration(seconds: 10), triggerMode: TooltipTriggerMode.longPress,
      padding: const EdgeInsets.all(12), margin: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: const Color(0xFF39FF14), width: 1), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 14), const SizedBox(width: 2), Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold))]),
    );
  }

  Widget _buildDistrictAccordion({required String title, required List<Widget> children, bool initiallyExpanded = false}) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded, iconColor: const Color(0xFF39FF14), collapsedIconColor: Colors.grey[600], tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
        title: Row(children: [Padding(padding: const EdgeInsets.only(right: 8.0), child: Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold))), const Expanded(child: Divider(color: Color(0xFF333333)))]),
        children: children,
      ),
    );
  }

  Widget _buildMenuTile({required IconData icon, required Color color, required String title, required VoidCallback onTap, Color textColor = Colors.white}) {
    return ListTile(
      dense: true, visualDensity: const VisualDensity(horizontal: 0, vertical: -4), contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
      leading: Icon(icon, color: color, size: 16), title: Text(title, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)), onTap: onTap,
    );
  }
}