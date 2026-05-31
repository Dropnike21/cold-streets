import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'tutorial_beacon.dart';

class MainHubAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isDesktop;
  final String? activeBeacon;
  final String username;
  final String userId;
  final int level;
  final int exp;
  final bool levelHolding;
  final int energy;
  final int nerve;
  final int hp;
  final double heat;
  final String? hospitalExpiry;
  final String? jailExpiry;
  final VoidCallback onMenuPressed;
  final VoidCallback onVitalsTap;
  final VoidCallback onLevelUp;

  const MainHubAppBar({
    super.key,
    required this.isDesktop,
    this.activeBeacon,
    required this.username,
    required this.userId,
    required this.level,
    required this.exp,
    required this.levelHolding,
    required this.energy,
    required this.nerve,
    required this.hp,
    required this.heat,
    this.hospitalExpiry,
    this.jailExpiry,
    required this.onMenuPressed,
    required this.onVitalsTap,
    required this.onLevelUp,
  });

  @override
  Size get preferredSize => const Size.fromHeight(55);

  int _getRequiredExp(int currentLevel) {
    return (25 * math.pow(currentLevel, 1.7)).floor();
  }

  Widget _buildLevelIndicator() {
    int requiredExp = _getRequiredExp(level);
    bool canLevelUp = exp >= requiredExp;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("LV.$level", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
        if (canLevelUp && levelHolding) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: onLevelUp,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFF39FF14).withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF39FF14), width: 1.5)),
              child: const Icon(Icons.arrow_upward, color: Color(0xFF39FF14), size: 10),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildVital(IconData icon, String val, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: color.withOpacity(0.5), width: 1), borderRadius: BorderRadius.circular(4)),
      child: Row(children: [Icon(icon, color: color, size: 14), const SizedBox(width: 4), Text(val, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))]),
    );
  }

  Widget _buildHeatAndStatus() {
    bool inHosp = hospitalExpiry != null && DateTime.parse(hospitalExpiry!).toLocal().isAfter(DateTime.now());
    bool inJail = jailExpiry != null && DateTime.parse(jailExpiry!).toLocal().isAfter(DateTime.now());
    return Row(
      children: [
        if (inHosp) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.medical_services, color: Colors.redAccent, size: 14)),
        if (inJail) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.2), border: Border.all(color: Colors.orangeAccent), borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.gavel, color: Colors.orangeAccent, size: 14)),
        if (heat > 0) Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: heat > 80 ? Colors.redAccent : Colors.deepOrangeAccent, width: 1), borderRadius: BorderRadius.circular(4)),
          child: Row(children: [Icon(Icons.local_fire_department, color: heat > 80 ? Colors.redAccent : Colors.deepOrangeAccent, size: 14), const SizedBox(width: 4), Text("${heat.toStringAsFixed(0)}%", style: TextStyle(color: heat > 80 ? Colors.redAccent : Colors.deepOrangeAccent, fontSize: 11, fontWeight: FontWeight.bold))]),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMenuTarget = activeBeacon == 'btn_menu';

    return AppBar(
      backgroundColor: Colors.black,
      elevation: 2,
      toolbarHeight: 55,
      shadowColor: const Color(0xFF39FF14).withValues(alpha: 0.5),
      automaticallyImplyLeading: false,
      leading: isDesktop ? null : Builder(
        builder: (context) => TutorialBeacon(
          id: 'btn_menu',
          activeId: isMenuTarget ? 'btn_menu' : null,
          child: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: onMenuPressed,
          ),
        ),
      ),
      title: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(
            children: [
              const Text("CS", style: TextStyle(color: Color(0xFF39FF14), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2, fontStyle: FontStyle.italic)),
              const SizedBox(width: 12),
              _buildLevelIndicator(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "$username [$userId]",
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              TutorialBeacon(
                id: 'hud_vitals',
                activeId: activeBeacon,
                child: GestureDetector(
                  onTap: onVitalsTap,
                  child: Container(
                    color: Colors.transparent,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildVital(Icons.bolt, "$energy", Colors.yellowAccent),
                        _buildVital(Icons.psychology, "$nerve", Colors.purpleAccent),
                        _buildVital(Icons.favorite, "$hp", Colors.redAccent),
                        _buildHeatAndStatus(),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}