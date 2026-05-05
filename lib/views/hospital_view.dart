import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class HospitalView extends StatefulWidget {
  final Map<String, dynamic> userData;

  const HospitalView({super.key, required this.userData});

  @override
  State<HospitalView> createState() => _HospitalViewState();
}

class _HospitalViewState extends State<HospitalView> {
  final String apiUrl = "http://10.0.2.2:3000/hospital";

  bool _isLoading = true;
  bool _isProcessing = false;
  List<dynamic> _patients = [];

  int _currentPage = 1;
  int _totalPages = 1;
  Timer? _localTicker;

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);
  final Color darkSurface = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _fetchPatients();

    // Ticks locally so we don't spam the server
    _localTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    super.dispose();
  }

  Future<void> _fetchPatients() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('$apiUrl/patients?page=$_currentPage&limit=20'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _patients = data['patients'] ?? [];
            _currentPage = data['pagination']['current_page'];
            _totalPages = data['pagination']['total_pages'];
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

  String? _getTimeRemaining(String? expiresAt) {
    if (expiresAt == null) return null;
    DateTime expiry = DateTime.parse(expiresAt).toLocal();
    Duration diff = expiry.difference(DateTime.now());

    if (diff.isNegative) return null; // Time is up!

    int h = diff.inHours;
    int m = diff.inMinutes % 60;
    int s = diff.inSeconds % 60;

    if (h > 0) return "${h}h ${m}m ${s}s";
    return "${m}m ${s}s";
  }

  bool _isOnline(String? lastActiveAt) {
    if (lastActiveAt == null) return false;
    DateTime lastActive = DateTime.parse(lastActiveAt).toLocal();
    return DateTime.now().difference(lastActive).inMinutes <= 5;
  }

  Future<void> _processRevive(String targetId) async {
    setState(() => _isProcessing = true);
    try {
      final res = await http.post(Uri.parse('$apiUrl/revive'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": widget.userData['user_id'], "target_id": targetId})
      );
      final data = jsonDecode(res.body);

      _showSnackbar(data['message'] ?? data['error'], isError: res.statusCode != 200);
      await _fetchPatients();
    } catch (e) {
      _showSnackbar("Network error.", isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("CITY HOSPITAL", style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
        iconTheme: const IconThemeData(color: Colors.redAccent),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54), onPressed: _fetchPatients),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // --- PAGINATION BAR ---
              Container(
                color: const Color(0xFF1A1A1A),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white),
                        onPressed: _currentPage > 1 ? () { setState(() => _currentPage--); _fetchPatients(); } : null,
                        disabledColor: Colors.white24, constraints: const BoxConstraints(), padding: EdgeInsets.zero
                    ),
                    Text("PAGE $_currentPage OF $_totalPages", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.white),
                        onPressed: _currentPage < _totalPages ? () { setState(() => _currentPage++); _fetchPatients(); } : null,
                        disabledColor: Colors.white24, constraints: const BoxConstraints(), padding: EdgeInsets.zero
                    ),
                  ],
                ),
              ),

              // --- LEDGER HEADER ---
              Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF333333)))),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text("PATIENT / REASON", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text("PROGNOSIS", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text("ACTIONS", textAlign: TextAlign.right, style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),

              // --- PATIENT LIST ---
              Expanded(
                child: _patients.isEmpty
                    ? const Center(child: Text("The ICU is currently empty.", style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                  itemCount: _patients.length,
                  itemBuilder: (context, index) {
                    var patient = _patients[index];
                    bool isMe = patient['user_id'].toString() == widget.userData['user_id'].toString();

                    String? timeLeft = _getTimeRemaining(patient['hospital_expires_at']);
                    bool isDischarged = timeLeft == null;
                    bool isOnline = _isOnline(patient['last_active_at']);

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
                                    "${patient['username']} [${patient['user_id']}]",
                                    style: TextStyle(color: isMe ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  patient['reason'] ?? "Admitted with severe trauma injuries.",
                                  style: const TextStyle(color: Colors.white54, fontSize: 9, height: 1.2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          // COLUMN 2: Timer & Status
                          Expanded(
                            flex: 2,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                    isDischarged ? "DISCHARGED" : timeLeft!,
                                    style: TextStyle(
                                        color: isDischarged ? neonGreen : Colors.redAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'Courier'
                                    )
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.circle, size: 8, color: isOnline ? neonGreen : Colors.white24),
                                    const SizedBox(width: 4),
                                    Text(isOnline ? "ONLINE" : "OFFLINE", style: TextStyle(color: isOnline ? neonGreen : Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          ),

                          // COLUMN 3: Revive Button
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 28,
                                child: ElevatedButton.icon(
                                  onPressed: isDischarged ? null : () => _processRevive(patient['user_id'].toString()),
                                  icon: Icon(Icons.medical_services, size: 12, color: isDischarged ? Colors.white24 : Colors.redAccent),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent.withOpacity(0.1),
                                      side: const BorderSide(color: Colors.redAccent),
                                      padding: const EdgeInsets.symmetric(horizontal: 10)
                                  ),
                                  label: Text("REVIVE", style: TextStyle(color: isDischarged ? Colors.white24 : Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ),
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