import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import '../api_config.dart';

class CrimesPickpocketView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;
  final Function(Map<String, dynamic>) onStateChange;

  const CrimesPickpocketView({
    super.key,
    required this.userData,
    required this.onBack,
    required this.onStateChange,
  });

  @override
  State<CrimesPickpocketView> createState() => _CrimesPickpocketViewState();
}

class _CrimesPickpocketViewState extends State<CrimesPickpocketView> {
  Timer? _spawnerTimer;
  Map<String, dynamic>? _executingTarget; // Tracks who we are actively robbing
  bool _isExecuting = false;
  bool _isLoading = true;
  Map<String, dynamic>? _lastResult;

  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  List<dynamic> _targetTemplates = [];
  List<Map<String, dynamic>> _activeTargets = [];

  IconData _getIconData(String? iconName) {
    switch (iconName) {
      case 'smartphone': return Icons.smartphone;
      case 'headphones': return Icons.headphones;
      case 'visibility': return Icons.visibility;
      case 'warning_amber_rounded': return Icons.warning_amber_rounded;
      default: return Icons.directions_walk;
    }
  }

  // Dynamically colors the tags based on the database modifier!
  Color _getActivityColor(double mod) {
    if (mod >= 15.0) return const Color(0xFF39FF14); // High Success (Neon Green)
    if (mod > 0.0) return Colors.lightGreenAccent;   // Good Success
    if (mod == 0.0) return Colors.yellowAccent;      // Neutral
    if (mod > -20.0) return Colors.orangeAccent;     // Bad
    return Colors.redAccent;                         // High Alert!
  }

  @override
  void initState() {
    super.initState();
    _fetchPickpocketData();
  }

  Future<void> _fetchPickpocketData() async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/crimes/list?type=pickpocketing'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _targetTemplates = data['templates'];

            for(int i = 0; i < 4; i++) {
              _spawnTarget(animate: false);
            }

