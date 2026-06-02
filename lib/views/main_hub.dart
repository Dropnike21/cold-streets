import 'package:flutter/material.dart';

import 'main_hub_drawer.dart';
import 'level_up_overlay.dart';
import 'tutorial_beacon.dart';
import 'tutorial_intro_overlay.dart';
import 'main_hub_app_bar.dart';
import 'main_hub_router.dart';

// 🚨 IMPORT THE NEW MIXIN
import 'main_hub_logic.dart';

class MainHub extends StatefulWidget {
  final Map<String, dynamic> userData;

  const MainHub({super.key, required this.userData});

  @override
  State<MainHub> createState() => _MainHubState();
}

// 🚨 INJECT THE MIXIN HERE using 'with'
class _MainHubState extends State<MainHub> with MainHubLogic {

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 900;

          // Note: Variables have lost their underscores since they are now public in the Mixin
          String? activeBeacon = tutState.getActiveBeacon(
            showIntroStory: showIntroStory,
            isWaitingForMessage: isWaitingForMessage,
            anonExp: getAnonExp(),
            lastReadMissionExp: lastReadMissionExp,
            isDrawerOpen: scaffoldKey.currentState?.isDrawerOpen ?? false,
            isDesktop: isDesktop,
            selectedIndex: selectedIndex,
          );

          int anonExp = getAnonExp();

          List<int> activeRoutes = [0, 1];
          List<BottomNavigationBarItem> navItems = [
            const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Hub"),
            BottomNavigationBarItem(icon: TutorialBeacon(id: 'nav_streets', activeId: activeBeacon, child: const Icon(Icons.local_fire_department)), label: "Streets"),
          ];

          if (anonExp >= 4) {
            activeRoutes.add(5);
            navItems.add(BottomNavigationBarItem(icon: TutorialBeacon(id: 'nav_gym', activeId: activeBeacon, child: const Icon(Icons.fitness_center)), label: "Gym"));
          }

          if (anonExp >= 5) {
            activeRoutes.addAll([24, 3]);
            navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"));
            navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.group), label: "Syndicate"));
          }

          int baseRoute = 0;
          if (selectedIndex == 0) baseRoute = 0;
          else if (selectedIndex == 1 || selectedIndex == 26 || selectedIndex == 27 || selectedIndex == 28) baseRoute = 1;
          else if (selectedIndex == 5) baseRoute = 5;
          else if (selectedIndex == 24) baseRoute = 24;
          else if (selectedIndex == 3) baseRoute = 3;

          int visualNavIndex = activeRoutes.indexOf(baseRoute);
          if (visualNavIndex == -1) visualNavIndex = 0;

          Widget gameContent = Scaffold(
            key: scaffoldKey,
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
              onMenuPressed: () {
                scaffoldKey.currentState?.openDrawer();
              },
              onVitalsTap: () => setState(() => tutState.tut1Vitals = true),
              onLevelUp: () => setState(() { levelHolding = false; widget.userData['level_holding'] = false; }),
            ),

            drawer: isDesktop ? null : MainHubDrawer(
              isMobile: true,
              username: username, dirtyCash: dirtyCash, cleanCash: cleanCash, goldBars: goldBars, creds: creds, influence: influence, unreadEventsCount: unreadEventsCount, hasBazaar: hasBazaar,
              anonExp: anonExp, activeBeacon: activeBeacon,
              onAssetTap: () { setState(() => tutState.tut1Assets = true); if (!isDesktop) Navigator.pop(context); },
              onNavigate: navigateTo, onLogout: logout,
            ),

            body: MainHubRouter.buildScreen(
              selectedIndex: selectedIndex,
              userData: widget.userData,
              onStateChange: customStateUpdate,
              onNavigate: navigateTo,
              activeCompanyId: activeCompanyId,
              infoBrokerTabIndex: infoBrokerTabIndex,
              setInfoBrokerTab: (val) => setState(() => infoBrokerTabIndex = val),
              setCompanyAndNavigate: (companyId, viewIndex) => setState(() { activeCompanyId = companyId; selectedIndex = viewIndex; }),
              activeBeacon: activeBeacon,
              isWaitingForMessage: isWaitingForMessage,
              tutState: tutState,
              onMissionRead: () {
                int currentAnonExp = getAnonExp();
                if (lastReadMissionExp < currentAnonExp) {
                  setState(() => lastReadMissionExp = currentAnonExp);
                }
              },
            ),

            bottomNavigationBar: isDesktop ? null : Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF39FF14), width: 0.5))),
              child: BottomNavigationBar(
                backgroundColor: Colors.black, type: BottomNavigationBarType.fixed, selectedItemColor: const Color(0xFF39FF14), unselectedItemColor: Colors.grey[700], selectedFontSize: 10, unselectedFontSize: 10, iconSize: 22,
                currentIndex: visualNavIndex,
                onTap: (index) => navigateTo(activeRoutes[index]),
                items: navItems,
              ),
            ),

            floatingActionButton: (selectedIndex == 0 && anonExp < 50)
                ? TutorialBeacon(
              id: 'fab_phone',
              activeId: activeBeacon,
              borderRadius: 16,
              child: FloatingActionButton(
                onPressed: () => navigateTo(29),
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
                        username: username, dirtyCash: dirtyCash, cleanCash: cleanCash, goldBars: goldBars, creds: creds, influence: influence, unreadEventsCount: unreadEventsCount, hasBazaar: hasBazaar,
                        anonExp: anonExp, activeBeacon: activeBeacon,
                        onAssetTap: () => setState(() => tutState.tut1Assets = true),
                        onNavigate: navigateTo, onLogout: logout,
                      ),
                    ),
                    Expanded(child: gameContent),
                  ],
                )
              else
                gameContent,

              if (showIntroStory) TutorialIntroOverlay(onContinue: () {
                setState(() {
                  showIntroStory = false;
                  MainHubLogic.hasPlayedIntro = true;
                });
              }),

              LevelUpOverlay(userData: widget.userData, onStateChange: customStateUpdate),
            ],
          );
        }
    );
  }
}