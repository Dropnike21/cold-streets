import 'package:shared_preferences/shared_preferences.dart';

class TutorialState {
  // Temporary Memory Flags (Reset on app restart)
  bool tut1Vitals = false;
  bool tut1Assets = false;
  bool tut2Inv = false;
  bool tut2Prop = false;
  bool tut2Ach = false;

  // Persistent Flags (Survive app restart)
  bool tut3Search = false;
  bool tut3Shop = false;
  bool tut3Pick = false;
  int tut3CrimesDoneCount = 0;

  // Load from Device
  Future<void> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    tut3Search = prefs.getBool('tut3Search_$userId') ?? false;
    tut3Shop = prefs.getBool('tut3Shop_$userId') ?? false;
    tut3Pick = prefs.getBool('tut3Pick_$userId') ?? false;
    tut3CrimesDoneCount = prefs.getInt('tut3Crimes_$userId') ?? 0;
  }

  // Save to Device
  Future<void> saveBool(String userId, String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${key}_$userId', value);
  }

  Future<void> saveInt(String userId, String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${key}_$userId', value);
  }

  // The Smart Beacon Engine (Moved out of MainHub!)
  String? getActiveBeacon({
    required bool showIntroStory,
    required bool isWaitingForMessage,
    required int anonExp,
    required int lastReadMissionExp,
    required bool isDrawerOpen,
    required bool isDesktop,
    required int selectedIndex,
  }) {
    if (showIntroStory) return null;
    if (isWaitingForMessage) return null;

    if (lastReadMissionExp < anonExp && anonExp <= 3) {
      if (selectedIndex != 29) return 'fab_phone';
      return 'contact_anonymous';
    }

    String? drawerBeacon(String targetId) {
      if (isDesktop) return targetId;
      if (isDrawerOpen) return targetId;
      return 'btn_menu';
    }

    if (anonExp == 1) {
      if (!tut1Vitals) return 'hud_vitals';
      if (!tut1Assets) return drawerBeacon('drawer_assets');
      if (selectedIndex != 29) return 'fab_phone';
      return 'btn_verify_anon';
    }

    if (anonExp == 2) {
      if (!tut2Inv) return drawerBeacon('nav_inventory');
      if (!tut2Prop) return drawerBeacon('nav_properties');
      if (!tut2Ach) return drawerBeacon('nav_achievements');
      if (selectedIndex != 29) return 'fab_phone';
      return 'btn_verify_anon';
    }

    if (anonExp == 3) {
      if (!tut3Search || !tut3Shop || !tut3Pick) {
        if (selectedIndex != 1 && selectedIndex != 26 && selectedIndex != 27 && selectedIndex != 28) return 'nav_streets';
        if (!tut3Search && selectedIndex == 1) return 'cat_search';
        if (!tut3Shop && selectedIndex == 1) return 'cat_shop';
        if (!tut3Pick && selectedIndex == 1) return 'cat_pickpocket';
      }

      if (tut3CrimesDoneCount < 20) {
        if (selectedIndex != 1 && selectedIndex != 26 && selectedIndex != 27 && selectedIndex != 28) return 'nav_streets';
        return 'btn_do_crime';
      }

      if (selectedIndex != 29) return 'fab_phone';
      return 'btn_verify_anon';
    }

    return null;
  }
}