import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';

class CasPeryaView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final VoidCallback onBack;

  const CasPeryaView({super.key, required this.userData, required this.onStateChange, required this.onBack});

  @override
  State<CasPeryaView> createState() => _CasPeryaViewState();
}

class _CasPeryaViewState extends State<CasPeryaView> {
  late String userId;
  late int cleanCash;
  late int dirtyCash;
  late int casinoTokens;

  String? selectedColor;
  int currentBet = 0;

  bool isRolling = false;
  List<String> diceResults = ['?', '?', '?'];
  String lastResultText = "SELECT A COLOR & PLACE YOUR BET";
  Color lastResultColor = Colors.grey;

  // Session History Tracker (Will hold max 10 entries)
  List<Map<String, dynamic>> sessionHistory = [];

  final Map<String, Color> peryaColors = {
    'RED': Colors.redAccent, 'BLUE': Colors.blueAccent, 'YELLOW': Colors.yellowAccent,
    'GREEN': Colors.greenAccent, 'PINK': Colors.pinkAccent, 'WHITE': Colors.white,
  };

  final List<int> cashChips = [100, 1000, 10000, 100000, 500000, 1000000, 5000000, 10000000, 20000000];

  Timer? _rollTimer;
  final Random _random = Random();

  int _parseSafeInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    userId = widget.userData['user_id']?.toString() ?? "0";
    _syncState();
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    super.dispose();
  }

  void _syncState() {
    cleanCash = _parseSafeInt(widget.userData['clean_cash']);
    dirtyCash = _parseSafeInt(widget.userData['dirty_cash']);
    casinoTokens = _parseSafeInt(widget.userData['casino_tokens']);
  }

  String _formatCash(num amount) {
    if (amount >= 1000000000) return '\$${(amount / 1000000000).toStringAsFixed(1)}b';
    if (amount >= 1000000) return '\$${(amount / 1000000).toStringAsFixed(1)}m';
    if (amount >= 1000) return '\$${(amount / 1000).toStringAsFixed(1)}k';
    return '\$${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  void _showTutorial() {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF39FF14))),
          title: const Row(children: [Icon(Icons.help_outline, color: Color(0xFF39FF14)), SizedBox(width: 8), Text("HOW TO PLAY", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))]),
          content: const Text(
            "1. Choose one of the 6 colors.\n"
                "2. Place your cash bet. (Dirty Cash is used first).\n"
                "3. Every roll costs exactly 1 Casino Token.\n\n"
                "Payouts (Paid in Clean Cash):\n"
                "• 1 Match = 2x your bet\n"
                "• 2 Matches = 3x your bet\n"
                "• 3 Matches = 4x your bet",
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("GOT IT", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.bold)))],
        )
    );
  }

  void _addBet(int amount) {
    setState(() {
      currentBet += amount;
      if (currentBet > (dirtyCash + cleanCash)) {
        currentBet = dirtyCash + cleanCash;
      }
    });
  }

  Future<void> _rollDice() async {
    if (selectedColor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a color first!"), backgroundColor: Colors.redAccent));
      return;
    }
    if (currentBet <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Place a bet first!"), backgroundColor: Colors.redAccent));
      return;
    }
    if (casinoTokens < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Out of Tokens!"), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() {
      isRolling = true;
      lastResultText = "TUMBLING...";
      lastResultColor = Colors.cyanAccent;
    });

    List<String> colorNames = peryaColors.keys.toList();
    _rollTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      setState(() {
        diceResults = [
          colorNames[_random.nextInt(colorNames.length)],
          colorNames[_random.nextInt(colorNames.length)],
          colorNames[_random.nextInt(colorNames.length)],
        ];
      });
    });

    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:3000/casino/perya/roll'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'betAmount': currentBet, 'chosenColor': selectedColor}),
      );

      final data = jsonDecode(response.body);
      await Future.delayed(const Duration(milliseconds: 1500));

      _rollTimer?.cancel();

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            isRolling = false;
            diceResults = List<String>.from(data['dice']);

            widget.userData['clean_cash'] = data['updatedBalances']['clean_cash'];
            widget.userData['dirty_cash'] = data['updatedBalances']['dirty_cash'];
            widget.userData['casino_tokens'] = data['updatedBalances']['casino_tokens'];
            _syncState();
            widget.onStateChange(widget.userData);

            int payout = data['payout'];
            if (payout > 0) {
              lastResultText = "YOU WON ${_formatCash(payout)} CLEAN!";
              lastResultColor = const Color(0xFF39FF14);
            } else {
              lastResultText = "NO MATCH. BET LOST.";
              lastResultColor = Colors.redAccent;
            }

            // 🚨 LOG HISTORY (Cap at 10 to keep memory light)
            sessionHistory.insert(0, {
              'betAmount': currentBet,
              'betColor': selectedColor,
              'dice': diceResults,
              'payout': payout
            });
            if (sessionHistory.length > 10) sessionHistory.removeLast();
          });
        }
      } else {
        _rollTimer?.cancel();
        setState(() { isRolling = false; lastResultText = data['error'] ?? "ERROR OCCURRED"; lastResultColor = Colors.redAccent; });
      }
    } catch (e) {
      _rollTimer?.cancel();
      setState(() { isRolling = false; lastResultText = "NETWORK ERROR"; lastResultColor = Colors.redAccent; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black, elevation: 0, titleSpacing: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF39FF14)), onPressed: widget.onBack),
        title: const Text("PERYA COLOR GAME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                _buildWalletBadge("TOKENS", "$casinoTokens", Colors.cyanAccent),
                IconButton(icon: const Icon(Icons.help_outline, color: Colors.white54, size: 20), onPressed: _showTutorial),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- THE BOARD (Shrunk Height) ---
                  Container(
                    height: 90, width: double.infinity,
                    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(lastResultText, style: TextStyle(color: lastResultColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: diceResults.map((result) {
                            Color boxColor = result == '?' ? const Color(0xFF252525) : peryaColors[result]!;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 80),
                              width: 45, height: 45, // Smaller dice
                              decoration: BoxDecoration(
                                color: boxColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white54, width: 2),
                                boxShadow: result != '?' ? [BoxShadow(color: boxColor.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)] : [],
                              ),
                              child: Center(child: Text(result == '?' ? '?' : '', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // --- COLOR SELECTOR (Tighter Grid) ---
                  GridView.builder(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.2), // Wider boxes, less height
                    itemCount: peryaColors.length,
                    itemBuilder: (context, index) {
                      String colorName = peryaColors.keys.elementAt(index);
                      Color c = peryaColors.values.elementAt(index);
                      bool isSelected = selectedColor == colorName;

                      return GestureDetector(
                        onTap: isRolling ? null : () => setState(() => selectedColor = colorName),
                        child: Container(
                          decoration: BoxDecoration(color: c.withOpacity(isSelected ? 1.0 : 0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: isSelected ? Colors.white : c, width: isSelected ? 2 : 1)),
                          child: Center(child: Text(colorName, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1))),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // --- TOTAL BET (Compact) ---
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFF121212), border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.5)), borderRadius: BorderRadius.circular(6)),
                    child: Center(
                      child: Text("BET: ${_formatCash(currentBet)}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // --- CHIPS (Tighter Wrap) ---
                  Wrap(
                    spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
                    children: [
                      ...cashChips.map((amount) => _buildChip(amount)),
                      _buildActionChip(
                          "CLR",
                          Colors.redAccent,
                              () => setState(() => currentBet = 0),
                          isEnabled: currentBet > 0 // Only active if a bet is placed
                      ),
                      _buildActionChip(
                          "MAX",
                          Colors.amberAccent,
                              () => setState(() => currentBet = dirtyCash + cleanCash),
                          isEnabled: ((dirtyCash + cleanCash) - currentBet) > 0 // Only active if they have un-bet cash left
                      ),
                    ],
                  ),

                  // 🚨 NEW: HORIZONTAL TICKER HISTORY
                  if (sessionHistory.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text("RECENT PLAYS", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 100, // Fixed height keeps it compact
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal, // Draggable left to right!
                        itemCount: sessionHistory.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return SizedBox(
                            width: 65, // Fixed width for each column
                            child: _buildHistoryTickerCard(sessionHistory[index]),
                          );
                        },
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),

          // --- ROLL BUTTON (Fixed to Bottom, Shrunk) ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            color: const Color(0xFF1A1A1A), // Nice anchored footer
            child: SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isRolling ? Colors.grey[800] : const Color(0xFF39FF14), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                onPressed: isRolling ? null : _rollDice,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isRolling ? "TUMBLING..." : "ROLL DICE", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    if (!isRolling) const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Text("[-1 TOKEN]", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MICRO-WIDGETS ---
  Widget _buildWalletBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 6, fontWeight: FontWeight.bold, letterSpacing: 1)),
          Text(value, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildChip(int amount) {
    // Calculate what they have left to bet
    int remainingCash = (dirtyCash + cleanCash) - currentBet;
    bool canAfford = amount <= remainingCash;
    bool isDisabled = isRolling || !canAfford;

    String label = _formatCash(amount).replaceAll('\$', '');

    return InkWell(
      onTap: isDisabled ? null : () => _addBet(amount),
      child: Opacity(
        opacity: canAfford ? 1.0 : 0.3, // Dims the chip if they can't afford it
        child: Container(
          width: 45, height: 30,
          decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: canAfford ? Colors.white24 : Colors.transparent)
          ),
          child: Center(
              child: Text(
                  "+$label",
                  style: TextStyle(
                      color: canAfford ? Colors.white : Colors.grey,
                      fontSize: 9,
                      fontWeight: FontWeight.bold
                  )
              )
          ),
        ),
      ),
    );
  }

  // Added the optional 'isEnabled' parameter to handle CLR and MAX states
  Widget _buildActionChip(String label, Color color, VoidCallback onTap, {bool isEnabled = true}) {
    bool isDisabled = isRolling || !isEnabled;
    return InkWell(
      onTap: isDisabled ? null : onTap,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.3, // Dims the button if disabled
        child: Container(
          width: 45, height: 30,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withOpacity(0.5))
          ),
          child: Center(child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }

  // 🚨 NEW: Horizontal Ticker Card
  Widget _buildHistoryTickerCard(Map<String, dynamic> history) {
    bool isWin = history['payout'] > 0;
    Color borderColor = isWin ? const Color(0xFF39FF14) : Colors.white12;
    Color payoutColor = isWin ? const Color(0xFF39FF14) : Colors.grey;
    List<String> dice = history['dice'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(6)
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Bet Amount
          Text(_formatCash(history['betAmount']), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white12, height: 4),

          // Bet Color (Circle)
          _buildMiniColorBox(history['betColor'], isBet: true),
          const SizedBox(height: 2),

          // The 3 Dice Results (Stacked in 3 Rows)
          ...dice.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _buildMiniColorBox(c, isBet: false),
          )),

          const Spacer(),
          // Payout Result
          Text(isWin ? "WIN" : "LOSS", style: TextStyle(color: payoutColor, fontSize: 8, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildMiniColorBox(String colorName, {required bool isBet}) {
    Color c = peryaColors[colorName]!;
    return Container(
      width: 12, height: 12,
      decoration: BoxDecoration(
          color: c,
          shape: isBet ? BoxShape.circle : BoxShape.rectangle, // Circle = Your Bet, Square = Dice
          border: Border.all(color: Colors.white54, width: 1)
      ),
    );
  }
}