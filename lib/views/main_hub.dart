import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

import '../api_config.dart';
import 'auth_view.dart';
import 'main_hub_drawer.dart';
import 'level_up_overlay.dart';
import 'tutorial_beacon.dart';

// 🚨 MODULAR IMPORTS
import 'tutorial_state.dart';
import 'tutorial_intro_overlay.dart';
import 'main_hub_app_bar.dart';
import 'main_hub_router.dart';

class MainHub extends StatefulWidget {
  final Map<String, dynamic> userData;

  const MainHub({super.key, required this.userData});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TutorialState _tutState = TutorialState();

  static bool _hasPlayedIntro = false;
  bool _showIntroStory = false;

  int _lastReadMissionExp = 0;
  bool _isWaitingForMessage = false;
  int _previousAnonExp = 0;

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

  late int level;
  late int exp;
  late bool levelHolding;
  int currentJobId = 0;

  int _selectedIndex = 0;
  int _activeCompanyId = 0;
  int _infoBrokerTabIndex = 0;

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
    level = _parseSafeInt(widget.userData['level']);
    if (level == 0) level = 1;
    exp = _parseSafeInt(widget.userData['exp']);
    levelHolding = widget.userData['level_holding'] == true;
    currentJobId = _parseSafeInt(widget.userData['current_job_id']);

    _previousAnonExp = _getAnonExp();
    _checkIntroStatus();

    _tutState.load(userId).then((_) {
      if (mounted) setState(() {});
    });

