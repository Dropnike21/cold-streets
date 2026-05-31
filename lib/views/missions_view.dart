import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api_config.dart';
import 'tutorial_beacon.dart';

class MissionsView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final VoidCallback onBack;
  final VoidCallback? onMissionRead;
  final String? activeBeacon;
  final bool isWaitingForMessage;

  final bool tut1Vitals;
  final bool tut1Assets;
  final bool tut2Inv;
  final bool tut2Prop;
  final bool tut2Ach;

  final bool tut3Search;
  final bool tut3Shop;
  final bool tut3Pick;

  // 🚨 NEW PROP TO RECEIVE THE SILENT COUNTER
  final int tut3CrimesDoneCount;

  const MissionsView({
    super.key,
    required this.userData,
    required this.onStateChange,
    required this.onBack,
    this.onMissionRead,
    this.activeBeacon,
    this.isWaitingForMessage = false,
    this.tut1Vitals = false,
    this.tut1Assets = false,
    this.tut2Inv = false,
    this.tut2Prop = false,
    this.tut2Ach = false,
    this.tut3Search = false,
    this.tut3Shop = false,
    this.tut3Pick = false,
    this.tut3CrimesDoneCount = 0,
  });

  @override
  State<MissionsView> createState() => _MissionsViewState();
}

class _MissionsViewState extends State<MissionsView> {
  String? _activeContact;
  bool _isLoadingMission = false;
  Map<String, dynamic>? _currentMissionData;
  bool _isProcessingAction = false;

  Map<String, dynamic> _getContactExp() {
    if (widget.userData['contact_exp'] == null) return {};
    if (widget.userData['contact_exp'] is String) return jsonDecode(widget.userData['contact_exp']);
    return Map<String, dynamic>.from(widget.userData['contact_exp']);
  }

  Map<String, dynamic>? _getActiveContract() {
    if (widget.userData['active_contract'] == null) return null;
    if (widget.userData['active_contract'] is String) return jsonDecode(widget.userData['active_contract']);
    return Map<String, dynamic>.from(widget.userData['active_contract']);
  }

