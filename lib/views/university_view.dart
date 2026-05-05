import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class UniversityView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>)? onStateChange;

  const UniversityView({super.key, required this.userData, this.onStateChange});

  @override
  State<UniversityView> createState() => _UniversityViewState();
}

class _UniversityViewState extends State<UniversityView> {
  final String apiUrl = "http://10.0.2.2:3000/university"; // Use your IP if on physical device

  bool _isLoading = true;
  bool _isProcessing = false;

  int _dirtyCash = 0;
  int? _activeCourseId;
  String? _courseExpiresAt;
  List<int> _completedCourses = [];
  List<dynamic> _tracks = [];
  List<dynamic> _courses = [];

  Timer? _localTicker;

  final Color neonGreen = const Color(0xFF39FF14);
  final Color matteBlack = const Color(0xFF121212);

  @override
  void initState() {
    super.initState();
    _fetchUniversityData();

    _localTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeCourseId != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    super.dispose();
  }

  Future<void> _fetchUniversityData() async {
    setState(() => _isLoading = true);
    try {
      final String userIdStr = widget.userData['user_id'].toString();
      final res = await http.get(Uri.parse('$apiUrl/$userIdStr'));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _dirtyCash = int.tryParse(data['dirty_cash']?.toString() ?? '0') ?? 0;
            _activeCourseId = data['active_course_id'] != null ? int.tryParse(data['active_course_id'].toString()) : null;
            _courseExpiresAt = data['course_expires_at'];

            // Safely parse completed courses as integers
            _completedCourses = (data['completed_courses'] as List?)?.map((e) => int.tryParse(e.toString()) ?? 0).toList() ?? [];

            _tracks = data['tracks'] ?? [];
            _courses = data['courses'] ?? [];
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

  String _formatCash(int amount) {
    return '\$${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  String _formatDuration(int seconds) {
    int d = seconds ~/ 86400;
    if (d > 0) return "$d Days";

    int h = (seconds % 86400) ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    return "${seconds} Seconds";
  }

  String? _getTimeRemaining(String? expiresAt) {
    if (expiresAt == null) return null;
    DateTime expiry = DateTime.parse(expiresAt).toLocal();
    Duration diff = expiry.difference(DateTime.now());

    if (diff.isNegative) return "00:00:00 (READY)";

    int d = diff.inDays;
    int h = diff.inHours % 24;
    int m = diff.inMinutes % 60;
    int s = diff.inSeconds % 60;

    if (d > 0) return "${d}d ${h}h ${m}m ${s}s";
    return "${h}h ${m}m ${s}s";
  }

  Future<void> _processAction(String endpoint, Map<String, dynamic> payload) async {
    setState(() => _isProcessing = true);
    try {
      final res = await http.post(Uri.parse('$apiUrl/$endpoint'),
          headers: {"Content-Type": "application/json"}, body: jsonEncode(payload));
      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        _showSnackbar(data['message']);

        // Sync stats instantly to HUD if graduation provided the updated user object
        if (endpoint == 'graduate' && data['user'] != null && widget.onStateChange != null) {
          widget.onStateChange!(data['user']);
        }
      } else {
        _showSnackbar(data['error'] ?? "Action failed.", isError: true);
      }

      await _fetchUniversityData();
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
        title: const Text("CITY UNIVERSITY", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
        iconTheme: const IconThemeData(color: Colors.lightBlueAccent),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54), onPressed: _fetchUniversityData),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_activeCourseId != null) _buildActiveEnrollmentBanner(),

              Container(
                width: double.infinity, padding: const EdgeInsets.all(16), color: const Color(0xFF1A1A1A),
                child: const Text("Enroll in long-term academic tracks to earn massive permanent boosts to your Working Stats. You can only take one course at a time.", style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent))
                    : ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    var track = _tracks[index];
                    int trackId = int.tryParse(track['track_id'].toString()) ?? 0;

                    List<dynamic> trackCourses = _courses.where((c) {
                      return (int.tryParse(c['track_id'].toString()) ?? 0) == trackId;
                    }).toList();

                    return ExpansionTile(
                      initiallyExpanded: true,
                      iconColor: Colors.lightBlueAccent,
                      collapsedIconColor: Colors.white54,
                      title: Text(track['title'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(track['description'] ?? "", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                      children: trackCourses.map((course) => _buildCourseCard(course)).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isProcessing) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent)))
        ],
      ),
    );
  }

  Widget _buildActiveEnrollmentBanner() {
    var activeCourse = _courses.firstWhere((c) => (int.tryParse(c['course_id'].toString()) ?? 0) == _activeCourseId, orElse: () => null);
    if (activeCourse == null) return const SizedBox.shrink();

    String timeStr = _getTimeRemaining(_courseExpiresAt) ?? "READY";
    bool isReady = timeStr.contains("READY");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.lightBlueAccent.withOpacity(0.1), border: const Border(bottom: BorderSide(color: Colors.lightBlueAccent, width: 2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("CURRENTLY ENROLLED", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activeCourse['title'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("TIME LEFT: $timeStr", style: TextStyle(color: isReady ? neonGreen : Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  ],
                ),
              ),
              if (!isReady)
                ElevatedButton(
                  onPressed: () => _processAction('dropout', {"user_id": widget.userData['user_id']}),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1), side: const BorderSide(color: Colors.redAccent)),
                  child: const Text("DROP OUT", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                )
              else
                ElevatedButton(
                  onPressed: () => _processAction('graduate', {"user_id": widget.userData['user_id']}),
                  style: ElevatedButton.styleFrom(backgroundColor: neonGreen.withOpacity(0.1), side: BorderSide(color: neonGreen)),
                  child: Text("GRADUATE", style: TextStyle(color: neonGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course) {
    int courseId = int.tryParse(course['course_id'].toString()) ?? 0;
    int prereqId = int.tryParse(course['prerequisite_course_id']?.toString() ?? '0') ?? 0;
    int cost = int.tryParse(course['cost_dirty_cash']?.toString() ?? '0') ?? 0;
    int duration = int.tryParse(course['duration_seconds']?.toString() ?? '0') ?? 0;

    bool isCompleted = _completedCourses.contains(courseId);
    bool isPrereqMet = prereqId == 0 || _completedCourses.contains(prereqId);
    bool isLocked = !isCompleted && !isPrereqMet;
    bool canAfford = _dirtyCash >= cost;

    Color cardBorderColor = isCompleted ? neonGreen : (isLocked ? Colors.redAccent : Colors.lightBlueAccent);

    String rewardStr = "";
    if (course['reward_stat_1'] != null) rewardStr += "+${course['reward_amount_1']} ${course['reward_stat_1'].toString().toUpperCase()}  ";
    if (course['reward_stat_2'] != null) rewardStr += "+${course['reward_amount_2']} ${course['reward_stat_2'].toString().toUpperCase()}";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(left: BorderSide(color: cardBorderColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(course['title'].toString().toUpperCase(), style: TextStyle(color: isLocked ? Colors.white54 : Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
              if (isCompleted)
                Icon(Icons.check_circle, color: neonGreen, size: 16)
              else if (isLocked)
                const Icon(Icons.lock, color: Colors.redAccent, size: 16)
              else
                Text(_formatCash(cost), style: TextStyle(color: canAfford ? Colors.lightBlueAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("DURATION: ${_formatDuration(duration)}", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text("REWARD: $rewardStr", style: TextStyle(color: isCompleted ? Colors.white24 : neonGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              if (!isCompleted && !isLocked && _activeCourseId == null)
                SizedBox(
                  height: 26, width: 80,
                  child: ElevatedButton(
                    onPressed: canAfford ? () => _processAction('enroll', {"user_id": widget.userData['user_id'], "course_id": courseId}) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlueAccent.withOpacity(0.1),
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: Colors.lightBlueAccent),
                    ),
                    child: const Text("ENROLL", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          )
        ],
      ),
    );
  }
}