    _startTelemetrySync();
  }

  void _checkIntroStatus() {
    if (_hasPlayedIntro) return;
    if (_getAnonExp() == 1) {
      setState(() => _showIntroStory = true);
    }
  }

  int _getAnonExp() {
    Map<String, dynamic> contactExp = {};
    if (widget.userData['contact_exp'] != null) {
      contactExp = widget.userData['contact_exp'] is String
          ? jsonDecode(widget.userData['contact_exp'])
          : Map<String, dynamic>.from(widget.userData['contact_exp']);
    }
    return _parseSafeInt(contactExp['anonymous'] ?? 1);
  }

  void _customStateUpdate(Map<String, dynamic> updatedStats) {
    _updateUserStats(updatedStats);
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
      if (_regenSecondsLeft > 0) { _regenSecondsLeft--; updated = true; }
      else { _regenSecondsLeft = 30; updated = true; }
      if (_activeCooldowns.isNotEmpty) {
        for (var cd in _activeCooldowns) {
          if (cd['seconds_left'] > 0) { cd['seconds_left']--; updated = true; }
        }
      }
      if (updated) setState(() {});
    });
  }

  Future<void> _fetchLiveStatus() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('${ApiConfig.baseUrl}/auth/status/$userId')),
        http.get(Uri.parse('${ApiConfig.baseUrl}/events/$userId?limit=1'))
      ]);
      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);
        if (mounted) {
          _updateUserStats(data['user']);
          List<Map<String, dynamic>> safeCooldowns = [];
          if (data['cooldowns'] != null) {
            for (var c in data['cooldowns']) safeCooldowns.add({'type': c['type'].toString(), 'seconds_left': double.parse(c['seconds_left'].toString()).toInt()});
          }
          setState(() => _activeCooldowns = safeCooldowns);
        }
      }
      if (responses[1].statusCode == 200) {
        if (mounted) setState(() => _unreadEventsCount = jsonDecode(responses[1].body)['unread_count'] ?? 0);
      }
    } catch (e) {
      debugPrint("SYNC NETWORK ERROR: $e");
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
      // 🚨 1. Save the PREVIOUS state before applying the new stats
      bool wasInHosp = hospitalExpiry != null && DateTime.parse(hospitalExpiry!).toLocal().isAfter(DateTime.now());
      bool wasInJail = jailExpiry != null && DateTime.parse(jailExpiry!).toLocal().isAfter(DateTime.now());

      // 🚨 2. Apply the NEW stats from the database
      hospitalExpiry = updatedStats['hospital_expires_at'];
      jailExpiry = updatedStats['jail_expires_at'];

      // 🚨 3. Check the CURRENT state
      bool nowInHosp = hospitalExpiry != null && DateTime.parse(hospitalExpiry!).toLocal().isAfter(DateTime.now());
      bool nowInJail = jailExpiry != null && DateTime.parse(jailExpiry!).toLocal().isAfter(DateTime.now());

      currentJobId = _parseSafeInt(updatedStats['current_job_id'] ?? currentJobId);
      level = _parseSafeInt(updatedStats['level'] ?? level);
      exp = _parseSafeInt(updatedStats['exp'] ?? exp);
      if (updatedStats.containsKey('level_holding')) levelHolding = updatedStats['level_holding'] == true;

      int oldCrimeExp = _parseSafeInt(widget.userData['crime_exp']);
      int liveCrimeExp = _parseSafeInt(updatedStats['crime_exp'] ?? widget.userData['crime_exp']);

      if (liveCrimeExp > oldCrimeExp && _getAnonExp() == 3) {
        _tutState.tut3CrimesDoneCount++;
        _tutState.saveInt(userId, 'tut3Crimes', _tutState.tut3CrimesDoneCount);
      }
      // 🚨 TASK 4 STAT WATCHER
      int oldStr = _parseSafeInt(widget.userData['stat_str']);
      int liveStr = _parseSafeInt(updatedStats['stat_str'] ?? widget.userData['stat_str']);
      int oldDef = _parseSafeInt(widget.userData['stat_def']);
      int liveDef = _parseSafeInt(updatedStats['stat_def'] ?? widget.userData['stat_def']);
      int oldDex = _parseSafeInt(widget.userData['stat_dex']);
      int liveDex = _parseSafeInt(updatedStats['stat_dex'] ?? widget.userData['stat_dex']);
      int oldSpd = _parseSafeInt(widget.userData['stat_spd']);
      int liveSpd = _parseSafeInt(updatedStats['stat_spd'] ?? widget.userData['stat_spd']);

      int oldEnergy = energy; // 'energy' holds the current UI state before updating

      if (_getAnonExp() == 4 && oldEnergy > energy) { // Energy dropped!
        int energySpent = oldEnergy - energy;
        if (liveStr > oldStr) { _tutState.tut4EnergyStr += energySpent; _tutState.saveInt(userId, 'tut4EnergyStr', _tutState.tut4EnergyStr); }
        else if (liveDef > oldDef) { _tutState.tut4EnergyDef += energySpent; _tutState.saveInt(userId, 'tut4EnergyDef', _tutState.tut4EnergyDef); }
        else if (liveDex > oldDex) { _tutState.tut4EnergyDex += energySpent; _tutState.saveInt(userId, 'tut4EnergyDex', _tutState.tut4EnergyDex); }
        else if (liveSpd > oldSpd) { _tutState.tut4EnergySpd += energySpent; _tutState.saveInt(userId, 'tut4EnergySpd', _tutState.tut4EnergySpd); }
      }

      if (updatedStats.containsKey('contact_exp')) {
        widget.userData['contact_exp'] = updatedStats['contact_exp'];

        int newAnonExp = _getAnonExp();
        if (_previousAnonExp > 0 && newAnonExp > _previousAnonExp) {
          _isWaitingForMessage = true;

          Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _isWaitingForMessage = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text("New encrypted message received.", style: TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.orangeAccent
                ),
              );
            }
          });
        }
        _previousAnonExp = newAnonExp;
      }

      widget.userData['dirty_cash'] = dirtyCash;
      widget.userData['clean_cash'] = cleanCash;
      widget.userData['cred'] = creds;
      widget.userData['energy'] = energy;
      widget.userData['nerve'] = nerve;
      widget.userData['max_nerve'] = maxNerve;
      widget.userData['hp'] = hp;
      widget.userData['heat'] = heat;
      widget.userData['level'] = level;
      widget.userData['exp'] = exp;
      widget.userData['crime_exp'] = liveCrimeExp;
      widget.userData['level_holding'] = levelHolding;
      // 🚨 CACHE THE LIVE STATS
      widget.userData['stat_str'] = liveStr;
      widget.userData['stat_def'] = liveDef;
      widget.userData['stat_dex'] = liveDex;
      widget.userData['stat_spd'] = liveSpd;
      // 🚨 4. AUTO-KICK LOGIC
      // If they weren't in jail/hosp a second ago, but they are NOW, force them there!
      if (!wasInJail && nowInJail) {
        _navigateTo(14); // Force to Jail View
      } else if (!wasInHosp && nowInHosp) {
        _navigateTo(15); // Force to Hospital View
      }
    });
  }

  void _logout() {
    _syncTimer?.cancel();
    _countdownTimer?.cancel();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthView()));
  }

  void _navigateTo(int index) {
    // 🚨 FRONTEND GATEKEEPER: Check if player is incapacitated
    bool inHosp = hospitalExpiry != null && DateTime.parse(hospitalExpiry!).toLocal().isAfter(DateTime.now());
    bool inJail = jailExpiry != null && DateTime.parse(jailExpiry!).toLocal().isAfter(DateTime.now());

    if (inHosp || inJail) {
      // 🚨 THE WHITELIST (Matches your server.js whitelist)
      // 0: Hub, 4: Inventory, 8: City Hall, 9: Achievements, 10: Events,
      // 13: Info Broker, 14: Jail, 15: Hospital, 16: University, 17: Bank, 29: Burner Phone
      List<int> allowedIndices = [0, 4, 8, 9, 10, 13, 14, 15, 16, 17, 29];

      if (!allowedIndices.contains(index)) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                inHosp ? "ACCESS DENIED: You are in the Hospital." : "ACCESS DENIED: You are in State Prison.",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 2),
            )
        );
        return; // 🚨 BLOCKS THE NAVIGATION
      }
    }

    setState(() {
      _selectedIndex = index;

      if (index == 4) _tutState.tut2Inv = true;
      if (index == 19) _tutState.tut2Prop = true;
      if (index == 9) _tutState.tut2Ach = true;

      if (index == 26 && !_tutState.tut3Search) {
        _tutState.tut3Search = true;
        _tutState.saveBool(userId, 'tut3Search', true);
      }
      if (index == 27 && !_tutState.tut3Shop) {
        _tutState.tut3Shop = true;
        _tutState.saveBool(userId, 'tut3Shop', true);
      }
      if (index == 28 && !_tutState.tut3Pick) {
        _tutState.tut3Pick = true;
        _tutState.saveBool(userId, 'tut3Pick', true);
      }
      // 🚨 TRACK GYM NAVIGATION
      if (index == 5 && !_tutState.tut4Gym) {
        _tutState.tut4Gym = true;
        _tutState.saveBool(userId, 'tut4Gym', true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 900;

          String? activeBeacon = _tutState.getActiveBeacon(
            showIntroStory: _showIntroStory,
            isWaitingForMessage: _isWaitingForMessage,
            anonExp: _getAnonExp(),
            lastReadMissionExp: _lastReadMissionExp,
            isDrawerOpen: _scaffoldKey.currentState?.isDrawerOpen ?? false,
            isDesktop: isDesktop,
            selectedIndex: _selectedIndex,
          );

          int anonExp = _getAnonExp();

          List<int> activeRoutes = [0, 1];
          List<BottomNavigationBarItem> navItems = [
            const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Hub"),
            BottomNavigationBarItem(icon: TutorialBeacon(id: 'nav_streets', activeId: activeBeacon, child: const Icon(Icons.local_fire_department)), label: "Streets"),
          ];

          if (anonExp >= 4) {
            activeRoutes.add(5);
            navItems.add(BottomNavigationBarItem(icon: TutorialBeacon(id: 'nav_gym', activeId: activeBeacon, child: const Icon(Icons.fitness_center)), label: "Gym"));
          }

          if (anonExp >= 50) {
            activeRoutes.addAll([24, 3]);
            navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"));
            navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.group), label: "Syndicate"));
          }

          int baseRoute = 0;
          if (_selectedIndex == 0) baseRoute = 0;
          else if (_selectedIndex == 1 || _selectedIndex == 26 || _selectedIndex == 27 || _selectedIndex == 28) baseRoute = 1;
          else if (_selectedIndex == 5) baseRoute = 5;
          else if (_selectedIndex == 24) baseRoute = 24;
          else if (_selectedIndex == 3) baseRoute = 3;

          int visualNavIndex = activeRoutes.indexOf(baseRoute);
          if (visualNavIndex == -1) visualNavIndex = 0;

          Widget gameContent = Scaffold(
            key: _scaffoldKey,
            onDrawerChanged: (isOpen) => setState(() {}),
            backgroundColor: const Color(0xFF121212),

            appBar: MainHubAppBar(
              isDesktop: isDesktop,
              activeBeacon: activeBeacon,
              username: username,
              userId: userId,
              level: level,
              exp: exp,
              levelHolding: levelHolding,
              energy: energy,
              nerve: nerve,
              hp: hp,
              heat: heat,
              hospitalExpiry: hospitalExpiry,
              jailExpiry: jailExpiry,
              // 🚨 FIX: Removed the non-existent setter!
              onMenuPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
              onVitalsTap: () => setState(() => _tutState.tut1Vitals = true),
              onLevelUp: () => setState(() { levelHolding = false; widget.userData['level_holding'] = false; }),
            ),

            drawer: isDesktop ? null : MainHubDrawer(
              isMobile: true,
              username: username, dirtyCash: dirtyCash, cleanCash: cleanCash, goldBars: goldBars, creds: creds, influence: influence, unreadEventsCount: _unreadEventsCount, hasBazaar: hasBazaar,
              anonExp: anonExp, activeBeacon: activeBeacon,
              onAssetTap: () { setState(() => _tutState.tut1Assets = true); if (!isDesktop) Navigator.pop(context); },
              onNavigate: _navigateTo, onLogout: _logout,
            ),

            body: MainHubRouter.buildScreen(
              selectedIndex: _selectedIndex,
              userData: widget.userData,
              onStateChange: _customStateUpdate,
              onNavigate: _navigateTo,
              activeCompanyId: _activeCompanyId,
              infoBrokerTabIndex: _infoBrokerTabIndex,
              setInfoBrokerTab: (val) => setState(() => _infoBrokerTabIndex = val),
              setCompanyAndNavigate: (companyId, viewIndex) => setState(() { _activeCompanyId = companyId; _selectedIndex = viewIndex; }),
              activeBeacon: activeBeacon,
              isWaitingForMessage: _isWaitingForMessage,
              tutState: _tutState,
              onMissionRead: () {
                int currentAnonExp = _getAnonExp();
                if (_lastReadMissionExp < currentAnonExp) {
                  setState(() => _lastReadMissionExp = currentAnonExp);
                }
              },
            ),

            bottomNavigationBar: isDesktop ? null : Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF39FF14), width: 0.5))),
              child: BottomNavigationBar(
                backgroundColor: Colors.black, type: BottomNavigationBarType.fixed, selectedItemColor: const Color(0xFF39FF14), unselectedItemColor: Colors.grey[700], selectedFontSize: 10, unselectedFontSize: 10, iconSize: 22,
                currentIndex: visualNavIndex,
                onTap: (index) => _navigateTo(activeRoutes[index]),
                items: navItems,
              ),
            ),

            floatingActionButton: (_selectedIndex == 0 && anonExp < 50)
                ? TutorialBeacon(
              id: 'fab_phone',
              activeId: activeBeacon,
              borderRadius: 16,
              child: FloatingActionButton(
                onPressed: () => _navigateTo(29),
                backgroundColor: const Color(0xFF0A0F14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.orangeAccent, width: 2)),
                child: const Icon(Icons.phone_android, color: Colors.orangeAccent, size: 28),
              ),
            )
                : null,
          );

          return Stack(
            children: [
              if (isDesktop)
                Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: MainHubDrawer(
                        isMobile: false,
                        username: username, dirtyCash: dirtyCash, cleanCash: cleanCash, goldBars: goldBars, creds: creds, influence: influence, unreadEventsCount: _unreadEventsCount, hasBazaar: hasBazaar,
                        anonExp: anonExp, activeBeacon: activeBeacon,
                        onAssetTap: () => setState(() => _tutState.tut1Assets = true),
                        onNavigate: _navigateTo, onLogout: _logout,
                      ),
                    ),
                    Expanded(child: gameContent),
                  ],
                )
              else
                gameContent,

              if (_showIntroStory) TutorialIntroOverlay(onContinue: () {
                setState(() {
                  _showIntroStory = false;
                  _hasPlayedIntro = true;
                });
              }),

              LevelUpOverlay(userData: widget.userData, onStateChange: _customStateUpdate),
            ],
          );
        }
    );
  }
}