import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

import '../api_config.dart';
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
import 'company_dashboard_view.dart';
import 'company_management_view.dart';
import 'info_broker_view.dart';
import 'jail_view.dart';
import 'hospital_view.dart';
import 'university_view.dart';
import 'bank_view.dart';
import 'real_estate_view.dart';
import 'manage_properties_view.dart';
import 'casino_hub_view.dart';
import 'cas_perya.dart';
import 'cas_slots.dart';
import 'cas_high_low.dart';
import 'city_map_view.dart';

// 👇 Your new modular drawer import!
import 'main_hub_drawer.dart';

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
  late int casinoTokens;

  int goldBars = 0;
  int influence = 0;

  bool hasBazaar = false;

  late int energy;
  late int nerve;
  late int maxNerve;
  late int hp;
  late double heat;
  String? hospitalExpiry;
  String? jailExpiry;


  int currentJobId = 0;

  // --- MASTER NAVIGATION INDEX ---
  int _selectedIndex = 0;
  int _bottomNavIndex = 0;
  int _activeCompanyId = 0; // Tracks which company to show in dashboard
  int _infoBrokerTabIndex = 0; // Tracks which tab to open in Info Broker

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

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
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
    casinoTokens = _parseSafeInt(widget.userData['casino_tokens']);
    goldBars = _parseSafeInt(widget.userData['gold_bars']);
    influence = _parseSafeInt(widget.userData['influence']);

    energy = _parseSafeInt(widget.userData['energy']);
    nerve = _parseSafeInt(widget.userData['nerve']);
    hp = _parseSafeInt(widget.userData['hp']);
    heat = _parseDouble(widget.userData['heat']);
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
        http.get(Uri.parse('${ApiConfig.baseUrl}/auth/status/$id')),
        http.get(Uri.parse('${ApiConfig.baseUrl}/events/$id?limit=1'))
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
      casinoTokens = _parseSafeInt(updatedStats['casino_tokens'] ?? casinoTokens);
      goldBars = _parseSafeInt(updatedStats['gold_bars'] ?? goldBars);
      influence = _parseSafeInt(updatedStats['influence'] ?? influence);
      hasBazaar = updatedStats['has_bazaar'] == false;


      energy = _parseSafeInt(updatedStats['energy'] ?? energy);
      nerve = _parseSafeInt(updatedStats['nerve'] ?? nerve);
      maxNerve = _parseSafeInt(updatedStats['max_nerve'] ?? maxNerve);
      hp = _parseSafeInt(updatedStats['hp'] ?? hp);
      heat = _parseDouble(updatedStats['heat'] ?? heat);
      hospitalExpiry = updatedStats['hospital_expires_at'];
      jailExpiry = updatedStats['jail_expires_at'];

      currentJobId = _parseSafeInt(updatedStats['current_job_id'] ?? currentJobId);

      widget.userData['dirty_cash'] = dirtyCash;
      widget.userData['clean_cash'] = cleanCash;
      widget.userData['cred'] = creds;
      widget.userData['energy'] = energy;
      widget.userData['nerve'] = nerve;
      widget.userData['max_nerve'] = maxNerve;
      widget.userData['hp'] = hp;
      widget.userData['heat'] = heat;
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
      case 7: return JobsView(
        userData: widget.userData,
        onStateChange: _updateUserStats,
        onBack: () {
          setState(() => _infoBrokerTabIndex = 2);
          _navigateTo(13);
        },
      );
      case 8: return CityHallView(
        userData: widget.userData,
        onStateChange: _updateUserStats,
        onViewCompany: (int companyId) {
          setState(() {
            _activeCompanyId = companyId;
            _selectedIndex = 11;
          });
        },
      );
      case 9: return AchievementsView(userData: widget.userData);
      case 10: return EventsView(userData: widget.userData);
      case 11: return CompanyDashboardView(
        userData: widget.userData,
        companyId: _activeCompanyId,
        onBack: () => _navigateTo(8),
        onManage: () => _navigateTo(12),
      );
      case 12: return CompanyManagementView(
        userData: widget.userData,
        companyId: _activeCompanyId,
        onBack: () => _navigateTo(11),
        onSell: () => _navigateTo(8),
      );
      case 13: return InfoBrokerView(
        key: ValueKey(_infoBrokerTabIndex),
        userData: widget.userData,
        onStateChange: _updateUserStats,
        initialTabIndex: _infoBrokerTabIndex,
        onNavigate: (index) {
          setState(() => _infoBrokerTabIndex = 0);
          _navigateTo(index);
        },
      );
      case 14: return JailView(userData: widget.userData, onStateChange: _updateUserStats);
      case 15: return HospitalView(userData: widget.userData);
      case 16: return UniversityView(userData: widget.userData, onStateChange: _updateUserStats);
      case 17: return BankView(userData: widget.userData, onStateChange: _updateUserStats);
      case 18: return RealEstateView(userData: widget.userData, onStateChange: _updateUserStats); // 👇 ADD THIS
      case 19: return ManagePropertiesView(userData: widget.userData, onStateChange: _updateUserStats); // 👇 ADD THIS
      case 20: return CasinoHubView(userData: widget.userData, onStateChange: _updateUserStats,onNavigate: _navigateTo,);
      case 21: return CasPeryaView(
        userData: widget.userData,
        onStateChange: _updateUserStats,
        onBack: () => _navigateTo(20), // Returns them to the Casino Hub
      );
      case 22: return CasSlotsView(
        userData: widget.userData,
        onStateChange: _updateUserStats,
        onBack: () => _navigateTo(20), // Return to Casino Hub
      );
      case 23: return CasHighLowView(
        userData: widget.userData,
        onStateChange: _updateUserStats,
        onBack: () => _navigateTo(20),
      );
      case 24: return CityMapView(
        userData: widget.userData,
        onBack: () => _navigateTo(0),
        onNavigate: _navigateTo,
      );






      default: return DashboardView(userData: widget.userData);
    }
  }

  // 👇 This was kept because it's used by your AppBar tooltips!
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

      // 👇 THIS IS THE MODULAR DRAWER!
      endDrawer: MainHubDrawer(
        username: username,
        activeCooldowns: _activeCooldowns,
        unreadEventsCount: _unreadEventsCount,
        hospitalExpiry: hospitalExpiry,
        jailExpiry: jailExpiry,
        heat: heat,
        hasBazaar: hasBazaar,
        onNavigate: _navigateTo,
        onLogout: _logout,
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

  // 👇 These two helpers are kept because your AppBar needs them!
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
}