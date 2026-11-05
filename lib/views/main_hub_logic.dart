import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/game_http.dart' as http;
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
  StreamSubscription<AuthState>? _authSubscription;
  bool _leavingGame = false;

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
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (event) {
        if (event.event == AuthChangeEvent.signedOut && mounted) {
          _returnToSignIn();
        }
      },
      onError: (Object error) {
        debugPrint('Cold Streets authentication session error.');
      },
    );
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
      if (mounted) {
        setState(() {});
        syncTutorialProgress();
      }
    });

    startTelemetrySync();
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    countdownTimer?.cancel();
    _authSubscription?.cancel();
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

  void _applyTutorialProgress(Map<String, dynamic> progress) {
    final visitsRaw = progress['visits'];
    final visits = visitsRaw is Map ? Map<String, dynamic>.from(visitsRaw) : <String, dynamic>{};
    final energyRaw = progress['energy_by_stat'];
    final energyByStat = energyRaw is Map ? Map<String, dynamic>.from(energyRaw) : <String, dynamic>{};
    final rep = getAnonExp();
    setState(() {
      if (rep == 1) {
        tutState.tut1Vitals = visits['vitals'] == true;
        tutState.tut1Assets = visits['assets'] == true;
      } else if (rep == 2) {
        tutState.tut2Inv = visits['inventory'] == true;
        tutState.tut2Prop = visits['properties'] == true;
        tutState.tut2Ach = visits['achievements'] == true;
      } else if (rep == 3) {
        tutState.tut3Search = visits['crime_searching'] == true;
        tutState.tut3Shop = visits['crime_shoplifting'] == true;
        tutState.tut3Pick = visits['crime_pickpocketing'] == true;
        tutState.tut3CrimesDoneCount = parseSafeInt(progress['successful_crimes']);
      } else if (rep == 4) {
        tutState.tut4Gym = visits['gym'] == true;
        tutState.tut4EnergyStr = parseSafeInt(energyByStat['str']);
        tutState.tut4EnergyDef = parseSafeInt(energyByStat['def']);
        tutState.tut4EnergyDex = parseSafeInt(energyByStat['dex']);
        tutState.tut4EnergySpd = parseSafeInt(energyByStat['spd']);
      } else if (rep == 5) {
        tutState.tut5Bank = visits['bank'] == true;
        tutState.tut5Estate = visits['real_estate'] == true;
      } else if (rep == 6) {
        tutState.tut6Broker = visits['credit_broker'] == true;
        tutState.tut6Casino = visits['casino'] == true;
      }
    });
  }

  Future<void> syncTutorialProgress() async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/missions/details/$userId/anonymous'));
      if (response.statusCode != 200 || !mounted) return;
      final data = jsonDecode(response.body);
      if (data['progress'] is Map) {
        _applyTutorialProgress(Map<String, dynamic>.from(data['progress']));
      }
    } catch (_) {
      debugPrint('Tutorial progress sync unavailable.');
    }
  }

  Future<void> recordTutorialVisit(String visit) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/missions/tutorial/visit'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'visit': visit}),
      );
      if (response.statusCode != 200 || !mounted) return;
      final data = jsonDecode(response.body);
      if (data['progress'] is Map) {
        _applyTutorialProgress(Map<String, dynamic>.from(data['progress']));
      }
    } catch (_) {
      debugPrint('Tutorial visit could not be recorded.');
    }
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

      double liveStr = parseDouble(updatedStats['stat_str'] ?? widget.userData['stat_str']);
      double liveDef = parseDouble(updatedStats['stat_def'] ?? widget.userData['stat_def']);
      double liveDex = parseDouble(updatedStats['stat_dex'] ?? widget.userData['stat_dex']);
      double liveSpd = parseDouble(updatedStats['stat_spd'] ?? widget.userData['stat_spd']);

      energy = parseSafeInt(updatedStats['energy'] ?? energy);
      maxEnergy = parseSafeInt(updatedStats['max_energy'] ?? maxEnergy);
      nerve = parseSafeInt(updatedStats['nerve'] ?? nerve);
      maxNerve = parseSafeInt(updatedStats['max_nerve'] ?? maxNerve);
      hp = parseSafeInt(updatedStats['hp'] ?? hp);
      maxHp = parseSafeInt(updatedStats['max_hp'] ?? maxHp);
      heat = parseDouble(updatedStats['heat'] ?? heat);
      int liveCrimeExp = parseSafeInt(updatedStats['crime_exp'] ?? widget.userData['crime_exp']);

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

  void _returnToSignIn() {
    if (_leavingGame || !mounted) return;
    _leavingGame = true;
    syncTimer?.cancel();
    countdownTimer?.cancel();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthView()),
      (route) => false,
    );
  }

  Future<void> logout() async {
    if (_leavingGame) return;
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) _returnToSignIn();
    } on AuthException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign out failed. Please try again.')),
        );
      }
    }
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

      // Server-owned tutorial progress; local flags mirror backend state.
    });

    const tutorialVisits = <int, String>{
      4: 'inventory', 19: 'properties', 9: 'achievements',
      26: 'crime_searching', 27: 'crime_shoplifting', 28: 'crime_pickpocketing',
      5: 'gym', 17: 'bank', 18: 'real_estate',
      6: 'credit_broker', 20: 'casino',
    };
    final visit = tutorialVisits[index];
    if (visit != null) recordTutorialVisit(visit);

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
        body = "Lifetime milestones across the city. Progress is shown only for achievement categories backed by authoritative server telemetry.";
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
        body = "A recovered long-term progression catalog. Cred balance and upgrade definitions are visible, but earning rules, pricing, and upgrade effects are still being reconciled, so purchases are paused.";
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