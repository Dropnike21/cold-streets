import 'package:flutter/material.dart';

// 🚨 ALL SCREEN IMPORTS MOVED HERE
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
import 'trade_network_view.dart';
import 'crimes_search_view.dart';
import 'crimes_shoplifting_view.dart';
import 'crimes_pickpocket_view.dart';
import 'missions_view.dart';

import 'tutorial_state.dart';

class MainHubRouter {
  static Widget buildScreen({
    required int selectedIndex,
    required Map<String, dynamic> userData,
    required Function(Map<String, dynamic>) onStateChange,
    required Function(int) onNavigate,
    required int activeCompanyId,
    required int infoBrokerTabIndex,
    required Function(int) setInfoBrokerTab,
    required Function(int, int) setCompanyAndNavigate,
    String? activeBeacon,
    required bool isWaitingForMessage,
    required TutorialState tutState,
    required VoidCallback onMissionRead,
  }) {
    switch (selectedIndex) {
      case 0: return DashboardView(userData: userData, onNavigate: onNavigate);
      case 1: return StreetsView(userData: userData, onStateChange: onStateChange, onNavigate: onNavigate);
      case 2: return MarketView(userData: userData, onStateChange: onStateChange);
      case 3: return SyndicateView(userData: userData, onStateChange: onStateChange);
      case 4: return InventoryView(userData: userData, onStateChange: onStateChange);
      case 5: return GymView(userData: userData, onStateChange: onStateChange);
      case 6: return CreditBrokerView(userData: userData);
      case 7: return JobsView(userData: userData, onStateChange: onStateChange, onBack: () { setInfoBrokerTab(2); onNavigate(13); });
      case 8: return CityHallView(userData: userData, onStateChange: onStateChange, onViewCompany: (int companyId) { setCompanyAndNavigate(companyId, 11); });
      case 9: return AchievementsView(userData: userData);
      case 10: return EventsView(userData: userData);
      case 11: return CompanyDashboardView(userData: userData, companyId: activeCompanyId, onBack: () => onNavigate(8), onManage: () => onNavigate(12));
      case 12: return CompanyManagementView(userData: userData, companyId: activeCompanyId, onBack: () => onNavigate(11), onSell: () => onNavigate(8));
      case 13: return InfoBrokerView(key: ValueKey(infoBrokerTabIndex), userData: userData, onStateChange: onStateChange, initialTabIndex: infoBrokerTabIndex, onNavigate: (index) { setInfoBrokerTab(0); onNavigate(index); });
      case 14: return JailView(userData: userData, onStateChange: onStateChange);
      case 15: return HospitalView(userData: userData);
      case 16: return UniversityView(userData: userData, onStateChange: onStateChange);
      case 17: return BankView(userData: userData, onStateChange: onStateChange);
      case 18: return RealEstateView(userData: userData, onStateChange: onStateChange);
      case 19: return ManagePropertiesView(userData: userData, onStateChange: onStateChange);
      case 20: return CasinoHubView(userData: userData, onStateChange: onStateChange, onNavigate: onNavigate);
      case 21: return CasPeryaView(userData: userData, onStateChange: onStateChange, onBack: () => onNavigate(20));
      case 22: return CasSlotsView(userData: userData, onStateChange: onStateChange, onBack: () => onNavigate(20));
      case 23: return CasHighLowView(userData: userData, onStateChange: onStateChange, onBack: () => onNavigate(20));
      case 24: return CityMapView(userData: userData, onBack: () => onNavigate(0), onNavigate: onNavigate);
      case 25: return TradeNetworkView(userData: userData, onStateChange: onStateChange, onBack: () => onNavigate(0));
      case 26: return CrimesSearchView(userData: userData, onStateChange: onStateChange, onBack: () => onNavigate(1));
      case 27: return CrimesShopliftingView(userData: userData, onStateChange: onStateChange, onBack: () => onNavigate(1));
      case 28: return CrimesPickpocketView(userData: userData, onStateChange: onStateChange, onBack: () => onNavigate(1));

      case 29: return MissionsView(
        userData: userData,
        onStateChange: onStateChange,
        onBack: () => onNavigate(0),
        activeBeacon: activeBeacon,
        isWaitingForMessage: isWaitingForMessage,
        tut1Vitals: tutState.tut1Vitals,
        tut1Assets: tutState.tut1Assets,
        tut2Inv: tutState.tut2Inv,
        tut2Prop: tutState.tut2Prop,
        tut2Ach: tutState.tut2Ach,
        tut3Search: tutState.tut3Search,
        tut3Shop: tutState.tut3Shop,
        tut3Pick: tutState.tut3Pick,
        tut3CrimesDoneCount: tutState.tut3CrimesDoneCount,
        onMissionRead: onMissionRead,
      );

      default: return DashboardView(userData: userData, onNavigate: onNavigate);
    }
  }
}