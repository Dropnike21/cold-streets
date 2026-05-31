import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import '../api_config.dart';

class LevelUpOverlay extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const LevelUpOverlay({super.key, required this.userData, required this.onStateChange});

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay> {
  bool _isProcessing = false;

  int _getRequiredExp(int level) {
    return (25 * math.pow(level, 1.7)).floor();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("SYSTEM ERROR: $message", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _processLevelAction(String action) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/character/level-up'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.userData['user_id'],
          "action": action
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        // This instantly updates main_hub.dart.
        // If holding == true OR exp is now < requiredExp, this overlay vanishes!
        widget.onStateChange(result['user']);

      } else {
        // 🚨 IF THE SERVER FAILS (e.g. 404 Route Not Found, 400 Not Enough EXP)
        try {
          final errorData = jsonDecode(response.body);
          _showError(errorData['error'] ?? "Server rejected the request.");
        } catch (_) {
          _showError("Failed to connect to the character engine (Status: ${response.statusCode}).");
        }
      }
    } catch (e) {
      _showError("Network timeout. Check your connection.");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    int currentLevel = widget.userData['level'] ?? 1;
    int currentExp = widget.userData['exp'] ?? 0;
    bool isHolding = widget.userData['level_holding'] == true;
    int requiredExp = _getRequiredExp(currentLevel);

    // THE GATEKEEPER: If they don't have enough EXP, or they are holding, stay invisible!
    if (currentExp < requiredExp || isHolding) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: const Color(0xFF161616),
                border: Border.all(color: const Color(0xFF39FF14), width: 2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF39FF14).withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
                ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.keyboard_double_arrow_up, color: Color(0xFF39FF14), size: 50),
                const SizedBox(height: 12),
                const Text("LEVEL UP AVAILABLE", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Text("You have reached Level ${currentLevel + 1}.", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 16),

                // Reward Details
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                  child: const Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite, color: Colors.redAccent, size: 14),
                          SizedBox(width: 8),
                          Text("MAX HP INCREASED BY 50", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.health_and_safety, color: Colors.greenAccent, size: 14),
                          SizedBox(width: 8),
                          Text("HEALTH FULLY RESTORED", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                if (_isProcessing)
                  const CircularProgressIndicator(color: Color(0xFF39FF14))
                else
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF39FF14),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => _processLevelAction('UPGRADE'),
                          child: const Text("UPGRADE NOW", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => _processLevelAction('HOLD'),
                          child: const Text("HOLD LEVEL", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }
}