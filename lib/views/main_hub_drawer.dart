import 'package:flutter/material.dart';

class MainHubDrawer extends StatelessWidget {
  final String username;
  final List<Map<String, dynamic>> activeCooldowns;
  final int unreadEventsCount;
  final String? hospitalExpiry;
  final String? jailExpiry;
  final double heat;
  final bool hasBazaar;
  final Function(int) onNavigate;
  final VoidCallback onLogout;

  const MainHubDrawer({
    super.key,
    required this.username,
    required this.activeCooldowns,
    required this.unreadEventsCount,
    this.hospitalExpiry,
    this.jailExpiry,
    required this.heat,
    required this.hasBazaar,
    required this.onNavigate,
    required this.onLogout,
  });

  String _formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    if (h > 0) {
      return "$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  void _handleNavigation(BuildContext context, int index) {
    Navigator.pop(context); // Close the drawer
    onNavigate(index);      // Trigger the navigation in MainHub
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
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
                if (activeCooldowns.any((cd) => cd['seconds_left'] > 0))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: activeCooldowns.where((cd) => cd['seconds_left'] > 0).map((cd) {
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
                                onTap: () => _handleNavigation(context, 10),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Icon(Icons.notifications, color: Colors.white54, size: 24),
                                    if (unreadEventsCount > 0)
                                      Positioned(
                                        right: -2, top: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                          child: Text(
                                            unreadEventsCount > 9 ? '9+' : '$unreadEventsCount',
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
                          Row(
                            children: [
                              if (hospitalExpiry != null && DateTime.parse(hospitalExpiry!).toLocal().isAfter(DateTime.now()))
                                Tooltip(
                                  message: "HOSPITALIZED\nYou are in a coma. Access to the city is restricted.",
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)),
                                    child: const Icon(Icons.medical_services, color: Colors.redAccent, size: 16),
                                  ),
                                )
                              else if (jailExpiry != null && DateTime.parse(jailExpiry!).toLocal().isAfter(DateTime.now()))
                                Tooltip(
                                  message: "INCARCERATED\nYou are locked in state prison. Access to the city is restricted.",
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.2), border: Border.all(color: Colors.orangeAccent), borderRadius: BorderRadius.circular(4)),
                                    child: const Icon(Icons.gavel, color: Colors.orangeAccent, size: 16),
                                  ),
                                )
                              else if (heat > 0)
                                  Tooltip(
                                    message: "HEAT: ${heat.toStringAsFixed(1)}%\nWanted level. Hits 100% for automatic arrest.",
                                    decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: heat > 80 ? Colors.redAccent : Colors.deepOrangeAccent), borderRadius: BorderRadius.circular(4)),
                                    child: SizedBox(
                                      width: 24, height: 24,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CircularProgressIndicator(value: heat / 100.0, strokeWidth: 2.5, backgroundColor: Colors.grey[800], color: heat > 80 ? Colors.redAccent : Colors.deepOrangeAccent),
                                          Icon(Icons.local_fire_department, size: 14, color: heat > 80 ? Colors.redAccent : Colors.deepOrangeAccent),
                                        ],
                                      ),
                                    ),
                                  ),
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
                      icon: Icons.dashboard, color: const Color(0xFF39FF14), title: "Return to City Hub",
                      onTap: () => _handleNavigation(context, 0)),
                ),
                const Divider(color: Color(0xFF333333), height: 1),

                _buildDistrictAccordion(
                    context: context,
                    title: "LOCAL NEIGHBORHOOD",
                    initiallyExpanded: true,
                    children: [
                      _buildMenuTile(icon: Icons.fitness_center, color: Colors.orangeAccent, title: "The Gym", onTap: () => _handleNavigation(context, 5)),
                      _buildMenuTile(icon: Icons.local_hospital, color: Colors.redAccent, title: "The Clinic", onTap: () {}),
                      _buildMenuTile(icon: Icons.church, color: Colors.yellow, title: "Church", onTap: () {}),
                    ]
                ),

                _buildDistrictAccordion(
                    context: context,
                    title: "THE UNDERWORLD",
                    children: [
                      _buildMenuTile(icon: Icons.diamond, color: Colors.cyanAccent, title: "Credit Broker", onTap: () => _handleNavigation(context, 6)),
                      _buildMenuTile(icon: Icons.security, color: Colors.grey, title: "Underground Munitions", onTap: () {}),
                      _buildMenuTile(icon: Icons.casino, color: Colors.purpleAccent, title: "The Casino", onTap: ()  => _handleNavigation(context, 20)),
                    ]
                ),

                _buildDistrictAccordion(
                    context: context,
                    title: "FINANCIAL DISTRICT",
                    children: [
                      _buildMenuTile(icon: Icons.account_balance, color: Colors.blueAccent, title: "The Bank", onTap: () => _handleNavigation(context, 17)),
                      _buildMenuTile(icon: Icons.show_chart, color: Colors.greenAccent, title: "Stock Market", onTap: () {}),
                      _buildMenuTile(icon: Icons.domain, color: Colors.tealAccent, title: "Real Estate", onTap: () => _handleNavigation(context, 18)),
                      _buildMenuTile(icon: Icons.shopping_bag, color: Colors.amber, title: "Trade Network", onTap: () {}),
                      _buildMenuTile(icon: Icons.gavel, color: Colors.orange, title: "Auction House", onTap: () {}),
                    ]
                ),

                _buildDistrictAccordion(
                    context: context,
                    title: "CIVIC CENTER",
                    children: [
                      _buildMenuTile(icon: Icons.newspaper, color: Colors.white, title: "Info Broker", onTap: () => _handleNavigation(context, 13)),
                      _buildMenuTile(icon: Icons.school, color: Colors.lightBlueAccent, title: "University", onTap: () => _handleNavigation(context, 16)),
                      _buildMenuTile(icon: Icons.local_hospital, color: Colors.redAccent, title: "City Hospital", onTap: () => _handleNavigation(context, 15)),
                      _buildMenuTile(icon: Icons.gavel, color: Colors.grey, title: "State Jail", onTap: () => _handleNavigation(context, 14)),
                      _buildMenuTile(icon: Icons.location_city, color: Colors.deepPurpleAccent, title: "City Hall", onTap: () => _handleNavigation(context, 8)),
                    ]
                ),

                _buildDistrictAccordion(
                    context: context,
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
                  _buildMenuTile(icon: Icons.backpack, color: Colors.white, title: "Inventory", onTap: () => _handleNavigation(context, 4)),
                  _buildMenuTile(icon: Icons.military_tech, color: const Color(0xFF39FF14), title: "Achievements", onTap: () => _handleNavigation(context, 9)),
                  _buildMenuTile(icon: Icons.house, color: Colors.brown.shade300, title: "My Properties", onTap: () => _handleNavigation(context, 19)),
                  if (hasBazaar) _buildMenuTile(icon: Icons.storefront, color: Colors.amber, title: "My Bazaar", onTap: () {}),
                  _buildMenuTile(icon: Icons.assignment, color: Colors.amberAccent, title: "Mission Board", onTap: () {}),
                  _buildMenuTile(icon: Icons.settings, color: Colors.grey, title: "Settings", onTap: () {}),
                  _buildMenuTile(icon: Icons.exit_to_app, color: Colors.redAccent, title: "Log Out", onTap: onLogout, textColor: Colors.redAccent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistrictAccordion({required BuildContext context, required String title, required List<Widget> children, bool initiallyExpanded = false}) {
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