import 'package:flutter/material.dart';
import 'dashboard_view.dart';
import 'streets_view.dart';
import 'market_view.dart';
import 'syndicate_view.dart';

class MainHub extends StatefulWidget {
  const MainHub({super.key});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  int _currentIndex = 2; // Defaulting to Market

  final List<Widget> _pages = [
    const DashboardView(),
    const StreetsView(),
    const MarketView(),
    const SyndicateView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTacticalHUD(context),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _pages,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF1E1E1E),
        shape: CircleBorder(
          side: BorderSide(color: const Color(0xFF39FF14).withOpacity(0.5), width: 1),
        ),
        child: const Icon(Icons.phone_android, color: Color(0xFF39FF14)),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF39FF14), width: 0.5)),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF121212),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF39FF14),
          unselectedItemColor: Colors.white30,
          selectedFontSize: 10,
          unselectedFontSize: 9,
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.terminal), label: "HUB"),
            BottomNavigationBarItem(icon: Icon(Icons.directions_run), label: "STREETS"),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: "MARKET"),
            BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: "SYNDICATE"),
          ],
        ),
      ),
    );
  }

  Widget _buildTacticalHUD(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(bottom: BorderSide(color: Color(0xFF39FF14), width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('CS', style: TextStyle(color: Color(0xFF39FF14), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1)),
              const SizedBox(width: 8),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('SIXSON', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('\$4,250', style: TextStyle(color: Color(0xFF39FF14), fontSize: 16, fontWeight: FontWeight.w900)),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: screenWidth * 0.40,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildHudBar('E', 1.0, const Color(0xFF39FF14)),
                    const SizedBox(height: 4),
                    _buildHudBar('N', 0.2, Colors.orange),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusIcon(Icons.circle, const Color(0xFF39FF14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHudBar(String label, double fillLevel, Color color) {
    return Row(
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(width: 5),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: fillLevel,
              backgroundColor: const Color(0xFF333333),
              color: color,
              minHeight: 5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(IconData icon, Color color) {
    return Padding(padding: const EdgeInsets.only(right: 8.0), child: Icon(icon, color: color, size: 12));
  }
}