            _isLoading = false;
          });
          _startSpawner();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startSpawner() {
    _spawnerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      for (int i = _activeTargets.length - 1; i >= 0; i--) {
        _activeTargets[i]['time_left'] -= 1;
        if (_activeTargets[i]['time_left'] <= 0) {
          _removeTargetWithAnimation(i);
        }
      }

      if (_activeTargets.length < 12 && math.Random().nextDouble() < 0.40) {
        _spawnTarget(animate: true);
      }

      setState(() {});
    });
  }

  @override
  void dispose() {
    _spawnerTimer?.cancel();
    super.dispose();
  }

  void _spawnTarget({bool animate = true}) {
    if (_targetTemplates.isEmpty) return;

    final template = _targetTemplates[math.Random().nextInt(_targetTemplates.length)];
    final mechanics = template['mechanics_json'] ?? {};
    final activitiesList = mechanics['activities'] ?? [];

    if (activitiesList.isEmpty) return; // Failsafe

    final activity = activitiesList[math.Random().nextInt(activitiesList.length)];
    int lifespan = math.Random().nextInt(61) + 10;

    double nerveCost = (template['nerve_cost'] ?? 1).toDouble();
    double baseChance = 95.0 - (nerveCost * 0.8);
    baseChance = baseChance.clamp(5.0, 95.0);

    final newTarget = {
      'instance_id': math.Random().nextInt(999999).toString(),
      'id': template['id'],
      'title': template['title'],
      'nerve_cost': template['nerve_cost'],
      'base_success': baseChance,
      'activity': activity,
      'time_left': lifespan,
      'max_time': lifespan,
    };

    _activeTargets.add(newTarget);

    if (animate && _listKey.currentState != null) {
      _listKey.currentState!.insertItem(_activeTargets.length - 1, duration: const Duration(milliseconds: 300));
    }
  }

  void _removeTargetWithAnimation(int index) {
    if (!mounted || index < 0 || index >= _activeTargets.length) return;

    final removedTarget = _activeTargets.removeAt(index);

    _listKey.currentState?.removeItem(
        index,
            (context, animation) => _buildAnimatedItem(removedTarget, animation),
        duration: const Duration(milliseconds: 500)
    );
  }

  Future<void> _executeCrime(Map<String, dynamic> target) async {
    if (_isExecuting) return;

    setState(() {
      _executingTarget = target; // Lock onto them for the terminal UI
      _isExecuting = true;
      _lastResult = null;
    });

    if (widget.userData['nerve'] < target['nerve_cost']) {
      setState(() => _isExecuting = false);
      _lastResult = {'status': 'ERROR', 'color': Colors.purpleAccent, 'message': 'Insufficient Nerve.', 'data': 'Abort operation.'};
      return;
    }

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    int targetIndex = _activeTargets.indexWhere((t) => t['instance_id'] == target['instance_id']);

    if (targetIndex == -1) {
      setState(() {
        _isExecuting = false;
        _lastResult = {'status': 'MISSED', 'color': Colors.grey, 'message': 'Target blended into the crowd.', 'data': 'You were too slow.'};
      });
      return;
    }

    _removeTargetWithAnimation(targetIndex);

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/crimes/execute'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.userData['user_id'],
          "crime_id": target['id'],
          "activity_name": target['activity']['name']
        }),
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
              case "escaped": _lastResult = {'status': 'ESCAPED', 'color': Colors.yellowAccent, 'message': 'Target checked their pockets. You aborted.', 'data': result['message']}; break;
              case "hospitalized": _lastResult = {'status': 'HOSPITALIZED', 'color': Colors.orangeAccent, 'message': 'Target fought back violently.', 'data': result['message']}; break;
              case "jailed": _lastResult = {'status': 'BUSTED', 'color': Colors.redAccent, 'message': 'You were caught red-handed.', 'data': result['message']}; break;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1A1A1A),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF39FF14), size: 16), onPressed: widget.onBack),
              const Text("PICKPOCKETING", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            ],
          ),
        ),

        Container(
          height: 140,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF0A0F14),
            border: Border(bottom: BorderSide(color: Color(0xFF39FF14), width: 1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildTerminalContent(),
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)))
              : AnimatedList(
            key: _listKey,
            padding: const EdgeInsets.all(12),
            initialItemCount: _activeTargets.length,
            itemBuilder: (context, index, animation) {
              return _buildAnimatedItem(_activeTargets[index], animation);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalContent() {
    if (_isExecuting && _executingTarget != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text("APPROACHING: ${_executingTarget!['title'].toString().toUpperCase()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5))),
            ],
          ),
          const SizedBox(height: 8),
          const Text("> Closing distance in crowd...", style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace')),
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
              Text("RESULT: ${_lastResult!['status']}", style: TextStyle(color: _lastResult!['color'], fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text("> ${_lastResult!['message']}", style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text("> ${_lastResult!['data']}", style: TextStyle(color: _lastResult!['color'], fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      );
    }

    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.visibility, color: Colors.white24, size: 30),
        SizedBox(height: 8),
        Text("OBSERVING CROWD", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
        const SizedBox(height: 4),
        Text("Awaiting execution command...", style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildAnimatedItem(Map<String, dynamic> target, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: 0.0,
      child: FadeTransition(
        opacity: animation,
        child: _buildTargetCard(target),
      ),
    );
  }

  Widget _buildActionIndicator(Map<String, dynamic> activity, double timePct) {
    // Dynamic color based on the actual Modifier pulled from the Database
    double modValue = (activity['mod'] ?? 0).toDouble();
    Color baseColor = _getActivityColor(modValue);

    // Turns red when less than 20% time remains
    Color urgencyColor = timePct < 0.2 ? Colors.redAccent : baseColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
          color: urgencyColor.withOpacity(0.15),
          border: Border.all(color: urgencyColor.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(4)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
              value: timePct,
              valueColor: AlwaysStoppedAnimation<Color>(urgencyColor),
              strokeWidth: 2,
              backgroundColor: Colors.white10,
            ),
          ),
          const SizedBox(width: 6),
          Icon(_getIconData(activity['icon']), color: urgencyColor, size: 12),
          const SizedBox(width: 4),
          Text(activity['name'].toString().toUpperCase(), style: TextStyle(color: urgencyColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildTargetCard(Map<String, dynamic> target) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        gradient: const LinearGradient(
          colors: [Color(0xFF222222), Color(0xFF1A1A1A)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        // Completely static borders now! No focus logic.
        border: Border.all(color: const Color(0xFF333333), width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Align(
                alignment: Alignment.centerLeft,
                // Card text is no longer clickable
                child: Text(target['title'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
              ),
            ),
          ),

          Center(
            child: Row(
              children: [
                _buildActionIndicator(target['activity'], target['time_left'] / target['max_time']),
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
                  color: const Color(0xFF39FF14).withOpacity(0.1),
                  border: const Border(left: BorderSide(color: Color(0xFF333333))),
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(5), bottomRight: Radius.circular(5)),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("${target['nerve_cost']} ", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 15, fontWeight: FontWeight.w900)),
                    const Icon(Icons.pan_tool, color: Color(0xFF39FF14), size: 16),
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