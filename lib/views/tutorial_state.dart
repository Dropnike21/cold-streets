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

  // 🚨 TASK 4: GYM & STAT TRACKERS
  bool tut4Gym = false;
  int tut4EnergyStr = 0;
  int tut4EnergyDef = 0;
  int tut4EnergyDex = 0;
  int tut4EnergySpd = 0;

  // 🚨 TASK 5 & 6: DISTRICT EXPLORATION
  bool tut5Bank = false;
  bool tut5Estate = false;
  bool tut6Broker = false;
  bool tut6Casino = false;

  // Mission progress is server-owned. These fields are only an in-memory
  // presentation mirror used by the tutorial beacon system.
  Future<void> load(String _) async {}

  // The Smart Beacon Engine
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

    if (lastReadMissionExp < anonExp && anonExp <= 4) { // 🚨 Expanded to cover Task 4
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
        if (selectedIndex != 1 && selectedIndex != 26 && selectedIndex != 27 && selectedIndex != 28) {
          return isDesktop ? 'drawer_streets' : 'nav_streets';
        }
        if (!tut3Search && selectedIndex == 1) return 'cat_search';
        if (!tut3Shop && selectedIndex == 1) return 'cat_shop';
        if (!tut3Pick && selectedIndex == 1) return 'cat_pickpocket';
      }

      if (tut3CrimesDoneCount < 20) {
        if (selectedIndex != 1 && selectedIndex != 26 && selectedIndex != 27 && selectedIndex != 28) {
          return isDesktop ? 'drawer_streets' : 'nav_streets';
        }
        return 'btn_do_crime';
      }

      if (selectedIndex != 29) return 'fab_phone';
      return 'btn_verify_anon';
    }

    // 🚨 TASK 4 BEACON LOGIC
    if (anonExp == 4) {
      if (!tut4Gym) {
        if (selectedIndex != 5) return isDesktop ? 'drawer_gym' : 'nav_gym';
      }
      if (tut4EnergyStr < 150 || tut4EnergyDef < 150 || tut4EnergyDex < 150 || tut4EnergySpd < 150) {
        if (selectedIndex != 5) return isDesktop ? 'drawer_gym' : 'nav_gym';
        return null; // They are in the gym, let them train freely!
      }
      if (selectedIndex != 29) return 'fab_phone';
      return 'btn_verify_anon';
    }
    if (anonExp == 5) {
      if (!tut5Bank || !tut5Estate) return isDesktop ? null : 'btn_menu';
      if (selectedIndex != 29) return 'fab_phone';
      return 'btn_verify_anon';
    }
    if (anonExp == 6) {
      if (!tut6Broker || !tut6Casino) return isDesktop ? null : 'btn_menu';
      if (selectedIndex != 29) return 'fab_phone';
      return 'btn_verify_anon';
    }

    return null;
  }
}