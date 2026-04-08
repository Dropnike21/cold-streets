import 'package:flutter/material.dart';

class StreetsView extends StatelessWidget {
  const StreetsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10.0),
      children: [
        ExpansionTile(
          initiallyExpanded: true,
          title: const Text("SEARCH & SCAVENGE (SPD)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
          children: [
            _buildCrimeCard(
                context,
                title: "CHECK PAYPHONES",
                payout: "\$1 - \$3",
                costs: "3 E",
                reqTool: "NONE",
                assignedNpc: null,
                successText: "You check the coin returns and gather enough loose change to buy a coffee.",
                critText: "You pry open a jammed coin slot and find a fat wad of cash and extra loot.",
                escapeText: "A homeless guy yells at you for taking his spot. You walk away empty-handed.",
                hospText: "You reach into a dark slot and cut your hand deeply on hidden glass.",
                jailText: "A beat cop cites you for vandalism as you try to pry the phone apart."
            ),
            _buildCrimeCard(
                context,
                title: "SCAVENGE DUMPSTER",
                payout: "\$2 - \$8",
                costs: "5 E",
                reqTool: "NONE",
                assignedNpc: "SLY",
                successText: "You dig through the filth and find a few discarded valuables to pawn.",
                critText: "Beneath the trash, you find a dropped wallet and some salvageable loot.",
                escapeText: "Rats swarm out of the bags. You stumble backward and run off in disgust.",
                hospText: "You slip on some mystery sludge and fall headfirst into a pile of rusted metal.",
                jailText: "The restaurant owner catches you trespassing and locks you in the alley."
            ),
            _buildCrimeCard(
                context,
                title: "LOOT ABANDONED CAR",
                payout: "\$15 - \$35",
                costs: "15 E",
                reqTool: "CROWBAR",
                assignedNpc: null,
                successText: "You pop the lock and swipe a forgotten stereo.",
                critText: "You find a hidden stash compartment under the passenger seat!",
                escapeText: "The car alarm somehow triggers. You sprint down the block.",
                hospText: "You shatter the window but severely slice your arm in the process.",
                jailText: "A patrol cruiser turns the corner mid-break-in. You're cuffed."
            ),
          ],
        ),
        ExpansionTile(
          title: const Text("PICKPOCKETING (DEX)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
          children: [
            _buildCrimeCard(context, title: "THE OLD MAN", payout: "\$10 - \$25", costs: "2 N | 8 E", reqTool: "NONE",
                successText: "You bump into him and slide his wallet out cleanly.",
                critText: "You lift his wallet and slip his gold watch right off his wrist.",
                escapeText: "He turns around too quickly. You abort and walk away.",
                hospText: "He hits you with his cane. Hard. Right in the jaw.",
                jailText: "An undercover cop was watching the whole thing. Busted."
            ),
          ],
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildCrimeCard(
      BuildContext context, {
        required String title,
        required String payout,
        required String costs,
        required String reqTool,
        String? assignedNpc,
        String successText = "Job completed successfully.",
        String critText = "Flawless execution! Extra loot acquired.",
        String escapeText = "Things went south. You ran away.",
        String hospText = "You got seriously injured on the job.",
        String jailText = "You were caught and arrested."
      }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          border: Border(left: BorderSide(color: Color(0xFF39FF14), width: 3)),
          borderRadius: BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Text("COST: $costs", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 10)),
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
                  Text("PAYOUT: $payout", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("TOOL REQ: $reqTool", style: TextStyle(color: reqTool == "NONE" ? Colors.white24 : Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
              Row(
                children: [
                  if (assignedNpc == null) ...[
                    SizedBox(
                      height: 28,
                      child: OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          side: const BorderSide(color: Color(0xFF333333)),
                        ),
                        child: const Icon(Icons.person_add_alt_1, size: 14, color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      child: ElevatedButton(
                        onPressed: () => _showResultModal(context, title, successText, critText, escapeText, hospText, jailText),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF39FF14).withOpacity(0.1),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: const BorderSide(color: Color(0xFF39FF14)),
                        ),
                        child: const Text("EXECUTE", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else ...[
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person, size: 12, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(assignedNpc, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF39FF14)),
                          )
                        ],
                      ),
                    )
                  ],
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  void _showResultModal(
      BuildContext context,
      String title,
      String successText,
      String critText,
      String escapeText,
      String hospText,
      String jailText
      ) {
    final int roll = DateTime.now().millisecond % 5;
    String outcomeTitle;
    Color outcomeColor;
    String narrative;
    List<String> results;

    switch (roll) {
      case 0:
        outcomeTitle = "CRITICAL SUCCESS";
        outcomeColor = const Color(0xFF39FF14);
        narrative = critText;
        results = ["+ \$25 Dirty Cash", "+ 1x Dirty Coin", "- Energy/Nerve Cost"];
        break;
      case 1:
        outcomeTitle = "SUCCESS";
        outcomeColor = const Color(0xFF39FF14);
        narrative = successText;
        results = ["+ \$5 Dirty Cash", "- Energy/Nerve Cost"];
        break;
      case 2:
        outcomeTitle = "ESCAPED (FAILURE)";
        outcomeColor = Colors.yellowAccent;
        narrative = escapeText;
        results = ["- 10% HP", "- Energy/Nerve Cost", "+ 0 Heat"];
        break;
      case 3:
        outcomeTitle = "HOSPITALIZED (FAILURE)";
        outcomeColor = Colors.orangeAccent;
        narrative = hospText;
        results = ["HP dropped to 1", "Locked in Hospital", "- Energy/Nerve Cost"];
        break;
      default:
        outcomeTitle = "JAILED (FAILURE)";
        outcomeColor = Colors.redAccent;
        narrative = jailText;
        results = ["Max Heat Gained", "Locked in Jail (15m)", "- Energy/Nerve Cost"];
        break;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF121212),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: outcomeColor, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  outcomeTitle,
                  style: TextStyle(color: outcomeColor, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF333333)),
                const SizedBox(height: 12),
                Text(
                  "\"$narrative\"",
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF333333)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("RESULTS:", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...results.map((res) => Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(res, style: TextStyle(color: outcomeColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: outcomeColor.withOpacity(0.1),
                      side: BorderSide(color: outcomeColor),
                    ),
                    child: Text(
                        "ACKNOWLEDGE",
                        style: TextStyle(color: outcomeColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}