import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';

class CasSlotsView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final VoidCallback onBack;

  const CasSlotsView({super.key, required this.userData, required this.onStateChange, required this.onBack});

  @override
  State<CasSlotsView> createState() => _CasSlotsViewState();
}

class _CasSlotsViewState extends State<CasSlotsView> {
  late String userId;
  late int cleanCash;
  late int dirtyCash;
  late int casinoTokens;

  int currentBet = 0;
  int currentJackpot = 0;

  bool isRolling = false;
  List<String> reelResults = ['DIAMOND', 'CROWN', 'DIAMOND', 'CROWN'];
  String lastResultText = "PULL THE LEVER";
  Color lastResultColor = Colors.grey;

  List<Map<String, dynamic>> sessionHistory = [];

  final Map<String, String> slotSymbols = {
    'CHERRY': '🍒', 'LEMON': '🍋', 'GRAPE': '🍇',
    'DIAMOND': '💎', 'CROWN': '👑', 'SKULL': '💀',
  };

  final List<int> cashChips = [100, 1000, 10000, 100000, 500000, 1000000, 5000000, 10000000, 20000000];

  Timer? _spinTimer;
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
    _fetchJackpot();
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
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

  Future<void> _fetchJackpot() async {
    try {
      final res = await http.get(Uri.parse('http://10.0.2.2:3000/casino/slots/jackpot'));
      if (res.statusCode == 200) {
        if (mounted) setState(() => currentJackpot = jsonDecode(res.body)['jackpot']);
      }
    } catch (e) {
      debugPrint("Jackpot fetch error: $e");
    }
  }

