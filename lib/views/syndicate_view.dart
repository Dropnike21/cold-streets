import 'package:flutter/material.dart';

class SyndicateView extends StatefulWidget {
  const SyndicateView({super.key});

  @override
  State<SyndicateView> createState() => _SyndicateViewState();
}

class _SyndicateViewState extends State<SyndicateView> {
  final List<Map<String, dynamic>> _npcRoster = const [
    {
      "name": "SLY",
      "assignment": "SHOPLIFT BODEGA",
      "price": "OWNED",
      "reqs": "NONE",
      "isRecruited": true,
      "stats": {
        "STRENGTH": {"current": 15, "max": 35},
        "DEFENSE": {"current": 20, "max": 40},
        "DEXTERITY": {"current": 65, "max": 90},
        "SPEED": {"current": 70, "max": 95},
        "INTELLIGENCE": {"current": 40, "max": 60},
      }
    },
    {
      "name": "GHOST",
      "assignment": "HACK ATM",
      "price": "OWNED",
      "reqs": "NONE",
      "isRecruited": true,
      "stats": {
        "STRENGTH": {"current": 10, "max": 20},
        "DEFENSE": {"current": 15, "max": 35},
        "DEXTERITY": {"current": 40, "max": 65},
        "SPEED": {"current": 50, "max": 70},
        "INTELLIGENCE": {"current": 75, "max": 100},
      }
    },
    {
      "name": "BRICK",
      "assignment": "UNASSIGNED",
      "price": "\$5,000",
      "reqs": "REP LVL 3",
      "isRecruited": false,
      "stats": {
        "STRENGTH": {"current": 60, "max": 95},
        "DEFENSE": {"current": 55, "max": 90},
        "DEXTERITY": {"current": 15, "max": 30},
        "SPEED": {"current": 20, "max": 45},
        "INTELLIGENCE": {"current": 10, "max": 25},
      }
    },
    {
      "name": "VIPER",
      "assignment": "UNASSIGNED",
      "price": "\$12,500",
      "reqs": "REP LVL 5",
      "isRecruited": false,
      "stats": {
        "STRENGTH": {"current": 40, "max": 70},
        "DEFENSE": {"current": 30, "max": 60},
        "DEXTERITY": {"current": 80, "max": 100},
        "SPEED": {"current": 85, "max": 100},
        "INTELLIGENCE": {"current": 50, "max": 80},
      }
    },
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF333333))),
            ),
            child: const TabBar(
              indicatorColor: Color(0xFF39FF14),
              labelColor: Color(0xFF39FF14),
              unselectedLabelColor: Colors.white54,
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              tabs: [
                Tab(text: "MY GANG"),
                Tab(text: "SYNDICATE"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildMyGangTab(),
                _buildSyndicateTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyGangTab() {
    final myGang = _npcRoster.where((npc) => npc["isRecruited"] == true).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  "ACTIVE CREW (${myGang.length})",
                  style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)
              ),
              SizedBox(
                height: 28,
                child: ElevatedButton.icon(
                  onPressed: () => _showRecruitmentBoard(context),
                  icon: const Icon(Icons.person_add, size: 14, color: Color(0xFF39FF14)),
                  label: const Text("RECRUIT", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF39FF14).withOpacity(0.1),
                    side: const BorderSide(color: Color(0xFF39FF14)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 0),
            itemCount: myGang.length,
            itemBuilder: (context, index) {
              return _buildNpcCard(myGang[index], false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSyndicateTab() {
    final myGangCount = _npcRoster.where((npc) => npc["isRecruited"] == true).length;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            border: Border.all(color: const Color(0xFF333333)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("SYNDICATE ESTABLISHMENT", style: TextStyle(color: Color(0xFF39FF14), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 10),
              _buildReqRow("GANG MEMBERS", "$myGangCount / 150", myGangCount / 150),
              _buildReqRow("CAPITAL", "\$4,250 / \$500,000,000", 4250 / 500000000),
              _buildReqRow(
                  "COMPLETE BUSINESSES",
                  "0 / 2",
                  0.0,
                  subtext: "Requires fully linked Production, Manufacturing & Distribution lines."
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF39FF14).withOpacity(0.1),
                    disabledBackgroundColor: const Color(0xFF121212),
                    side: const BorderSide(color: Color(0xFF333333)),
                  ),
                  child: const Text("INSUFFICIENT RESOURCES", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  void _showRecruitmentBoard(BuildContext context) {
    final recruits = _npcRoster.where((npc) => npc["isRecruited"] == false).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (BuildContext context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("RECRUITMENT BOARD", style: TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
              const Divider(color: Color(0xFF333333)),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(10.0),
                  itemCount: recruits.length,
                  itemBuilder: (context, index) {
                    return _buildNpcCard(recruits[index], true);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReqRow(String label, String value, double progress, {String? subtext}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          if (subtext != null) ...[
            const SizedBox(height: 2),
            Text(subtext, style: const TextStyle(color: Colors.white24, fontSize: 9, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF121212),
              color: const Color(0xFF39FF14).withOpacity(0.5),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNpcCard(Map<String, dynamic> npc, bool isRecruit) {
    Map<String, dynamic> stats = npc["stats"];
    const int tierAbsoluteMax = 100;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: isRecruit ? const Color(0xFF333333) : const Color(0xFF39FF14).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(npc["name"], style: TextStyle(color: isRecruit ? Colors.white : const Color(0xFF39FF14), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(
                        isRecruit ? "ROLE REQUIRES TRAINING" : "ASSIGNMENT: ${npc["assignment"]}",
                        style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
              ),
              if (isRecruit)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("COST: ${npc["price"]}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text("REQ: ${npc["reqs"]}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 24,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF39FF14).withOpacity(0.1),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: const BorderSide(color: Color(0xFF39FF14)),
                        ),
                        child: const Text("HIRE", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                )
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF333333), height: 1),
          const SizedBox(height: 12),
          _buildStatBar("STRENGTH", stats["STRENGTH"]["current"], stats["STRENGTH"]["max"], tierAbsoluteMax),
          _buildStatBar("DEFENSE", stats["DEFENSE"]["current"], stats["DEFENSE"]["max"], tierAbsoluteMax),
          _buildStatBar("DEXTERITY", stats["DEXTERITY"]["current"], stats["DEXTERITY"]["max"], tierAbsoluteMax),
          _buildStatBar("SPEED", stats["SPEED"]["current"], stats["SPEED"]["max"], tierAbsoluteMax),
          _buildStatBar("INTELLIGENCE", stats["INTELLIGENCE"]["current"], stats["INTELLIGENCE"]["max"], tierAbsoluteMax),
        ],
      ),
    );
  }

  Widget _buildStatBar(String label, int current, int max, int tierAbsoluteMax) {
    double currentPct = current / tierAbsoluteMax;
    double maxPct = max / tierAbsoluteMax;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Text("$current / $max", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: maxPct.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: currentPct.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF39FF14),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}