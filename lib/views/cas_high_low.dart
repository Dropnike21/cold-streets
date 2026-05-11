import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

import '../api_config.dart';

class CasHighLowView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final VoidCallback onBack;

  const CasHighLowView({super.key, required this.userData, required this.onStateChange, required this.onBack});

  @override
  State<CasHighLowView> createState() => _CasHighLowViewState();
}

class _CasHighLowViewState extends State<CasHighLowView> {
  late String userId;
  late int cleanCash;
  late int dirtyCash;
  late int casinoTokens;

  bool isActiveGame = false;
  bool isRoundWon = false; // 🚨 NEW: Controls the Continue/Cashout phase
  bool isLoading = true;
  bool isDealing = false;

  // Game State
  int currentBet = 0;
  double currentMultiplier = 1.0;
  int currentStreak = 0;
  Map<String, dynamic>? currentCard; // Your Draw (Face down when null)
  Map<String, dynamic>? previousCard; // Dealer's Show

  String gameMessage = "PLACE YOUR BET";
  Color messageColor = Colors.white;

  final List<int> cashChips = [100, 1000, 10000, 100000, 500000, 1000000, 5000000, 10000000];

  @override
  void initState() {
    super.initState();
    userId = widget.userData['user_id']?.toString() ?? "0";
    _syncState();
    _checkActiveSession();
  }

  void _syncState() {
    cleanCash = _parseSafeInt(widget.userData['clean_cash']);
    dirtyCash = _parseSafeInt(widget.userData['dirty_cash']);
    casinoTokens = _parseSafeInt(widget.userData['casino_tokens']);
  }