  void _showTutorial() {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF39FF14))),
          title: const Row(children: [Icon(Icons.help_outline, color: Color(0xFF39FF14)), SizedBox(width: 8), Text("HOW TO PLAY", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))]),
          content: const SingleChildScrollView(
            child: Text(
              "Welcome to the 4-Reel Syndicate Slots!\n\n"
                  "Payout Rules (Commons):\n"
                  "• 1 Pair = 0.8x\n" // <-- Hidden tax removed from text
                  "• 2 Pairs = 1.2x\n"
                  "• 3 of a Kind = 1.8x\n"
                  "• 4 of a Kind = 2.0x\n\n"
                  "Premium Symbols:\n"
                  "💎 3 Diamonds = 3x\n"
                  "💎 4 Diamonds = 4x\n"
                  "👑 4 Crowns = PROGRESSIVE JACKPOT!\n\n"
                  "💀 Skulls act as dead spaces. 10% of every lost bet feeds the global Jackpot.",
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
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

  Future<void> _spinReels() async {
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
      lastResultText = "SPINNING...";
      lastResultColor = Colors.cyanAccent;
    });

    List<String> keys = slotSymbols.keys.toList();
    _spinTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      setState(() {
        reelResults = [
          keys[_random.nextInt(keys.length)],
          keys[_random.nextInt(keys.length)],
          keys[_random.nextInt(keys.length)],
          keys[_random.nextInt(keys.length)],
        ];
      });
    });

    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:3000/casino/slots/spin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'betAmount': currentBet}),
      );

      final data = jsonDecode(response.body);
      await Future.delayed(const Duration(milliseconds: 1500));

      _spinTimer?.cancel();

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            isRolling = false;
            reelResults = List<String>.from(data['reels']);
            currentJackpot = data['currentJackpot'];

            widget.userData['clean_cash'] = data['updatedBalances']['clean_cash'];
            widget.userData['dirty_cash'] = data['updatedBalances']['dirty_cash'];
            widget.userData['casino_tokens'] = data['updatedBalances']['casino_tokens'];
            _syncState();
            widget.onStateChange(widget.userData);

            int payout = data['payout'];
            bool isJackpot = data['isJackpot'] ?? false;

            if (isJackpot) {
              lastResultText = "💰 MEGA JACKPOT! +${_formatCash(payout)} 💰";
              lastResultColor = Colors.amberAccent;
            } else if (payout > currentBet) {
              lastResultText = "BIG WIN! +${_formatCash(payout)} CLEAN!";
              lastResultColor = const Color(0xFF39FF14);
            } else if (payout > 0) {
              // 🚨 The Loss-Disguised-As-Win Visual!
              lastResultText = "PARTIAL WIN: ${_formatCash(payout)}";
              lastResultColor = Colors.cyanAccent;
            } else {
              lastResultText = "DEAD SPIN.";
              lastResultColor = Colors.redAccent;
            }

            sessionHistory.insert(0, {
              'betAmount': currentBet,
              'reels': reelResults,
              'payout': payout
            });
            if (sessionHistory.length > 10) sessionHistory.removeLast();
          });
        }
      } else {
        _spinTimer?.cancel();
        setState(() { isRolling = false; lastResultText = data['error'] ?? "ERROR OCCURRED"; lastResultColor = Colors.redAccent; });
      }
    } catch (e) {
      _spinTimer?.cancel();
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
        title: const Text("SYNDICATE SLOTS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13)),
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- THE GLOBAL JACKPOT ---
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.amberAccent.withOpacity(0.1), Colors.black], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amberAccent.withOpacity(0.5))
                    ),
                    child: Column(
                      children: [
                        const Text("PROGRESSIVE JACKPOT", style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
                        const SizedBox(height: 4),
                        Text(currentJackpot == 0 ? "LOADING..." : "\$${currentJackpot.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}",
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.amberAccent, blurRadius: 10)])
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- THE 4 SLOT REELS ---
                  Container(
                    height: 110, width: double.infinity,
                    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(lastResultText, style: TextStyle(color: lastResultColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: reelResults.map((result) {
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              width: 55, height: 55,
                              decoration: BoxDecoration(
                                color: const Color(0xFF252525), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white38, width: 2),
                                boxShadow: isRolling ? [const BoxShadow(color: Colors.cyanAccent, blurRadius: 10, spreadRadius: 1)] : [],
                              ),
                              child: Center(child: Text(slotSymbols[result] ?? '?', style: const TextStyle(fontSize: 28))),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- TOTAL BET ---
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFF121212), border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.5)), borderRadius: BorderRadius.circular(6)),
                    child: Center(
                      child: Text("BET: ${_formatCash(currentBet)}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // --- CHIPS ---
                  Wrap(
                    spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
                    children: [
                      ...cashChips.map((amount) => _buildChip(amount)),
                      _buildActionChip("CLR", Colors.redAccent, () => setState(() => currentBet = 0), isEnabled: currentBet > 0),
                      _buildActionChip("MAX", Colors.amberAccent, () => setState(() => currentBet = dirtyCash + cleanCash), isEnabled: ((dirtyCash + cleanCash) - currentBet) > 0),
                    ],
                  ),

                  // --- HORIZONTAL TICKER HISTORY ---
                  if (sessionHistory.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Align(alignment: Alignment.centerLeft, child: Text("RECENT SPINS", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: sessionHistory.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return SizedBox(width: 85, child: _buildHistoryTickerCard(sessionHistory[index]));
                        },
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),

          // --- SPIN BUTTON ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            color: const Color(0xFF1A1A1A),
            child: SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isRolling ? Colors.grey[800] : const Color(0xFF39FF14), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                onPressed: isRolling ? null : _spinReels,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isRolling ? "SPINNING..." : "PULL LEVER", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
    int remainingCash = (dirtyCash + cleanCash) - currentBet;
    bool canAfford = amount <= remainingCash;
    bool isDisabled = isRolling || !canAfford;
    String label = _formatCash(amount).replaceAll('\$', '');

    return InkWell(
      onTap: isDisabled ? null : () => _addBet(amount),
      child: Opacity(
        opacity: canAfford ? 1.0 : 0.3,
        child: Container(
          width: 45, height: 30,
          decoration: BoxDecoration(color: const Color(0xFF252525), borderRadius: BorderRadius.circular(15), border: Border.all(color: canAfford ? Colors.white24 : Colors.transparent)),
          child: Center(child: Text("+$label", style: TextStyle(color: canAfford ? Colors.white : Colors.grey, fontSize: 9, fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }

  Widget _buildActionChip(String label, Color color, VoidCallback onTap, {bool isEnabled = true}) {
    bool isDisabled = isRolling || !isEnabled;
    return InkWell(
      onTap: isDisabled ? null : onTap,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.3,
        child: Container(
          width: 45, height: 30,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.5))),
          child: Center(child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }

  Widget _buildHistoryTickerCard(Map<String, dynamic> history) {
    int payout = history['payout'];
    int bet = history['betAmount'];

    bool isWin = payout > bet;
    bool isPartial = payout > 0 && payout < bet;

    Color borderColor = isWin ? const Color(0xFF39FF14) : (isPartial ? Colors.cyanAccent : Colors.white12);
    Color payoutColor = isWin ? const Color(0xFF39FF14) : (isPartial ? Colors.cyanAccent : Colors.grey);
    List<String> reels = history['reels'];

    String statusText = "LOSS";
    if (isWin) statusText = "+${_formatCash(payout)}";
    if (isPartial) statusText = "0.8x";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_formatCash(bet), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white12, height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: reels.map((r) => Text(slotSymbols[r] ?? '?', style: const TextStyle(fontSize: 10))).toList(),
          ),
          const Spacer(),
          Text(statusText, style: TextStyle(color: payoutColor, fontSize: 8, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}