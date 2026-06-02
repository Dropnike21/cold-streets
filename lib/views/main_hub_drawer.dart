import 'package:flutter/material.dart';
import 'tutorial_beacon.dart';

class MainHubDrawer extends StatelessWidget {
  final bool isMobile;
  final String username;
  final int dirtyCash;
  final int cleanCash;
  final int goldBars;
  final int creds;
  final int influence;
  final int unreadEventsCount;
  final bool hasBazaar;
  final int anonExp;
  final String? activeBeacon;
  final VoidCallback onAssetTap;
  final Function(int) onNavigate;
  final VoidCallback onLogout;

  const MainHubDrawer({
    super.key,
    required this.isMobile,
    required this.username,
    required this.dirtyCash,
    required this.cleanCash,
    required this.goldBars,
    required this.creds,
    required this.influence,
    required this.unreadEventsCount,
    required this.hasBazaar,
    required this.anonExp,
    this.activeBeacon,
    required this.onAssetTap,
    required this.onNavigate,
    required this.onLogout,
  });

  String _formatCash(int amount) {
    if (amount >= 1000000000) return '\$${(amount / 1000000000).toStringAsFixed(2)}b';
    if (amount >= 1000000) return '\$${(amount / 1000000).toStringAsFixed(2)}m';
    return '\$${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  void _handleNavigation(BuildContext context, int index) {
    if (isMobile) Navigator.pop(context);
    onNavigate(index);
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 DISTRICT UNLOCK LOGIC
    bool showFinancial = anonExp >= 5;
    bool showUnderworld = anonExp >= 6;
    bool showMapAndSyndicate = anonExp >= 7;

    return Drawer(
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Column(
        children: [
          // 🚨 HEADER: PLAYER PROFILE & CURRENCY
          TutorialBeacon(
            id: 'drawer_assets',
            activeId: activeBeacon,
            child: GestureDetector(
              onTap: onAssetTap,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.only(top: isMobile ? MediaQuery.of(context).padding.top + 16 : 24, left: 16, right: 16, bottom: 16),
                decoration: const BoxDecoration(
                    color: Color(0xFF0A0F14),
                    border: Border(bottom: BorderSide(color: Color(0xFF39FF14), width: 1.5))
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(color: const Color(0xFF252525), border: Border.all(color: const Color(0xFF39FF14), width: 1.5), borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.person, color: Colors.grey, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(username, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text("MY ASSETS", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildCurrencyRow(Icons.attach_money, "DIRTY CASH", _formatCash(dirtyCash), const Color(0xFF39FF14)),
                    const SizedBox(height: 8),
                    _buildCurrencyRow(Icons.account_balance_wallet, "CLEAN CASH", _formatCash(cleanCash), Colors.white),
                    const SizedBox(height: 8),
                    _buildCurrencyRow(Icons.view_agenda, "GOLD BARS", "$goldBars", Colors.amber),
                  ],
                ),
              ),
            ),
          ),

          // 🚨 BODY: SCROLLABLE NAVIGATION MENUS
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 16),

                // --- 1. COMPACT DESKTOP QUICK NAV (Horizontal Icon Bar) ---
                if (!isMobile) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        border: Border.all(color: const Color(0xFF333333)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.dashboard, color: Colors.white70, size: 22),
                            tooltip: "Dashboard Hub",
                            onPressed: () => onNavigate(0),
                          ),

                          TutorialBeacon(
                            id: 'drawer_streets',
                            activeId: activeBeacon,
                            child: IconButton(
                              icon: const Icon(Icons.local_fire_department, color: Colors.deepOrangeAccent, size: 22),
                              tooltip: "The Streets",
                              onPressed: () => onNavigate(1),
                            ),
                          ),

                          if (anonExp >= 4)
                            TutorialBeacon(
                              id: 'drawer_gym',
                              activeId: activeBeacon,
                              child: IconButton(
                                icon: const Icon(Icons.fitness_center, color: Colors.white70, size: 22),
                                tooltip: "Training Gym",
                                onPressed: () => onNavigate(5),
                              ),
                            ),

                          if (showMapAndSyndicate) ...[
                            IconButton(
                              icon: const Icon(Icons.map, color: Colors.white70, size: 22),
                              tooltip: "City Map",
                              onPressed: () => onNavigate(24),
                            ),
                            IconButton(
                              icon: const Icon(Icons.group, color: Colors.white70, size: 22),
                              tooltip: "Syndicate",
                              onPressed: () => onNavigate(3),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // --- 2. MOBILE-ONLY QUICK LINKS ---
                if (isMobile) ...[
                  Container(
                    color: const Color(0xFF121212),
                    child: _buildMenuTile(icon: Icons.dashboard, color: const Color(0xFF39FF14), title: "Return to City Hub", onTap: () => _handleNavigation(context, 0)),
                  ),
                  const Divider(color: Color(0xFF333333), height: 1),
                ],

                // --- 3. CIVIC CENTER (Always Visible) ---
                _buildDistrictAccordion(
                    context: context,
                    title: "CIVIC CENTER",
                    initiallyExpanded: anonExp < 5,
                    children: [
                      _buildMenuTile(icon: Icons.newspaper, color: Colors.white, title: "Info Broker", onTap: () => _handleNavigation(context, 13)),
                      _buildMenuTile(icon: Icons.school, color: Colors.lightBlueAccent, title: "University", onTap: () => _handleNavigation(context, 16)),
                      _buildMenuTile(icon: Icons.local_hospital, color: Colors.redAccent, title: "City Hospital", onTap: () => _handleNavigation(context, 15)),
                      _buildMenuTile(icon: Icons.gavel, color: Colors.orange, title: "State Prison", onTap: () => _handleNavigation(context, 14)),
                      _buildMenuTile(icon: Icons.location_city, color: Colors.deepPurpleAccent, title: "City Hall", onTap: () => _handleNavigation(context, 8)),
                    ]
                ),

                // --- 4. FINANCIAL DISTRICT (Unlocks at Task 5) ---
                if (showFinancial) ...[
                  _buildDistrictAccordion(
                      context: context,
                      title: "FINANCIAL DISTRICT",
                      initiallyExpanded: anonExp == 5,
                      children: [
                        _buildMenuTile(icon: Icons.account_balance, color: Colors.blueAccent, title: "The Bank", onTap: () => _handleNavigation(context, 17)),
                        _buildMenuTile(icon: Icons.domain, color: Colors.tealAccent, title: "Real Estate", onTap: () => _handleNavigation(context, 18)),
                        _buildMenuTile(icon: Icons.shopping_bag, color: Colors.amber, title: "Trade Network (undeveloped)", onTap: () => _handleNavigation(context, 25)),
                        _buildMenuTile(icon: Icons.gavel, color: Colors.orange, title: "Auction House (undeveloped)", onTap: () {}),
                      ]
                  ),
                ],

                // --- 5. THE UNDERWORLD (Unlocks at Task 6) ---
                if (showUnderworld) ...[
                  _buildDistrictAccordion(
                      context: context,
                      title: "THE UNDERWORLD",
                      initiallyExpanded: anonExp == 6,
                      children: [
                        _buildMenuTile(icon: Icons.diamond, color: Colors.cyanAccent, title: "Credit Broker / Item Market", onTap: () => _handleNavigation(context, 6)),
                        _buildMenuTile(icon: Icons.security, color: Colors.grey, title: "Underground Munitions (undeveloped)", onTap: () {}),
                        _buildMenuTile(icon: Icons.casino, color: Colors.purpleAccent, title: "The Casino", onTap: ()  => _handleNavigation(context, 20)),
                      ]
                  ),

                  // Secondary areas shown with Underworld
                  _buildDistrictAccordion(
                      context: context,
                      title: "LOCAL NEIGHBORHOOD",
                      children: [
                        _buildMenuTile(icon: Icons.local_hospital, color: Colors.redAccent, title: "The Clinic (undeveloped)", onTap: () {}),
                        _buildMenuTile(icon: Icons.church, color: Colors.yellow, title: "Church (undeveloped)", onTap: () {}),
                      ]
                  ),
                  _buildDistrictAccordion(
                      context: context,
                      title: "TRANSIT & AUTO",
                      children: [
                        _buildMenuTile(icon: Icons.flight_takeoff, color: Colors.white70, title: "Airport (undeveloped)", onTap: () {}),
                        _buildMenuTile(icon: Icons.car_repair, color: Colors.grey, title: "The Chop Shop (undeveloped)", onTap: () {}),
                      ]
                  ),
                ],

                // --- 6. RESTRICTED NOTIFICATION ---
                if (!showFinancial && !showUnderworld) ...[
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                      child: Text(
                        "OTHER CITY SECTORS RESTRICTED.\nCOMPLETE MISSIONS TO UNLOCK.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
              ],
            ),
          ),

          // 🚨 FOOTER: PINNED PERSONAL ASSETS (Always stays at bottom)
          Container(
            decoration: BoxDecoration(color: const Color(0xFF121212), border: Border(top: BorderSide(color: Colors.grey.shade900, width: 1))),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TutorialBeacon(id: 'nav_inventory', activeId: activeBeacon, child: _buildMenuTile(icon: Icons.backpack, color: Colors.white, title: "Inventory", onTap: () => _handleNavigation(context, 4))),
                  _buildMenuTile(icon: Icons.track_changes, color: Colors.orangeAccent, title: "Missions", onTap: () => _handleNavigation(context, 29)),
                  TutorialBeacon(id: 'nav_properties', activeId: activeBeacon, child: _buildMenuTile(icon: Icons.house, color: Colors.brown.shade300, title: "My Properties", onTap: () => _handleNavigation(context, 19))),
                  TutorialBeacon(id: 'nav_achievements', activeId: activeBeacon, child: _buildMenuTile(icon: Icons.military_tech, color: const Color(0xFF39FF14), title: "Achievements", onTap: () => _handleNavigation(context, 9))),
                  _buildMenuTile(icon: Icons.exit_to_app, color: Colors.redAccent, title: "Log Out", onTap: onLogout, textColor: Colors.redAccent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyRow(IconData icon, String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [Icon(icon, color: color, size: 14), const SizedBox(width: 8), Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.bold))]),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      ],
    );
  }

  // 🚨 ACCORDION HELPER WIDGET
  Widget _buildDistrictAccordion({required BuildContext context, required String title, required List<Widget> children, bool initiallyExpanded = false}) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        iconColor: const Color(0xFF39FF14),
        collapsedIconColor: Colors.grey[600],
        tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
        title: Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        children: children,
      ),
    );
  }

  // 🚨 MENU TILE HELPER WIDGET
  Widget _buildMenuTile({required IconData icon, required Color color, required String title, required VoidCallback onTap, Color textColor = Colors.white}) {
    return ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        leading: Icon(icon, color: color, size: 16),
        title: Text(title, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
        onTap: onTap
    );
  }
}