  int _getExpFor(String contact) {
    final expMap = _getContactExp();
    final value = expMap[contact];
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  void _handleBack() {
    if (_activeContact != null) {
      setState(() { _activeContact = null; _currentMissionData = null; });
    } else {
      widget.onBack();
    }
  }

  Future<void> _fetchMissionData(String contact) async {
    if (contact != 'anonymous') return;
    setState(() => _isLoadingMission = true);
    try {
      final String id = widget.userData['user_id'].toString();
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/missions/details/$id/$contact'));
      if (response.statusCode == 200 && mounted) {
        setState(() => _currentMissionData = jsonDecode(response.body)['mission']);
      }
    } catch (e) {
      debugPrint("Mission Fetch Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingMission = false);
    }
  }

  Future<void> _processAction(String contact, String actionType) async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/missions/action'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": widget.userData['user_id'], "contact": contact, "action_type": actionType}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && mounted) {
        widget.onStateChange(data['user']);

        if (contact == 'anonymous' && actionType == 'VERIFY') {
          widget.onBack();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? "Action complete."), backgroundColor: const Color(0xFF39FF14)));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'] ?? "Server error."), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection lost."), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Map<String, dynamic> _getAnonymousMissionFallback(int exp) {
    switch (exp) {
      case 1: return { "title": "GET YOUR BEARINGS", "message": "Before you hit the streets, you need to know your limits and what's in your pockets. Get familiar with your HUD.", "objective": "Check your Vitals and Inspect your Assets.", "reward": "\$500 Dirty Cash" };
      case 2: return { "title": "KNOW YOUR STASH", "message": "You survived day one. Now, memorize where you keep your gear, where you sleep, and what you've accomplished. Navigate through your core menus.", "objective": "Navigate to your Inventory, Properties, and Achievements.", "reward": "50 Nerve & \$100 Cash" };
      case 3: return { "title": "FIRST BLOOD", "message": "Now that you know your way around, it's time to earn your keep. Scope out the local crime spots and pull off a successful job.", "objective": "Open Searching, Shoplifting, and Pickpocket tabs, then pull off 20 successful crimes.", "reward": "700 Gym Energy" };
      default: return { "title": "END OF THE LINE", "message": "I've taught you all I can. A guy named Kevin is looking for reliable muscle. Check your contact list.", "objective": "No further objectives.", "reward": "None." };
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
              IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.orangeAccent, size: 16), onPressed: _handleBack),
              Text(_activeContact == null ? "BURNER PHONE" : "ENCRYPTED COMMS", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
              const Spacer(),
              const Icon(Icons.signal_cellular_4_bar, color: Colors.orangeAccent, size: 16),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF050505),
            child: _activeContact == null ? _buildContactList() : _buildChatThread(),
          ),
        ),
      ],
    );
  }

  Widget _buildContactList() {
    int anonExp = _getExpFor('anonymous');
    int kevinExp = _getExpFor('kevin');
    int johnExp = _getExpFor('uncle_john');

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text("CONTACTS", style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2.0, fontFamily: 'monospace')),
        const SizedBox(height: 12),

        TutorialBeacon(
          id: 'contact_anonymous',
          activeId: widget.activeBeacon,
          child: _buildContactTile(
            name: "Anonymous",
            phone: "+63 945 112 ****",
            repScore: anonExp,
            maxRep: 50,
            color: widget.isWaitingForMessage ? Colors.white24 : Colors.grey,
            icon: widget.isWaitingForMessage ? Icons.lock_clock : Icons.help_outline,
            subtitleOverride: widget.isWaitingForMessage ? "Decrypting transmission..." : null,
            onTap: widget.isWaitingForMessage ? null : () {
              setState(() => _activeContact = 'anonymous');
              _fetchMissionData('anonymous');
              if (widget.onMissionRead != null) widget.onMissionRead!();
            },
          ),
        ),

        if (anonExp >= 50)
          _buildContactTile(name: "Kevin", phone: "+63 917 883 ****", repScore: kevinExp, maxRep: 200, color: Colors.orangeAccent, icon: Icons.local_fire_department, onTap: () => setState(() => _activeContact = 'kevin')),

        if (kevinExp >= 200)
          _buildContactTile(name: "Uncle John", phone: "+63 920 555 ****", repScore: johnExp, maxRep: 1000, color: Colors.redAccent, icon: Icons.business_center, onTap: () => setState(() => _activeContact = 'uncle_john')),
      ],
    );
  }

  Widget _buildContactTile({required String name, required String phone, required int repScore, required int maxRep, required Color color, required IconData icon, required VoidCallback? onTap, String? subtitleOverride}) {
    double progress = (repScore / maxRep).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: const Color(0xFF161616), border: Border.all(color: color.withOpacity(0.5)), borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: SizedBox(
          width: 42, height: 42,
          child: Stack(children: [
            Center(child: CircleAvatar(radius: 18, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 18))),
            Positioned.fill(child: CircularProgressIndicator(value: progress, color: color, backgroundColor: Colors.white10, strokeWidth: 3.5)),
          ]),
        ),
        title: Text(name, style: TextStyle(color: onTap == null ? Colors.white38 : Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitleOverride ?? "REP: $repScore / $maxRep", style: TextStyle(color: color.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold)),
        trailing: Text(phone, style: const TextStyle(color: Colors.white38, fontSize: 13, fontFamily: 'monospace', letterSpacing: 1.0)),
      ),
    );
  }

  Widget _buildChatThread() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
          child: Row(
            children: [
              const Icon(Icons.account_circle, color: Colors.white54, size: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_activeContact!.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const Text("Encrypted Peer-to-Peer", style: TextStyle(color: Colors.white38, fontSize: 10)),
              ])),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingMission
              ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
              : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_activeContact == 'anonymous') _buildAnonymousChat(),
              if (_activeContact == 'kevin') _buildKevinChat(),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildChecklistItem(String text, bool isDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isDone ? Icons.check_box : Icons.check_box_outline_blank, color: isDone ? Colors.grey : Colors.orangeAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                text,
                style: TextStyle(
                  color: isDone ? Colors.grey : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                )
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnonymousChat() {
    int anonExp = _getExpFor('anonymous');
    Map<String, dynamic> missionData = _currentMissionData ?? _getAnonymousMissionFallback(anonExp);

    Widget objectiveWidget;
    bool canVerify = false;

    if (anonExp == 1) {
      canVerify = widget.tut1Vitals && widget.tut1Assets;
      objectiveWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChecklistItem("Check your Vitals (Top Bar)", widget.tut1Vitals),
          _buildChecklistItem("Inspect your Assets (Side Menu)", widget.tut1Assets),
        ],
      );
    }
    else if (anonExp == 2) {
      canVerify = widget.tut2Inv && widget.tut2Prop && widget.tut2Ach;
      objectiveWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChecklistItem("Access your Inventory", widget.tut2Inv),
          _buildChecklistItem("Access your Properties", widget.tut2Prop),
          _buildChecklistItem("Access your Achievements", widget.tut2Ach),
        ],
      );
    }
    // 🚨 REP 3: 20-CRIME SILENT CHECKLIST LOGIC
    else if (anonExp == 3) {
      bool hasDoneCrime = widget.tut3CrimesDoneCount >= 20;
      int displayCount = widget.tut3CrimesDoneCount > 20 ? 20 : widget.tut3CrimesDoneCount;

      canVerify = widget.tut3Search && widget.tut3Shop && widget.tut3Pick && hasDoneCrime;
      objectiveWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChecklistItem("Scout the Searching area", widget.tut3Search),
          _buildChecklistItem("Scout the Shoplifting area", widget.tut3Shop),
          _buildChecklistItem("Scout the Pickpocketing area", widget.tut3Pick),
          _buildChecklistItem("Pull off 20 successful crimes ($displayCount / 20)", hasDoneCrime),
        ],
      );
    }
    else {
      objectiveWidget = Text(missionData['objective_text'] ?? "", style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold, height: 1.4));
      canVerify = true;
    }

    return _buildMessageBubble(
        title: missionData['title'] ?? "SECURE MSG",
        message: missionData['message'] ?? "",
        objectiveWidget: objectiveWidget,
        reward: missionData['reward_text'] ?? "",
        buttons: (!canVerify || missionData['title'] == "END OF THE LINE") ? [] : [
          TutorialBeacon(
            id: 'btn_verify_anon',
            activeId: widget.activeBeacon,
            glowColor: const Color(0xFF39FF14),
            child: _buildActionBtn("VERIFY COMPLETION (+1 REP)", const Color(0xFF39FF14), () {
              _processAction('anonymous', 'VERIFY');
            }),
          )
        ]
    );
  }

  Widget _buildKevinChat() {
    final contract = _getActiveContract();

    if (contract == null || contract['fixer'] != 'kevin') {
      return _buildMessageBubble(
          title: "STANDBY FOR WORK", message: "You looking for a hustle? I got names and targets, but you gotta commit.",
          objectiveWidget: const Text("Request a dynamic contract from Kevin.", style: TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold, height: 1.4)),
          reward: "Variable Cash & EXP",
          buttons: [_buildActionBtn("REQUEST NEW CONTRACT", Colors.orangeAccent, () => _processAction('kevin', 'REQUEST'))]
      );
    }

    Widget dynamicObjective = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChecklistItem("Crimes: ${contract['progress']['crimes']} / ${contract['reqs']['crimes']}", contract['progress']['crimes'] >= contract['reqs']['crimes']),
        _buildChecklistItem("Gym: ${contract['progress']['gym']} / ${contract['reqs']['gym']}", contract['progress']['gym'] >= contract['reqs']['gym']),
      ],
    );

    return _buildMessageBubble(
        title: "ACTIVE CONTRACT", message: "Here are the details. Get it done, and report back.",
        objectiveWidget: dynamicObjective,
        reward: "\$${contract['reward_cash']} Dirty Cash",
        buttons: [
          _buildActionBtn("TURN IN CONTRACT (+2 REP)", const Color(0xFF39FF14), () => _processAction('kevin', 'TURN_IN')),
          const SizedBox(height: 8),
          _buildActionBtn("PARTIAL TURN-IN (-1 REP)", Colors.yellowAccent, () => _processAction('kevin', 'PARTIAL')),
          const SizedBox(height: 8),
          _buildActionBtn("ABORT CONTRACT (-2 REP)", Colors.redAccent, () => _processAction('kevin', 'ABORT')),
        ]
    );
  }

  Widget _buildMessageBubble({required String title, required String message, required Widget objectiveWidget, required String reward, required List<Widget> buttons}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF161616), border: Border.all(color: Colors.white10), borderRadius: const BorderRadius.only(topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          const Text("CURRENT OBJECTIVES:", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          objectiveWidget,
          const SizedBox(height: 12),
          Row(children: [const Icon(Icons.card_giftcard, color: Color(0xFF39FF14), size: 14), const SizedBox(width: 8), Expanded(child: Text("REWARD: $reward", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 12, fontWeight: FontWeight.bold)))]),
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: 24),
            if (_isProcessingAction) const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)) else ...buttons
          ]
        ],
      ),
    );
  }

  Widget _buildActionBtn(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity, height: 45,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(side: BorderSide(color: color.withOpacity(0.5), width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: color.withOpacity(0.05)),
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
      ),
    );
  }
}