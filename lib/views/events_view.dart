import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EventsView extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EventsView({super.key, required this.userData});

  @override
  State<EventsView> createState() => _EventsViewState();
}

class _EventsViewState extends State<EventsView> {
  static const Color cBlack = Color(0xFF121212);
  static const Color cNeonGreen = Color(0xFF39FF14);
  static const Color cDarkGrey = Color(0xFF1E1E1E);

  List<dynamic> _events = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final int _initialLimit = 20;
  final int _loadMoreLimit = 50;

  @override
  void initState() {
    super.initState();
    _fetchEvents(isInitial: true);
    _markEventsAsRead();
  }

  Future<void> _fetchEvents({bool isInitial = false}) async {
    if (isInitial) {
      setState(() { _isLoading = true; });
    } else {
      setState(() { _isLoadingMore = true; });
    }

    try {
      final String userId = widget.userData['user_id'].toString();
      int limit = isInitial ? _initialLimit : _loadMoreLimit;
      int offset = isInitial ? 0 : _events.length;

      final response = await http.get(
          Uri.parse('http://10.0.2.2:3000/events/$userId?limit=$limit&offset=$offset')
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          List<dynamic> newEvents = data['events'];

          setState(() {
            if (isInitial) {
              _events = newEvents;
            } else {
              _events.addAll(newEvents);
            }
            // If the server returned fewer events than we asked for, we've hit the end
            _hasMore = newEvents.length == limit;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching events: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // Tells the server to clear the unread notification badge
  Future<void> _markEventsAsRead() async {
    try {
      final String userId = widget.userData['user_id'].toString();
      await http.post(
        Uri.parse('http://10.0.2.2:3000/events/mark_read'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": userId}),
      );
    } catch (e) {
      debugPrint("Error marking events read: $e");
    }
  }

  // Extremely small, subtle icons based on event type
  IconData _getEventIcon(String type) {
    switch (type) {
      case 'achievement': return Icons.military_tech;
      case 'combat': return Icons.crisis_alert;
      case 'economy': return Icons.attach_money;
      case 'syndicate': return Icons.group;
      default: return Icons.info_outline;
    }
  }

  String _formatDate(String isoString) {
    if (isoString.isEmpty) return "";
    DateTime dt = DateTime.parse(isoString).toLocal();
    return "${dt.month}/${dt.day}/${dt.year} - ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: cNeonGreen),
        title: const Text(
          'EVENT LOG',
          style: TextStyle(color: cNeonGreen, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        centerTitle: true,
        elevation: 1,
        shadowColor: cNeonGreen.withValues(alpha: 0.5),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: cNeonGreen))
          : _events.isEmpty
          ? Center(child: Text("NO EVENTS LOGGED.", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)))
          : ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        // Add +1 to item count if we have more events to load, to render the Load More button
        itemCount: _events.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {

          // Render Load More Button at the bottom
          if (index == _events.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: _isLoadingMore
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: cNeonGreen, strokeWidth: 2))
                    : ElevatedButton(
                  onPressed: () => _fetchEvents(isInitial: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cDarkGrey,
                    side: const BorderSide(color: cNeonGreen),
                  ),
                  child: const Text("LOAD OLDER EVENTS", style: TextStyle(color: cNeonGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }

          // Render Standard Event Row
          var event = _events[index];
          bool isUnread = event['is_read'] == false;

          return Container(
            margin: const EdgeInsets.only(bottom: 6.0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              // Unread events get a very faint green background and a solid green left border
              color: isUnread ? cNeonGreen.withValues(alpha: 0.05) : cDarkGrey,
              border: Border(left: BorderSide(color: isUnread ? cNeonGreen : Colors.grey.shade800, width: 3)),
              borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _getEventIcon(event['event_type'] ?? 'system'),
                  color: isUnread ? cNeonGreen : Colors.grey.shade600,
                  size: 14, // Extremely small icon
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['event_text'] ?? "Unknown event.",
                        style: TextStyle(
                          color: isUnread ? Colors.white : Colors.grey.shade400,
                          fontSize: 12,
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(event['created_at'] ?? ''),
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}