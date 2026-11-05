import 'package:flutter/material.dart';
import '../services/game_http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../api_config.dart';

class JailView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>)? onStateChange;

  const JailView({super.key, required this.userData, this.onStateChange});

  @override
  State<JailView> createState() => _JailViewState();
}

class _JailViewState extends State<JailView> {

  String get apiUrl => "${ApiConfig.baseUrl}/jail";

  bool _isLoading = true;
  bool _isProcessing = false;
  List<dynamic> _inmates = [];

  Timer? _localTicker;

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _fetchInmates();

    // The Local Ticker: Updates the UI every second without hitting the server
    _localTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    super.dispose();
  }

  Future<void> _fetchInmates() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('$apiUrl/inmates'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _inmates = data['inmates'] ?? [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier')),
        backgroundColor: isError ? Colors.redAccent.shade700 : neonGreen.withOpacity(0.8)));
  }

  // Returns formatted time OR null if the timer has expired
  String? _getTimeRemaining(String expiresAt) {
    DateTime expiry = DateTime.parse(expiresAt).toLocal();
    Duration diff = expiry.difference(DateTime.now());

    if (diff.isNegative) return null; // Time is up!

    int h = diff.inHours;
    int m = diff.inMinutes % 60;
    int s = diff.inSeconds % 60;

    if (h > 0) return "${h}h ${m}m ${s}s";
    return "${m}m ${s}s";
  }

  void _showPausedMechanic() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Jail bail, breakout and prison-yard training are paused pending source-reconciled mechanics.',
        ),
        backgroundColor: Colors.white24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMeJailed = _inmates.any((i) => i['user_id'].toString() == widget.userData['user_id'].toString());

    return Scaffold(
      backgroundColor: matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("STATE PENITENTIARY", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
        iconTheme: const IconThemeData(color: Colors.grey),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54), onPressed: _fetchInmates),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // --- INMATE YARD DASHBOARD (Only visible if you are in jail) ---
              if (isMeJailed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.1), border: const Border(bottom: BorderSide(color: Colors.orangeAccent))),
                  child: Row(
                    children: [
                      const Icon(Icons.fitness_center, color: Colors.orangeAccent, size: 32),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("THE PRISON YARD", style: TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            Text("Lift rusted weights to burn Energy. Gains are heavily nerfed and split across all stats.", style: TextStyle(color: Colors.white70, fontSize: 10)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(backgroundColor: matteBlack, side: const BorderSide(color: Colors.white24)),
                        child: const Text("YARD PAUSED", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),

              // --- INMATE LEDGER HEADER ---
              Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: const Color(0xFF1A1A1A),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text("INMATE / REASON", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text("SENTENCE", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 3, child: Text("ACTIONS", textAlign: TextAlign.right, style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),

              // --- INMATE LIST ---
              Expanded(
                child: _inmates.isEmpty
                    ? const Center(child: Text("The cells are currently empty.", style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                  itemCount: _inmates.length,
                  itemBuilder: (context, index) {
                    var inmate = _inmates[index];
                    bool isMe = inmate['user_id'].toString() == widget.userData['user_id'].toString();

                    String? timeLeft = _getTimeRemaining(inmate['jail_expires_at']);
                    bool isReleased = timeLeft == null;

                    String arrestReason =
                        inmate['reason']?.toString().trim().isNotEmpty == true
                            ? inmate['reason'].toString()
                            : "Reason unavailable.";

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(color: isMe ? Colors.redAccent.withOpacity(0.05) : Colors.transparent, border: const Border(bottom: BorderSide(color: Color(0xFF333333)))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [

                          // COLUMN 1: Name and Reason
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    "${inmate['username']} [${inmate['user_id']}]",
                                    style: TextStyle(color: isMe ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Reason: $arrestReason",
                                  style: const TextStyle(color: Colors.white54, fontSize: 9, height: 1.2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          // COLUMN 2: The Timer
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Text(
                                  isReleased ? "RELEASED" : timeLeft!,
                                  style: TextStyle(
                                      color: isReleased ? neonGreen : Colors.orangeAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'Courier'
                                  )
                              ),
                            ),
                          ),

                          // COLUMN 3: Action Buttons (Stacked)
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                SizedBox(
                                  width: 120, height: 26,
                                  child: ElevatedButton(
                                    onPressed: null,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: isMe ? Colors.transparent : Colors.green.withOpacity(0.1),
                                        side: BorderSide(color: isMe ? Colors.white24 : Colors.green),
                                        padding: EdgeInsets.zero
                                    ),
                                    child: const Text(
                                        "BAIL PAUSED",
                                        style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 120, height: 26,
                                  child: ElevatedButton(
                                    onPressed: null,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent.withOpacity(0.1),
                                        side: const BorderSide(color: Colors.redAccent),
                                        padding: EdgeInsets.zero
                                    ),
                                    child: const Text(
                                        "BREAKOUT PAUSED",
                                        style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isLoading || _isProcessing) Container(color: Colors.black54, child: Center(child: CircularProgressIndicator(color: neonGreen)))
        ],
      ),
    );
  }
}