  int _parseSafeInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _formatCash(num amount) {
    if (amount >= 1000000000) return '\$${(amount / 1000000000).toStringAsFixed(1)}b';
    if (amount >= 1000000) return '\$${(amount / 1000000).toStringAsFixed(1)}m';
    if (amount >= 1000) return '\$${(amount / 1000).toStringAsFixed(1)}k';
    return '\$${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  // --- TUTORIAL ---
  void _showTutorial() {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF39FF14))),
          title: const Row(children: [Icon(Icons.help_outline, color: Color(0xFF39FF14)), SizedBox(width: 8), Text("HOW TO PLAY", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))]),
          content: const SingleChildScrollView(
            child: Text(
              "Welcome to the Classic Streak High-Low!\n\n"
                  "The Rules:\n"
                  "1. Place your bet (-1 Token).\n"
                  "2. The Dealer will show a card.\n"
                  "3. Guess if your face-down card will be Higher, Lower, or the Same.\n\n"
                  "Multipliers:\n"
                  "• High/Low = +0.3x Multiplier\n"
                  "• DRAW = +5.0x Multiplier!\n\n"
                  "The Streak:\n"
                  "If you guess right, you can Cash Out your winnings, OR let it ride to build your streak. Pushing your streak unlocks new Tier Colors, but if you guess wrong once, you lose it all!",
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("GOT IT", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.bold)))],
        )
    );
  }

  // --- API CALLS ---
  Future<void> _checkActiveSession() async {
    try {
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/casino/highlow/session/$userId'));
      final data = jsonDecode(res.body);
      if (data['active'] == true) {
        if (mounted) {
          setState(() {
            isActiveGame = true;
            isRoundWon = false; // Always load into a guessing state
            currentBet = int.parse(data['session']['bet_amount']);
            currentMultiplier = double.parse(data['session']['current_multiplier']);
            currentStreak = data['session']['current_streak'];

            // Set the dealer's card, make the player's card face down
            previousCard = {'value': data['session']['current_card_value'], 'suit': data['session']['current_card_suit']};
            currentCard = null;

            gameMessage = "WILL YOUR CARD BE HIGHER OR LOWER?";
            messageColor = Colors.cyanAccent;
          });
        }
      }
    } catch (e) {
      debugPrint("Error checking session: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _startGame() async {
    if (currentBet <= 0) return;
    setState(() => isDealing = true);
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/casino/highlow/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'betAmount': currentBet}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            isActiveGame = true;
            isRoundWon = false;
            currentMultiplier = 1.0;
            currentStreak = 0;

            // Setup the table
            previousCard = data['card']; // Dealer gets the card
            currentCard = null; // Player gets face down

            gameMessage = "HIGHER, LOWER, OR DRAW?";
            messageColor = Colors.cyanAccent;

            widget.userData['clean_cash'] = data['updatedBalances']['clean_cash'];
            widget.userData['dirty_cash'] = data['updatedBalances']['dirty_cash'];
            widget.userData['casino_tokens'] = data['updatedBalances']['casino_tokens'];
            _syncState();
            widget.onStateChange(widget.userData);
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'])));
      }
    } finally {
      if (mounted) setState(() => isDealing = false);
    }
  }

  Future<void> _makeGuess(String guess) async {
    setState(() {
      isDealing = true;
      gameMessage = "FLIPPING...";
      messageColor = Colors.white;
    });

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/casino/highlow/guess'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'guess': guess}),
      );
      final data = jsonDecode(res.body);

      // 1. Suspense Delay: Wait a moment before flipping
      await Future.delayed(const Duration(milliseconds: 400));

      if (mounted) {
        setState(() {
          currentCard = data['nextCard']; // 👈 This triggers the 3D Animation!
        });

        // 2. Animation Delay: Wait for the flip to finish before showing the result
        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted) {
          if (data['status'] == 'WIN') {
            setState(() {
              currentMultiplier = double.parse(data['newMultiplier'].toString());
              currentStreak = data['newStreak'];
              isRoundWon = true; // 👈 Triggers the Continue/Cashout buttons!
              gameMessage = guess == 'SAME' ? "EPIC DRAW! (+5.0x MULTIPLIER!)" : "CORRECT! KEEP GOING OR CASH OUT?";
              messageColor = guess == 'SAME' ? Colors.amberAccent : const Color(0xFF39FF14);
            });
          } else {
            setState(() {
              isActiveGame = false;
              isRoundWon = false;
              gameMessage = "WRONG GUESS. YOU LOST ${_formatCash(currentBet)}";
              messageColor = Colors.redAccent;
              currentBet = 0;
            });
          }
        }
      }
    } finally {
      if (mounted) setState(() => isDealing = false);
    }
  }

  // 🚨 NEW: The Continue Logic
  void _continueRound() {
    setState(() {
      previousCard = currentCard; // Shift the card you just won with to the Dealer
      currentCard = null; // Deal yourself a new Face Down card
      isRoundWon = false; // Bring back the guessing buttons
      gameMessage = "HIGHER, LOWER, OR DRAW?";
      messageColor = Colors.cyanAccent;
    });
  }

  Future<void> _cashOut() async {
    setState(() => isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/casino/highlow/cashout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      );
      final data = jsonDecode(res.body);

      if (mounted) {
        setState(() {
          isActiveGame = false;
          isRoundWon = false;
          gameMessage = "CASHED OUT FOR +${_formatCash(data['payout'])} CLEAN!";
          messageColor = Colors.amberAccent;
          currentBet = 0;

          widget.userData['clean_cash'] = data['updatedBalances']['clean_cash'];
          widget.userData['dirty_cash'] = data['updatedBalances']['dirty_cash'];
          widget.userData['casino_tokens'] = data['updatedBalances']['casino_tokens'];
          _syncState();
          widget.onStateChange(widget.userData);
        });
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- UI BUILDERS ---
  String _getCardString(int value) {
    if (value == 11) return "J";
    if (value == 12) return "Q";
    if (value == 13) return "K";
    if (value == 14) return "A";
    return value.toString();
  }

  Widget _buildCard(Map<String, dynamic>? card, {Key? key}) {
    // Face Down Card
    if (card == null) {
      return Container(
          key: key,
          width: 80, height: 120,
          decoration: BoxDecoration(color: const Color(0xFF0F0F0F), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF39FF14), width: 2)),
          child: const Center(child: Icon(Icons.casino, color: Color(0xFF39FF14), size: 32))
      );
    }

    // Face Up Card
    bool isRed = card['suit'] == 'HEARTS' || card['suit'] == 'DIAMONDS';
    String suitIcon = '♠';
    if (card['suit'] == 'HEARTS') suitIcon = '♥';
    if (card['suit'] == 'DIAMONDS') suitIcon = '♦';
    if (card['suit'] == 'CLUBS') suitIcon = '♣';

    return Container(
      key: key,
      width: 80, height: 120,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24, width: 2), boxShadow: [BoxShadow(color: (isRed ? Colors.red : Colors.black).withOpacity(0.5), blurRadius: 10)]),
      child: Stack(
        children: [
          Positioned(top: 8, left: 8, child: Text(_getCardString(card['value']), style: TextStyle(color: isRed ? Colors.red : Colors.black, fontSize: 18, fontWeight: FontWeight.bold))),
          Center(child: Text(suitIcon, style: TextStyle(color: isRed ? Colors.red : Colors.black, fontSize: 40))),
          Positioned(bottom: 8, right: 8, child: Text(_getCardString(card['value']), style: TextStyle(color: isRed ? Colors.red : Colors.black, fontSize: 18, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // Slower, smoother 3D Flip
  Widget _buildFlipTransition(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, childWidget) {
        final angle = (1.0 - animation.value) * pi;
        return Transform(
          transform: Matrix4.rotationY(angle),
          alignment: Alignment.center,
          child: angle < (pi / 2)
              ? childWidget
              : Container( // Temporary back of card during spin
            width: 80, height: 120,
            decoration: BoxDecoration(color: const Color(0xFF0F0F0F), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF39FF14), width: 2)),
            child: const Center(child: Icon(Icons.casino, color: Color(0xFF39FF14), size: 32)),
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildStreakBar() {
    int tier = (currentStreak == 0) ? 0 : (currentStreak - 1) ~/ 10;
    int progress = (currentStreak == 0) ? 0 : ((currentStreak - 1) % 10) + 1;

    List<Color> tierColors = [const Color(0xFF39FF14), Colors.orangeAccent, Colors.pinkAccent, Colors.purpleAccent, Colors.red];
    Color activeColor = tierColors[tier % tierColors.length];

    return Column(
      children: [
        Text("STREAK: $currentStreak", style: TextStyle(color: activeColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(10, (index) {
            bool isFilled = index < progress;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 25, height: 8,
              decoration: BoxDecoration(
                color: isFilled ? activeColor : const Color(0xFF252525),
                borderRadius: BorderRadius.circular(4),
                boxShadow: isFilled ? [BoxShadow(color: activeColor.withOpacity(0.5), blurRadius: 4)] : [],
              ),
            );
          }),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator(color: Color(0xFF39FF14))));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black, elevation: 0, titleSpacing: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF39FF14)), onPressed: widget.onBack),
        title: const Text("HIGH-LOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13)),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Game Status
                  Text(gameMessage, textAlign: TextAlign.center, style: TextStyle(color: messageColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  const SizedBox(height: 24),

                  // The Streak Bar
                  _buildStreakBar(),
                  const SizedBox(height: 32),

                  // The Cards with Labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // DEALER'S SHOW CARD
                      Column(
                        children: [
                          const Text("DEALER'S SHOW", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 8),
                          Opacity(
                              opacity: previousCard == null ? 0.3 : 1.0,
                              child: _buildCard(previousCard)
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 50.0),
                        child: Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 20),
                      ),
                      const SizedBox(width: 16),

                      // YOUR DRAW (With 3D Flip Animation!)
                      Column(
                        children: [
                          const Text("YOUR DRAW", style: TextStyle(color: Color(0xFF39FF14), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 800), // 👈 Slower, smoother animation!
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: _buildFlipTransition,
                            child: _buildCard(currentCard, key: ValueKey("${currentCard?['value']}_${currentCard?['suit']}")),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // --- PHASE 1: GUESSING ---
                  if (isActiveGame && !isRoundWon) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // HIGH
                        Expanded(
                          child: SizedBox(
                            height: 60,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14).withOpacity(0.1), side: const BorderSide(color: Color(0xFF39FF14))),
                              onPressed: isDealing ? null : () => _makeGuess('HIGH'),
                              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.arrow_upward, color: Color(0xFF39FF14), size: 18), SizedBox(height: 2), Text("HIGH", style: TextStyle(color: Color(0xFF39FF14), fontWeight: FontWeight.bold, fontSize: 10))]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // DRAW (+5.0x)
                        Expanded(
                          child: SizedBox(
                            height: 60,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent.withOpacity(0.1), side: const BorderSide(color: Colors.amberAccent)),
                              onPressed: isDealing ? null : () => _makeGuess('SAME'),
                              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text("DRAW", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w900, fontSize: 12)), Text("+5.0x", style: TextStyle(color: Colors.amberAccent, fontSize: 9))]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // LOW
                        Expanded(
                          child: SizedBox(
                            height: 60,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1), side: const BorderSide(color: Colors.redAccent)),
                              onPressed: isDealing ? null : () => _makeGuess('LOW'),
                              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.arrow_downward, color: Colors.redAccent, size: 18), SizedBox(height: 2), Text("LOW", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10))]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // --- PHASE 2: CONTINUE OR CASHOUT ---
                  if (isActiveGame && isRoundWon) ...[
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14), foregroundColor: Colors.black),
                        onPressed: isDealing ? null : _continueRound,
                        child: const Text("CONTINUE STREAK", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black),
                        onPressed: isDealing ? null : _cashOut,
                        child: Text("CASH OUT ${_formatCash(currentBet * currentMultiplier)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
                      ),
                    ),
                  ],

                  // --- PRE-GAME BETTING CONTROLS ---
                  if (!isActiveGame) ...[
                    Container(
                      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF121212), border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.5)), borderRadius: BorderRadius.circular(6)),
                      child: Center(child: Text("BET: ${_formatCash(currentBet)}", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 14, fontWeight: FontWeight.w900))),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
                      children: cashChips.map((amount) {
                        int remainingCash = (dirtyCash + cleanCash) - currentBet;
                        bool canAfford = amount <= remainingCash;
                        return InkWell(
                          onTap: canAfford ? () => setState(() => currentBet += amount) : null,
                          child: Opacity(
                            opacity: canAfford ? 1.0 : 0.3,
                            child: Container(width: 45, height: 30, decoration: BoxDecoration(color: const Color(0xFF252525), borderRadius: BorderRadius.circular(15), border: Border.all(color: canAfford ? Colors.white24 : Colors.transparent)), child: Center(child: Text("+${_formatCash(amount).replaceAll('\$', '')}", style: const TextStyle(color: Colors.white, fontSize: 9)))),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14), foregroundColor: Colors.black),
                        onPressed: isDealing ? null : _startGame,
                        child: const Text("START GAME (-1 TOKEN)", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}