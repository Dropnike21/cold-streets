import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math; // Required for the harsh penalty math!
import '../api_config.dart';

class CrimesSearchView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onBack;
  final Function(Map<String, dynamic>) onStateChange;

  const CrimesSearchView({
    super.key,
    required this.userData,
    required this.onBack,
    required this.onStateChange,
  });

  @override
  State<CrimesSearchView> createState() => _SearchingCrimesViewState();
}

class _SearchingCrimesViewState extends State<CrimesSearchView> {
  bool _isLoading = true;
  List<dynamic> _crimes = [];
  Map<String, dynamic>? _focusedCrime;
  Timer? _clockTimer;

  Map<String, double> _meters = {
    'time_of_day': 0.0,
    'police_patrol': 0.0,
    'municipal_services': 0.0,
    'crowd_density': 0.0,
    'weather_condition': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _fetchSearchingCrimes();
    _updateAutonomousMeters();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) _updateAutonomousMeters();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  // --- MATH ENGINE: CROWDS & WEATHER ---
  double _getCrowdDensity(DateTime now) {
    int day = now.weekday;
    int hour = now.hour;
    double progress = now.minute / 60.0;

    List<double> curve;
    if (day >= 1 && day <= 5) {
      curve = [0.1, 0.1, 0.1, 0.1, 0.1, 0.2, 0.5, 0.8, 0.9, 0.7, 0.5, 0.6, 0.6, 0.5, 0.5, 0.7, 0.9, 0.95, 0.8, 0.5, 0.3, 0.2, 0.1, 0.1];
    } else if (day == 6) {
      curve = [0.1, 0.1, 0.1, 0.1, 0.1, 0.2, 0.3, 0.5, 0.7, 0.8, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.8, 0.7, 0.8, 0.9, 0.7, 0.5, 0.3, 0.2];
    } else {
      curve = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.2, 0.4, 0.7, 0.9, 1.0, 0.9, 0.7, 0.6, 0.5, 0.5, 0.4, 0.4, 0.3, 0.2, 0.2, 0.1, 0.1, 0.1];
    }

