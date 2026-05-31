import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../api_config.dart';

class CrimesShopliftingView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;
  final Function(Map<String, dynamic>) onStateChange;

  const CrimesShopliftingView({
    super.key,
    required this.userData,
    required this.onBack,
    required this.onStateChange,
  });

  @override
  State<CrimesShopliftingView> createState() => _CrimesShopliftingViewState();
}

class _CrimesShopliftingViewState extends State<CrimesShopliftingView> {
  bool _isLoading = true;
  List<dynamic> _crimes = [];
  Map<String, dynamic>? _focusedTarget;
  Timer? _clockTimer;

  bool _isExecuting = false;
  Map<String, dynamic>? _lastResult;

  double _timeOfDayProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchShopliftingCrimes();

    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) _updateClock();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  // --- LIVE MATH LOGIC ---
  void _updateClock() {
    DateTime now = DateTime.now().toUtc();
    int secondsInDay = (now.hour * 3600) + (now.minute * 60) + now.second;
    setState(() {
      _timeOfDayProgress = secondsInDay / 86400.0;
    });
  }

  bool _isInsideWindow(double progress, List<dynamic>? window) {
    if (window == null || window.length != 2) return false;
    double start = window[0].toDouble();
    double end = window[1].toDouble();

    if (start > end) {
      return progress >= start || progress <= end;
    } else {
      return progress >= start && progress <= end;
    }
  }

  double _calculateSuccess(Map<String, dynamic> crime) {
    final mechanics = crime['mechanics_json'] ?? {};
    double cctvScore = 99.0;
    double guardScore = 99.0;

    if (mechanics['has_cctv'] == true) {
      if (_isInsideWindow(_timeOfDayProgress, mechanics['cctv_reboot'])) {
        cctvScore = 99.0;
      } else {
        cctvScore = 15.0;
      }
    }

    if (mechanics['has_guards'] == true) {
      if (_isInsideWindow(_timeOfDayProgress, mechanics['guard_break'])) {
        guardScore = 99.0;
      } else if (_isInsideWindow(_timeOfDayProgress, mechanics['guard_swap'])) {
        guardScore = 60.0;
      } else {
        guardScore = 10.0;
      }
    }
    return (cctvScore + guardScore) / 2.0;
  }

  Color _getDynamicColor(double rate) {
    if (rate <= 40.0) return Colors.redAccent;
    if (rate <= 80.0) return Colors.orangeAccent;
    return const Color(0xFF39FF14);
  }

  Map<String, dynamic> _getCctvStatus(Map<String, dynamic> mechanics) {
    if (mechanics['has_cctv'] != true) return {'color': Colors.white24, 'label': 'NO CCTV DETECTED'};

    if (_isInsideWindow(_timeOfDayProgress, mechanics['cctv_reboot'])) {
      return {'color': const Color(0xFF39FF14), 'label': 'CCTV: REBOOTING'};
    }
    return {'color': Colors.redAccent, 'label': 'CCTV: ONLINE'};
  }

  Map<String, dynamic> _getGuardStatus(Map<String, dynamic> mechanics) {
    if (mechanics['has_guards'] != true) return {'color': Colors.white24, 'label': 'NO GUARDS DETECTED'};

    if (_isInsideWindow(_timeOfDayProgress, mechanics['guard_break'])) {
      return {'color': const Color(0xFF39FF14), 'label': 'GUARDS: ON BREAK'};
    } else if (_isInsideWindow(_timeOfDayProgress, mechanics['guard_swap'])) {
      return {'color': Colors.orangeAccent, 'label': 'GUARDS: SHIFT SWAP'};
    }
    return {'color': Colors.redAccent, 'label': 'GUARDS: ON DUTY'};
  }

  // --- API CALLS ---
  Future<void> _fetchShopliftingCrimes() async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/crimes/list'));
      if (response.statusCode == 200) {
        final List<dynamic> allCrimes = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _crimes = allCrimes.where((c) => c['sub_category'] == 'Shoplifting').toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executeCrime(Map<String, dynamic> target) async {
    setState(() {
      _focusedTarget = target;
      _isExecuting = true;
      _lastResult = null;
    });

    if (widget.userData['nerve'] < target['nerve_cost']) {
      setState(() => _isExecuting = false);
      _showResultSnackbar("NO NERVE", "You don't have enough Nerve.", Colors.purpleAccent);
      return;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 1000)); // Suspense delay

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/crimes/execute'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userData['user_id'], "crime_id": target['id']}),
      );

      if (!mounted) return;
      final result = jsonDecode(response.body);

      if (result['user'] != null) widget.onStateChange(result['user']);

      setState(() {
        _isExecuting = false;
        if (response.statusCode == 200) {
          if (result['arrested'] == true) {
            _lastResult = {'status': 'BUSTED', 'color': Colors.redAccent, 'message': '100% HEAT REACHED.', 'data': result['message']};
          } else {
            switch (result['status']) {
              case "success": _lastResult = {'status': 'SUCCESS', 'color': const Color(0xFF39FF14), 'message': result['message'], 'data': '+\$${result['gained_cash'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} DIRTY CASH'}; break;
              case "escaped": _lastResult = {'status': 'ESCAPED', 'color': Colors.yellowAccent, 'message': 'Spooked the guards. Aborted the run.', 'data': result['message']}; break;
              case "hospitalized": _lastResult = {'status': 'HOSPITALIZED', 'color': Colors.orangeAccent, 'message': 'Beat down by security.', 'data': result['message']}; break;
              case "jailed": _lastResult = {'status': 'BUSTED', 'color': Colors.redAccent, 'message': 'Cameras flagged your face. Cops dispatched.', 'data': result['message']}; break;
            }
          }
        } else {
          _lastResult = {'status': 'ERROR', 'color': Colors.redAccent, 'message': 'System failure.', 'data': result['error'] ?? "Unknown error."};
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _lastResult = {'status': 'CONNECTION LOST', 'color': Colors.redAccent, 'message': 'Server timeout.', 'data': 'Check your connection.'};
      });
    }
  }

  void _showResultSnackbar(String title, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(side: BorderSide(color: color, width: 2), borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1A1A1A),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF39FF14), size: 16), onPressed: widget.onBack),
              const Text("SHOPLIFTING OPERATIONS", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            ],
          ),
        ),

        // --- THE OUTCOME TERMINAL ---
        Container(
          height: 140,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF0A0F14),
            border: Border(bottom: BorderSide(color: Color(0xFF39FF14), width: 1)),
          ),
          child: Stack(
            children: [
              const Positioned(right: -20, bottom: -20, child: Icon(Icons.terminal, size: 150, color: Colors.white10)),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withOpacity(0.95), isMobile ? Colors.black.withOpacity(0.85) : Colors.transparent],
                    begin: Alignment.centerLeft, end: Alignment.centerRight, stops: const [0.2, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 0, top: 0, bottom: 0,
                width: isMobile ? MediaQuery.of(context).size.width : MediaQuery.of(context).size.width * 0.60,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildTerminalContent(),
                ),
              ),
            ],
          ),
        ),

        // --- CRIME LIST ---
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)))
              : _crimes.isEmpty
              ? const Center(child: Text("No targets available.", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _crimes.length,
            itemBuilder: (context, index) {
              return _buildCrimeCard(_crimes[index]);
            },
          ),
        ),
      ],
    );
  }

  // --- TERMINAL RENDERER LOGIC ---
  Widget _buildTerminalContent() {
    if (_isExecuting) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              ),
              const SizedBox(width: 12),
              Expanded(child: Text("BREACHING: ${_focusedTarget!['title'].toString().toUpperCase()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5))),
            ],
          ),
          const SizedBox(height: 8),
          const Text("> Spoofing local camera nodes...", style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace')),
          const Text("> Bypassing guard patrols...", style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace')),
        ],
      );
    }

    if (_lastResult != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: _lastResult!['color']),
              const SizedBox(width: 8),
              Text("OPERATION: ${_lastResult!['status']}", style: TextStyle(color: _lastResult!['color'], fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text("> ${_lastResult!['message']}", style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text("> ${_lastResult!['data']}", style: TextStyle(color: _lastResult!['color'], fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      );
    }

    if (_focusedTarget != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: Colors.white),
              const SizedBox(width: 8),
              Text("TARGET LOCKED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text("> Location: ${_focusedTarget!['title'].toString().toUpperCase()}", style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
          const Text("> Awaiting EXECUTE command...", style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
        ],
      );
    }

    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.terminal, color: Colors.white24, size: 30),
        SizedBox(height: 8),
        Text("SYSTEM STANDBY", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
        SizedBox(height: 4),
        Text("Select a location to acquire target lock.", style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
      ],
    );
  }

  // --- LIVE CRIME CARD WITH INDICATORS ---
  Widget _buildLiveIndicator(IconData icon, Map<String, dynamic> status) {
    return Tooltip(
      message: status['label'],
      preferBelow: false,
      textStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(4), border: Border.all(color: status['color'])),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: status['color'].withOpacity(0.15),
            border: Border.all(color: status['color'].withOpacity(0.5)),
            borderRadius: BorderRadius.circular(4)
        ),
        child: Icon(icon, color: status['color'], size: 14),
      ),
    );
  }

  Widget _buildCrimeCard(Map<String, dynamic> target) {
    final mechanics = target['mechanics_json'] ?? {};
    double averageSuccessRate = _calculateSuccess(target);
    Color dynamicColor = _getDynamicColor(averageSuccessRate);
    bool isFocused = _focusedTarget != null && _focusedTarget!['id'] == target['id'];

    Map<String, dynamic> cctvStatus = _getCctvStatus(mechanics);
    Map<String, dynamic> guardStatus = _getGuardStatus(mechanics);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        gradient: LinearGradient(
          colors: [dynamicColor.withOpacity(0.15), const Color(0xFF1A1A1A)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        border: Border.all(color: isFocused ? Colors.white : dynamicColor.withOpacity(0.6), width: isFocused ? 2.0 : 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (_focusedTarget != null && _focusedTarget!['id'] == target['id']) {
                      _focusedTarget = null; // Toggle off if tapped again
                      _lastResult = null; // Clear terminal on deselect
                    } else {
                      _focusedTarget = target;
                      _lastResult = null;
                    }
                  });
                },
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(5), bottomLeft: Radius.circular(5)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      target['title'].toString().toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Center(
            child: Row(
              children: [
                _buildLiveIndicator(Icons.videocam, cctvStatus),
                const SizedBox(width: 6),
                _buildLiveIndicator(Icons.security, guardStatus),
                const SizedBox(width: 12),
              ],
            ),
          ),

          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _executeCrime(target),
              borderRadius: const BorderRadius.only(topRight: Radius.circular(5), bottomRight: Radius.circular(5)),
              child: Container(
                width: 70,
                decoration: BoxDecoration(
                  color: dynamicColor.withOpacity(0.1),
                  border: const Border(left: BorderSide(color: Color(0xFF333333))),
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(5), bottomRight: Radius.circular(5)),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("${target['nerve_cost']} ", style: TextStyle(color: dynamicColor, fontSize: 15, fontWeight: FontWeight.w900)),
                    Icon(Icons.shopping_bag, color: dynamicColor, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}