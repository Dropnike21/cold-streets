import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

import '../api_config.dart';
import 'auth_view.dart';
import 'main_hub.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tutorial_state.dart';

mixin MainHubLogic on State<MainHub> {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  final TutorialState tutState = TutorialState();

  static bool hasPlayedIntro = false;
  bool showIntroStory = false;

  int lastReadMissionExp = 0;
  bool isWaitingForMessage = false;
  int previousAnonExp = 0;

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
  late int maxEnergy; // 🚨 Added Max Energy
  late int nerve;
  late int maxNerve;
  late int hp;
  late int maxHp;     // 🚨 Added Max HP
  late double heat;
  String? hospitalExpiry;
  String? jailExpiry;

  late int level;
  late int exp;
  late bool levelHolding;
  int currentJobId = 0;

  int selectedIndex = 0;
  int activeCompanyId = 0;
  int infoBrokerTabIndex = 0;

  Timer? syncTimer;
  Timer? countdownTimer;

  int regenSecondsLeft = 30;
  List<Map<String, dynamic>> activeCooldowns = [];
  int unreadEventsCount = 0;

  int parseSafeInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double parseDouble(dynamic value) {
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
    dirtyCash = parseSafeInt(widget.userData['dirty_cash']);
    cleanCash = parseSafeInt(widget.userData['clean_cash']);
    creds = parseSafeInt(widget.userData['cred']);
    casinoTokens = parseSafeInt(widget.userData['casino_tokens']);
    goldBars = parseSafeInt(widget.userData['gold_bars']);
    influence = parseSafeInt(widget.userData['influence']);

    energy = parseSafeInt(widget.userData['energy']);
    maxEnergy = parseSafeInt(widget.userData['max_energy']);
    if (maxEnergy == 0) maxEnergy = 100; // Fallback if DB doesn't send it yet

    nerve = parseSafeInt(widget.userData['nerve']);
    maxNerve = parseSafeInt(widget.userData['max_nerve']);
    if (maxNerve == 0) maxNerve = 10;

    hp = parseSafeInt(widget.userData['hp']);
    maxHp = parseSafeInt(widget.userData['max_hp']);
    if (maxHp == 0) maxHp = 100; // Fallback if DB doesn't send it yet

    heat = parseDouble(widget.userData['heat']);
    level = parseSafeInt(widget.userData['level']);
    if (level == 0) level = 1;
    exp = parseSafeInt(widget.userData['exp']);
    levelHolding = widget.userData['level_holding'] == true;
    currentJobId = parseSafeInt(widget.userData['current_job_id']);

    previousAnonExp = getAnonExp();
    checkIntroStatus();

    tutState.load(userId).then((_) {
      if (mounted) setState(() {});
    });

    startTelemetrySync();
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    countdownTimer?.cancel();
    super.dispose();
  }

  void checkIntroStatus() {
    if (hasPlayedIntro) return;
    if (getAnonExp() == 1) {
      setState(() => showIntroStory = true);
    }
  }

  int getAnonExp() {
    Map<String, dynamic> contactExp = {};
    if (widget.userData['contact_exp'] != null) {
      contactExp = widget.userData['contact_exp'] is String
          ? jsonDecode(widget.userData['contact_exp'])
          : Map<String, dynamic>.from(widget.userData['contact_exp']);
    }
    return parseSafeInt(contactExp['anonymous'] ?? 1);
  }

  void customStateUpdate(Map<String, dynamic> updatedStats) {
    updateUserStats(updatedStats);
  }

  void startTelemetrySync() {
    syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => fetchLiveStatus());
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      bool updated = false;
      if (regenSecondsLeft > 0) { regenSecondsLeft--; updated = true; }
      else { regenSecondsLeft = 30; updated = true; }
      if (activeCooldowns.isNotEmpty) {
        for (var cd in activeCooldowns) {
          if (cd['seconds_left'] > 0) { cd['seconds_left']--; updated = true; }
        }
      }
      if (updated) setState(() {});
    });
  }

  Future<void> fetchLiveStatus() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('${ApiConfig.baseUrl}/auth/status/$userId')),
        http.get(Uri.parse('${ApiConfig.baseUrl}/events/$userId?limit=1'))
      ]);
      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);
        if (mounted) {
          updateUserStats(data['user']);
          List<Map<String, dynamic>> safeCooldowns = [];
          if (data['cooldowns'] != null) {
            for (var c in data['cooldowns']) safeCooldowns.add({'type': c['type'].toString(), 'seconds_left': double.parse(c['seconds_left'].toString()).toInt()});
          }
          setState(() => activeCooldowns = safeCooldowns);
        }
      }
      if (responses[1].statusCode == 200) {
        if (mounted) setState(() => unreadEventsCount = jsonDecode(responses[1].body)['unread_count'] ?? 0);
      }
    } catch (e) {
      debugPrint("SYNC NETWORK ERROR: $e");
    }
  }

  void updateUserStats(Map<String, dynamic> updatedStats) {
    if (!mounted) return;

    // 🚨 RESTORED: Save PREVIOUS state for Auto-Kick BEFORE updating
    bool wasInHosp = hospitalExpiry != null && DateTime.parse(hospitalExpiry!).toLocal().isAfter(DateTime.now());
    bool wasInJail = jailExpiry != null && DateTime.parse(jailExpiry!).toLocal().isAfter(DateTime.now());

    setState(() {
      dirtyCash = parseSafeInt(updatedStats['dirty_cash'] ?? dirtyCash);
      cleanCash = parseSafeInt(updatedStats['clean_cash'] ?? cleanCash);
      creds = parseSafeInt(updatedStats['cred'] ?? creds);
      casinoTokens = parseSafeInt(updatedStats['casino_tokens'] ?? casinoTokens);
      goldBars = parseSafeInt(updatedStats['gold_bars'] ?? goldBars);
      influence = parseSafeInt(updatedStats['influence'] ?? influence);
      if (updatedStats.containsKey('has_bazaar')) hasBazaar = updatedStats['has_bazaar'] == true;

      // Update expiry only if sent to prevent nulling out
      if (updatedStats.containsKey('hospital_expires_at')) hospitalExpiry = updatedStats['hospital_expires_at'];
      if (updatedStats.containsKey('jail_expires_at')) jailExpiry = updatedStats['jail_expires_at'];

      // 🚨 RESTORED: Check CURRENT state for Auto-Kick
      bool nowInHosp = hospitalExpiry != null && DateTime.parse(hospitalExpiry!).toLocal().isAfter(DateTime.now());
      bool nowInJail = jailExpiry != null && DateTime.parse(jailExpiry!).toLocal().isAfter(DateTime.now());

      currentJobId = parseSafeInt(updatedStats['current_job_id'] ?? currentJobId);
      level = parseSafeInt(updatedStats['level'] ?? level);
      exp = parseSafeInt(updatedStats['exp'] ?? exp);
      if (updatedStats.containsKey('level_holding')) levelHolding = updatedStats['level_holding'] == true;

      // --- TASK 4 STAT WATCHER ---
      double oldStr = parseDouble(widget.userData['stat_str']);
      double liveStr = parseDouble(updatedStats['stat_str'] ?? widget.userData['stat_str']);
      double oldDef = parseDouble(widget.userData['stat_def']);
      double liveDef = parseDouble(updatedStats['stat_def'] ?? widget.userData['stat_def']);
      double oldDex = parseDouble(widget.userData['stat_dex']);
      double liveDex = parseDouble(updatedStats['stat_dex'] ?? widget.userData['stat_dex']);
      double oldSpd = parseDouble(widget.userData['stat_spd']);
      double liveSpd = parseDouble(updatedStats['stat_spd'] ?? widget.userData['stat_spd']);

      int prevEnergy = parseSafeInt(widget.userData['energy']);
      int newEnergy = parseSafeInt(updatedStats['energy'] ?? prevEnergy);

      if (getAnonExp() == 4 && prevEnergy > newEnergy) {
        int energySpent = prevEnergy - newEnergy;
        if (liveStr > oldStr) { tutState.tut4EnergyStr += energySpent; tutState.saveInt(userId, 'tut4EnergyStr', tutState.tut4EnergyStr); }
        else if (liveDef > oldDef) { tutState.tut4EnergyDef += energySpent; tutState.saveInt(userId, 'tut4EnergyDef', tutState.tut4EnergyDef); }
        else if (liveDex > oldDex) { tutState.tut4EnergyDex += energySpent; tutState.saveInt(userId, 'tut4EnergyDex', tutState.tut4EnergyDex); }
        else if (liveSpd > oldSpd) { tutState.tut4EnergySpd += energySpent; tutState.saveInt(userId, 'tut4EnergySpd', tutState.tut4EnergySpd); }
      }

      energy = newEnergy;
      maxEnergy = parseSafeInt(updatedStats['max_energy'] ?? maxEnergy);
      nerve = parseSafeInt(updatedStats['nerve'] ?? nerve);
      maxNerve = parseSafeInt(updatedStats['max_nerve'] ?? maxNerve);
      hp = parseSafeInt(updatedStats['hp'] ?? hp);
      maxHp = parseSafeInt(updatedStats['max_hp'] ?? maxHp);
      heat = parseDouble(updatedStats['heat'] ?? heat);

      int oldCrimeExp = parseSafeInt(widget.userData['crime_exp']);
      int liveCrimeExp = parseSafeInt(updatedStats['crime_exp'] ?? widget.userData['crime_exp']);

      if (liveCrimeExp > oldCrimeExp && getAnonExp() == 3) {
        tutState.tut3CrimesDoneCount++;
        tutState.saveInt(userId, 'tut3Crimes', tutState.tut3CrimesDoneCount);
      }

      if (updatedStats.containsKey('contact_exp')) {
        widget.userData['contact_exp'] = updatedStats['contact_exp'];
        int newAnonExp = getAnonExp();
        if (previousAnonExp > 0 && newAnonExp > previousAnonExp) {
          isWaitingForMessage = true;
          Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => isWaitingForMessage = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("New encrypted message received.", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.orangeAccent),
              );
            }
          });
        }
        previousAnonExp = newAnonExp;
      }

      // Sync local widget data
      widget.userData['dirty_cash'] = dirtyCash;
      widget.userData['clean_cash'] = cleanCash;
      widget.userData['cred'] = creds;
      widget.userData['energy'] = energy;
      widget.userData['max_energy'] = maxEnergy;
      widget.userData['nerve'] = nerve;
      widget.userData['max_nerve'] = maxNerve;
      widget.userData['hp'] = hp;
      widget.userData['max_hp'] = maxHp;
      widget.userData['heat'] = heat;
      widget.userData['level'] = level;
      widget.userData['exp'] = exp;
      widget.userData['crime_exp'] = liveCrimeExp;
      widget.userData['level_holding'] = levelHolding;
      widget.userData['stat_str'] = liveStr;
      widget.userData['stat_def'] = liveDef;
      widget.userData['stat_dex'] = liveDex;
      widget.userData['stat_spd'] = liveSpd;

      if (updatedStats.containsKey('hospital_expires_at')) widget.userData['hospital_expires_at'] = hospitalExpiry;
      if (updatedStats.containsKey('jail_expires_at')) widget.userData['jail_expires_at'] = jailExpiry;

      // 🚨 RESTORED: Auto-Kick Execution
      if (!wasInJail && nowInJail) {
        navigateTo(14); // Rip them to Jail
      } else if (!wasInHosp && nowInHosp) {
        navigateTo(15); // Rip them to Hospital
      }
    });
  }

  void logout() {
    syncTimer?.cancel();
    countdownTimer?.cancel();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthView()));
  }

  void navigateTo(int index) {
    // 🚨 RESTORED: Frontend Gatekeeper
    bool inHosp = hospitalExpiry != null && DateTime.parse(hospitalExpiry!).toLocal().isAfter(DateTime.now());
    bool inJail = jailExpiry != null && DateTime.parse(jailExpiry!).toLocal().isAfter(DateTime.now());

    if (inHosp || inJail) {
      List<int> allowedIndices = [0, 3, 4, 8, 9, 13, 14, 15, 16, 17, 24, 29];
      if (!allowedIndices.contains(index)) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(inHosp ? "ACCESS DENIED: You are in the Hospital." : "ACCESS DENIED: You are in State Prison.", style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 2),
            )
        );
        return;
      }
    }

    setState(() {
      selectedIndex = index;

      if (index == 4) tutState.tut2Inv = true;
      if (index == 19) tutState.tut2Prop = true;
      if (index == 9) tutState.tut2Ach = true;

      if (index == 26 && !tutState.tut3Search) { tutState.tut3Search = true; tutState.saveBool(userId, 'tut3Search', true); }
      if (index == 27 && !tutState.tut3Shop) { tutState.tut3Shop = true; tutState.saveBool(userId, 'tut3Shop', true); }
      if (index == 28 && !tutState.tut3Pick) { tutState.tut3Pick = true; tutState.saveBool(userId, 'tut3Pick', true); }
      if (index == 5 && !tutState.tut4Gym) { tutState.tut4Gym = true; tutState.saveBool(userId, 'tut4Gym', true); }

      // 🚨 TASK 5 & 6 Triggers
      if (index == 17 && !tutState.tut5Bank) { tutState.tut5Bank = true; tutState.saveBool(userId, 'tut5Bank', true); }
      if (index == 18 && !tutState.tut5Estate) { tutState.tut5Estate = true; tutState.saveBool(userId, 'tut5Estate', true); }
      if (index == 6 && !tutState.tut6Broker) { tutState.tut6Broker = true; tutState.saveBool(userId, 'tut6Broker', true); }
      if (index == 20 && !tutState.tut6Casino) { tutState.tut6Casino = true; tutState.saveBool(userId, 'tut6Casino', true); }
    });

    // 🚨 RESTORED: Trigger universal intel pop-up
    checkAndShowIntel('nav_$index');
  }

  // 🚨 RESTORED: Universal Intel Engine
  Future<void> checkAndShowIntel(String intelKey) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final context = scaffoldKey.currentContext;
    if (context == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    bool hasVisited = prefs.getBool('intel_${intelKey}_$userId') ?? false;
    if (hasVisited) return;

    String title = "";
    String body = "";
    IconData icon = Icons.info_outline;

    switch (intelKey) {
      case 'vitals':
        title = "HUD VITALS";
        body = "Your lifeblood. Energy dictates gym training, Nerve is used for crimes, and HP keeps you alive. Watch your Wanted Level (Heat) closely, or you'll end up in prison.";
        icon = Icons.monitor_heart; break;
      case 'nav_4':
        title = "INVENTORY";
        body = "Your stash. Use consumables to recover stats, equip gear for battles, and manage the loot you've stolen or purchased.";
        icon = Icons.backpack; break;
      case 'nav_19':
        title = "PROPERTIES";
        body = "Where you lay your head. Better properties increase your maximum happiness and allow you to hold more items in your vault.";
        icon = Icons.house; break;
      case 'nav_9':
        title = "ACHIEVEMENTS";
        body = "Your street cred. Hit major milestones in crimes, combat, and wealth to earn permanent stat boosts and unique titles.";
        icon = Icons.military_tech; break;
      case 'nav_24':
        title = "CITY MAP";
        body = "Your gateway to the greater metropolis. Use this to travel between major districts, locate player-owned properties, and scout syndicate territories.";
        icon = Icons.map; break;
      case 'nav_17':
        title = "THE BANK";
        body = "A safe haven for your Clean Cash. Money stored here is protected from street attacks and earns daily interest. Dirty Cash must be laundered first.";
        icon = Icons.account_balance; break;
      case 'nav_15':
        title = "CITY HOSPITAL";
        body = "If you get zeroed out on the streets, you'll wake up here. You can also buy medical supplies to restore your HP instantly.";
        icon = Icons.local_hospital; break;
      case 'nav_14':
        title = "STATE PRISON";
        body = "Getting busted lands you here. You can serve your time, try to break out, or bust out other players to earn respect.";
        icon = Icons.gavel; break;
      case 'nav_6':
        title = "CREDIT BROKER";
        body = "The underground market. Trade premium Credits with other players, buy restricted items, and check the fluctuating market rates.";
        icon = Icons.diamond; break;
      case 'nav_3':
        title = "THE SYNDICATE";
        body = "Survival is a team sport. Join a syndicate to participate in organized wars, unlock faction perks, and pool resources.";
        icon = Icons.group; break;
      default:
        return;
    }

    await prefs.setBool('intel_${intelKey}_$userId', true);

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: const Color(0xFF161616),
                      border: Border.all(color: const Color(0xFF39FF14), width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: const Color(0xFF39FF14).withOpacity(0.2), blurRadius: 10, spreadRadius: 2)]
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: const Color(0xFF39FF14), size: 40),
                      const SizedBox(height: 16),
                      const Text("NEW INTEL ACQUIRED", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity, height: 40,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF39FF14)), backgroundColor: const Color(0xFF39FF14).withOpacity(0.1)),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("ACKNOWLEDGE", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                      )
                    ],
                  )
              )
          );
        }
    );
  }
}