    double currentHourDensity = curve[hour];
    double nextHourDensity = curve[(hour + 1) % 24];
    return currentHourDensity + ((nextHourDensity - currentHourDensity) * progress);
  }

  double _getDeterministicWeather(int secondsSinceEpoch) {
    const int chunkSize = 14400;
    const int transitionTime = 2400;

    int currentChunk = secondsSinceEpoch ~/ chunkSize;
    int timeInChunk = secondsSinceEpoch % chunkSize;

    double getSeededRandom(int seed) {
      return ((seed * 9301) + 49297) % 233280 / 233280.0;
    }

    double prevWeather = getSeededRandom(currentChunk - 1);
    double targetWeather = getSeededRandom(currentChunk);

    if (timeInChunk < transitionTime) {
      double progress = timeInChunk / transitionTime;
      return prevWeather + ((targetWeather - prevWeather) * progress);
    } else {
      return targetWeather;
    }
  }

  void _updateAutonomousMeters() {
    DateTime now = DateTime.now().toUtc();
    int dayOfWeek = now.weekday - 1;
    int secondsSinceEpoch = now.millisecondsSinceEpoch ~/ 1000;
    int secondsInDay = (now.hour * 3600) + (now.minute * 60) + now.second;
    int secondsInWeek = (dayOfWeek * 86400) + secondsInDay;

    setState(() {
      _meters['time_of_day'] = secondsInDay / 86400.0;
      _meters['police_patrol'] = secondsInDay / 86400.0;
      _meters['municipal_services'] = secondsInWeek / 604800.0;
      _meters['crowd_density'] = _getCrowdDensity(now);
      _meters['weather_condition'] = _getDeterministicWeather(secondsSinceEpoch);
    });
  }

  // --- FETCH & EXECUTE ---
  Future<void> _fetchSearchingCrimes() async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/crimes/list'));
      if (response.statusCode == 200) {
        final List<dynamic> allCrimes = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _crimes = allCrimes.where((c) => c['sub_category'] == 'Searching').toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executeCrime(Map<String, dynamic> crime) async {
    if (widget.userData['nerve'] < crime['nerve_cost']) {
      _showResultSnackbar("NO NERVE", "You don't have enough Nerve.", Colors.purpleAccent);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/crimes/execute'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userData['user_id'], "crime_id": crime['id']}),
      );

      if (!mounted) return;
      final result = jsonDecode(response.body);

      if (result['user'] != null) widget.onStateChange(result['user']);

      if (response.statusCode == 200) {
        if (result['arrested'] == true) {
          _showResultSnackbar("BUSTED!", result['message'], Colors.redAccent);
        } else {
          switch (result['status']) {
            case "success": _showResultSnackbar("SUCCESS", "${result['message']}\n+ \$${result['gained_cash']}", const Color(0xFF39FF14)); break;
            case "escaped": _showResultSnackbar("NOTHING FOUND", result['message'], Colors.yellowAccent); break;
            case "hospitalized": _showResultSnackbar("HOSPITALIZED", result['message'], Colors.orangeAccent); break;
            case "jailed": _showResultSnackbar("JAILED", result['message'], Colors.redAccent); break;
          }
        }
      } else {
        _showResultSnackbar("FAILED", result['error'] ?? "Unknown error.", Colors.redAccent);
      }
    } catch (e) {
      if (!mounted) return;
      _showResultSnackbar("CONNECTION LOST", "Cannot reach the game servers.", Colors.redAccent);
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

  double _getDistance(String meterType, double current, double min, double max, bool isCyclical) {
    if (isCyclical && min > max) {
      if (current >= min || current <= max) return 0.0;
    } else {
      if (current >= min && current <= max) return 0.0;
    }

    // THE SAWTOOTH LOGIC
    if (meterType == 'municipal_services') {
      if (current > max) return 1.0; // Instantly Empty!
      return (min - current).abs();  // Slowly Building up!
    }

    // THE BELL CURVE LOGIC
    double distToMin = (current - min).abs();
    double distToMax = (current - max).abs();

    if (isCyclical) {
      if (distToMin > 0.5) distToMin = 1.0 - distToMin;
      if (distToMax > 0.5) distToMax = 1.0 - distToMax;
    }
    return math.min(distToMin, distToMax);
  }

  double _getMeterScore(String meterType, double currentPct, List<dynamic> spotsArray) {
    double bestScore = 10.0;
    bool isCyclical = (meterType == 'time_of_day' || meterType == 'police_patrol' || meterType == 'weather_condition');

    for (var spot in spotsArray) {
      double min = spot[0].toDouble();
      double max = spot[1].toDouble();

      // Pass the meterType into our updated distance math
      double distance = _getDistance(meterType, currentPct, min, max, isCyclical);
      if (distance == 0.0) return 99.0;

      double maxDist = isCyclical ? 0.5 : 1.0;
      double fractionOutside = distance / maxDist;

      double harshPenalty = math.pow(fractionOutside, 0.5) * 89.0;
      double score = 99.0 - harshPenalty;

      if (score > bestScore) bestScore = score;
    }
    return bestScore.clamp(10.0, 99.0);
  }

  double _calculateAverageSuccess(Map<String, dynamic> crime) {
    final mechanics = crime['mechanics_json'] ?? {};
    String pMeter = mechanics['primary_meter'] ?? 'time_of_day';
    List<dynamic> pSpots = mechanics['p_spots'] ?? [[mechanics['p_min'] ?? 0.0, mechanics['p_max'] ?? 1.0]];
    String sMeter = mechanics['secondary_meter'] ?? 'time_of_day';
    List<dynamic> sSpots = mechanics['s_spots'] ?? [[mechanics['s_min'] ?? 0.0, mechanics['s_max'] ?? 1.0]];

    double pValue = _meters.containsKey(pMeter) ? _meters[pMeter]! : _meters['municipal_services'] ?? 0.0;
    double sValue = _meters.containsKey(sMeter) ? _meters[sMeter]! : _meters['municipal_services'] ?? 0.0;

    double primaryScore = _getMeterScore(pMeter, pValue, pSpots);
    double secondaryScore = _getMeterScore(sMeter, sValue, sSpots);
    return (primaryScore + secondaryScore) / 2.0;
  }

  Color _getDynamicColor(double rate) {
    // Stricter Thresholds: Average must be over 80 to turn Green!
    if (rate <= 50.0) return Colors.redAccent;
    if (rate <= 80.0) return Color.lerp(Colors.redAccent, Colors.blueAccent, (rate - 50.0) / (80.0 - 50.0)) ?? Colors.blueAccent;
    return Color.lerp(Colors.blueAccent, const Color(0xFF39FF14), (rate - 80.0) / (99.0 - 80.0)) ?? const Color(0xFF39FF14);
  }

  // --- UI COMPONENTS ---
  Widget _buildIconLegends(List<Map<String, dynamic>> iconData) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 24,
          child: Stack(
            clipBehavior: Clip.none,
            children: iconData.map((data) {
              double align = data['align'] ?? 0.0;
              return Positioned(
                left: (constraints.maxWidth * align) - 8,
                child: Tooltip(
                  message: data['tooltip'],
                  preferBelow: false,
                  textStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF39FF14))
                  ),
                  child: Icon(data['icon'], color: Colors.white54, size: 16),
                ),
              );
            }).toList(),
          ),
        );
      },
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
              const Text("SEARCHING OPERATIONS", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            ],
          ),
        ),

        Container(
          height: 320,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            border: Border(bottom: BorderSide(color: Color(0xFF39FF14), width: 1)),
          ),
          child: Stack(
            children: [
              const Positioned(right: -20, bottom: -20, child: Icon(Icons.search, size: 250, color: Colors.white10)),
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
                width: isMobile ? MediaQuery.of(context).size.width : MediaQuery.of(context).size.width * 0.40,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.transparent,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),

                        _buildAutonomousMeter('municipal_services', 'MUNICIPAL SERVICES (7-DAY)', _buildIconLegends([
                          {'icon': Icons.cleaning_services, 'tooltip': 'Sanitation Route (Tue)', 'align': 0.16},
                          {'icon': Icons.handyman, 'tooltip': 'Maintenance Check (Wed)', 'align': 0.34},
                          {'icon': Icons.cleaning_services, 'tooltip': 'Sanitation Route (Fri)', 'align': 0.59},
                          {'icon': Icons.handyman, 'tooltip': 'Maintenance Check (Sun)', 'align': 0.91},
                        ])),

                        _buildAutonomousMeter('police_patrol', 'POLICE PATROL SCHEDULE', _buildIconLegends([
                          {'icon': Icons.groups, 'tooltip': 'Shift Swap', 'align': 0.09},
                          {'icon': Icons.coffee, 'tooltip': 'Morning Break', 'align': 0.25},
                          {'icon': Icons.restaurant, 'tooltip': 'Lunch', 'align': 0.42},
                          {'icon': Icons.groups, 'tooltip': 'Shift Swap', 'align': 0.52},
                          {'icon': Icons.coffee, 'tooltip': 'Afternoon Break', 'align': 0.59},
                          {'icon': Icons.restaurant, 'tooltip': 'Dinner', 'align': 0.67},
                          {'icon': Icons.groups, 'tooltip': 'Night Shift Swap', 'align': 0.81},
                          {'icon': Icons.coffee, 'tooltip': 'Midnight Break', 'align': 0.92},
                        ])),

                        _buildAutonomousMeter('crowd_density', 'CROWD DENSITY', _buildIconLegends([
                          {'icon': Icons.person_off, 'tooltip': 'Dead/Empty', 'align': 0.1},
                          {'icon': Icons.groups_2, 'tooltip': 'Normal Traffic', 'align': 0.5},
                          {'icon': Icons.festival, 'tooltip': 'Packed/Rush Hour', 'align': 0.9},
                        ])),

                        _buildAutonomousMeter('weather_condition', 'LOCAL WEATHER RADAR', _buildIconLegends([
                          {'icon': Icons.wb_sunny, 'tooltip': 'Clear Skies', 'align': 0.12},
                          {'icon': Icons.cloud, 'tooltip': 'Overcast / Fog', 'align': 0.37},
                          {'icon': Icons.water_drop, 'tooltip': 'Light Rain', 'align': 0.62},
                          {'icon': Icons.thunderstorm, 'tooltip': 'Heavy Storm', 'align': 0.87},
                        ])),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF39FF14)))
              : _crimes.isEmpty
              ? const Center(child: Text("No targets found.", style: TextStyle(color: Colors.white54)))
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

  Widget _buildAutonomousMeter(String meterKey, String title, Widget legendRow) {
    double currentPct = _meters[meterKey] ?? 0.0;

    bool isRelevant = false;
    List<dynamic> targetSpots = [];

    if (_focusedCrime != null) {
      final mechanics = _focusedCrime!['mechanics_json'] ?? {};
      if (mechanics['primary_meter'] == meterKey) {
        isRelevant = true;
        targetSpots = mechanics['p_spots'] ?? [[mechanics['p_min'] ?? 0.0, mechanics['p_max'] ?? 1.0]];
      } else if (mechanics['secondary_meter'] == meterKey) {
        isRelevant = true;
        targetSpots = mechanics['s_spots'] ?? [[mechanics['s_min'] ?? 0.0, mechanics['s_max'] ?? 1.0]];
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: isRelevant ? const Color(0xFF39FF14) : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 6),

        LayoutBuilder(
          builder: (context, constraints) {
            double width = constraints.maxWidth;
            return Container(
              height: 12,
              decoration: BoxDecoration(color: isRelevant ? Colors.redAccent.withOpacity(0.3) : Colors.white10, borderRadius: BorderRadius.circular(6)),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // --- THE EXPANDED GRADIENT AURAS ---
                  // --- STRIKE ZONE RENDERING ---
                  if (isRelevant)
                    ...targetSpots.map((spot) {
                      double tMin = spot[0].toDouble();
                      double tMax = spot[1].toDouble();

                      // 1. ASYMMETRICAL SAWTOOTH (For Municipal Services)
                      if (meterKey == 'municipal_services') {
                        // Long buildup gradient (approx 1 full day of buildup)
                        double pMin = tMin - 0.15;
                        return Positioned(
                          left: width * pMin, width: width * (tMax - pMin),
                          child: Container(
                              height: 12,
                              decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, Color(0xAA39FF14), Color(0xFF39FF14)],
                                    stops: [0.0, 0.7, 1.0], // Slowly fades in, stays solid right up to the end!
                                  ),
                                  borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(6), bottomLeft: Radius.circular(6),
                                      topRight: Radius.circular(2), bottomRight: Radius.circular(2) // Sharp flat edge on the right
                                  )
                              )
                          ),
                        );
                      }

                      // 2. SYMMETRICAL BELL CURVE (For Weather, Police, Crowds)
                      else {
                        double pMin = tMin - 0.06;
                        double pMax = tMax + 0.06;

                        if (tMin > tMax) { // Cyclical wrap-around handling
                          return Stack(
                            children: [
                              Positioned(
                                  left: width * pMin, width: width * (1.0 - pMin),
                                  child: Container(height: 12, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Color(0xFF39FF14), Color(0xFF39FF14)], stops: [0.0, 0.4, 1.0]), borderRadius: BorderRadius.only(topLeft: Radius.circular(6), bottomLeft: Radius.circular(6))))
                              ),
                              Positioned(
                                  left: 0, width: width * pMax,
                                  child: Container(height: 12, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF39FF14), Color(0xFF39FF14), Colors.transparent], stops: [0.0, 0.6, 1.0]), borderRadius: BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6))))
                              ),
                            ],
                          );
                        } else {
                          return Positioned(
                            left: width * pMin, width: width * (pMax - pMin),
                            child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Colors.transparent, Color(0xAA39FF14), Color(0xFF39FF14), Color(0xFF39FF14), Color(0xAA39FF14), Colors.transparent],
                                      stops: [0.0, 0.25, 0.4, 0.6, 0.75, 1.0],
                                    ),
                                    borderRadius: BorderRadius.circular(6)
                                )
                            ),
                          );
                        }
                      }
                    }),

                  Positioned(
                    left: (width - 4) * currentPct,
                    child: Container(
                      width: 4, height: 12,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2), boxShadow: const [BoxShadow(color: Colors.white, blurRadius: 4)]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        legendRow,
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildCrimeCard(Map<String, dynamic> crime) {
    double averageSuccessRate = _calculateAverageSuccess(crime);
    Color dynamicColor = _getDynamicColor(averageSuccessRate);
    bool isFocused = _focusedCrime != null && _focusedCrime!['id'] == crime['id'];

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
                  setState(() { _focusedCrime = crime; });
                },
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(5), bottomLeft: Radius.circular(5)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      crime['title'].toString().toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _executeCrime(crime),
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
                    Text("${crime['nerve_cost']} ", style: TextStyle(color: dynamicColor, fontSize: 15, fontWeight: FontWeight.w900)),
                    Icon(Icons.search, color: dynamicColor, size: 16),
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