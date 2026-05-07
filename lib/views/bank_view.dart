import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';

class BankView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const BankView({super.key, required this.userData, required this.onStateChange});

  @override
  State<BankView> createState() => _BankViewState();
}

class _BankViewState extends State<BankView> {
  late int dirtyCash;
  late int cleanCash;
  late int totalCash;
  late int bankTrustLevel;

  final double currentBankCap = 2000000000; // 2 Billion limit

  final TextEditingController _amountController = TextEditingController();
  double _depositAmount = 0;
  int _selectedDurationIndex = 0;
  final double _perkBonus = 0.0;

  final List<String> _durations = ['7 Days', '2 Weeks', '1 Month', '3 Months', '6 Months'];
  final List<double> _baseRates = [0.005, 0.011, 0.025, 0.09, 0.22];

  // --- Active Time Deposit State ---
  bool hasActiveDeposit = false;
  DateTime? activeDepositUnlockTime;
  double activeDirtyUsed = 0;
  double activeCleanUsed = 0;

  // --- Pending Checks State ---
  List<Map<String, dynamic>> pendingChecks = [];

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncState();

    // Timer to update the countdowns every second
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  void _syncState() {
    bankTrustLevel = _parseSafeInt(widget.userData['bank_trust_level']);
    dirtyCash = _parseSafeInt(widget.userData['dirty_cash']);
    cleanCash = _parseSafeInt(widget.userData['clean_cash']);
    totalCash = dirtyCash + cleanCash;

    // Parse Active Deposit
    if (widget.userData['active_time_deposit'] != null) {
      var activeData = widget.userData['active_time_deposit'];
      hasActiveDeposit = true;
      activeDirtyUsed = _parseDouble(activeData['dirty_amount']);
      activeCleanUsed = _parseDouble(activeData['clean_amount']);
      _depositAmount = activeDirtyUsed + activeCleanUsed;
      _selectedDurationIndex = _parseSafeInt(activeData['duration_index']);

      if (activeData['unlocks_at'] != null) {
        activeDepositUnlockTime = DateTime.parse(activeData['unlocks_at']).toLocal();
      }

      _amountController.text = _depositAmount.toInt().toString();
    } else {
      hasActiveDeposit = false;
      _selectedDurationIndex = min(2, bankTrustLevel);
    }

    // Parse Pending Checks
    if (widget.userData['pending_checks'] != null) {
      pendingChecks = List<Map<String, dynamic>>.from(widget.userData['pending_checks']);
    }
  }

  int _parseSafeInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _formatCash(double amount) {
    String formatted = amount.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (Match m) => '${m[1]},'
    );
    return '\$$formatted';
  }

  String _getTimeLeft(DateTime? expiryTime) {
    if (expiryTime == null) return "--:--:--";
    final diff = expiryTime.difference(DateTime.now());
    if (diff.isNegative) return "READY";

    if (diff.inDays > 0) {
      return "${diff.inDays}d ${diff.inHours % 24}h ${diff.inMinutes % 60}m";
    }
    return "${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  void _onAmountChanged(String value) {
    if (hasActiveDeposit) return;

    String cleanString = value.replaceAll(RegExp(r'[^0-9]'), '');
    double parsed = double.tryParse(cleanString) ?? 0;
    double maxAllowed = min(totalCash.toDouble(), currentBankCap);

    if (parsed > maxAllowed) {
      parsed = maxAllowed;
      _amountController.text = parsed.toInt().toString();
      _amountController.selection = TextSelection.fromPosition(TextPosition(offset: _amountController.text.length));
    }

    setState(() {
      _depositAmount = parsed;
    });
  }

  void _setMax() {
    if (hasActiveDeposit) return;
    double maxAllowed = min(totalCash.toDouble(), currentBankCap);
    setState(() {
      _depositAmount = maxAllowed;
      _amountController.text = maxAllowed.toInt().toString();
    });
  }

  void _processDeposit() {
    if (_depositAmount <= 0 || _depositAmount > totalCash || _depositAmount > currentBankCap) return;

    int amountToProcess = _depositAmount.toInt();
    int dirtyToTake = min(amountToProcess, dirtyCash);
    int cleanToTake = amountToProcess - dirtyToTake;

    // Optimistic UI Update
    setState(() {
      dirtyCash -= dirtyToTake;
      cleanCash -= cleanToTake;
      totalCash = dirtyCash + cleanCash;

      widget.userData['dirty_cash'] = dirtyCash;
      widget.userData['clean_cash'] = cleanCash;

      hasActiveDeposit = true;
      activeDirtyUsed = dirtyToTake.toDouble();
      activeCleanUsed = cleanToTake.toDouble();

      int days = _selectedDurationIndex == 0 ? 7 : (_selectedDurationIndex == 1 ? 14 : (_selectedDurationIndex == 2 ? 30 : (_selectedDurationIndex == 3 ? 90 : 180)));
      activeDepositUnlockTime = DateTime.now().add(Duration(days: days));

      widget.onStateChange(widget.userData);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Laundered \$${_formatCash(dirtyToTake.toDouble())} dirty & \$${_formatCash(cleanToTake.toDouble())} clean!"),
        backgroundColor: const Color(0xFF39FF14),
      ),
    );
  }

  void _claimCheck(int checkIndex) {
    double amount = _parseDouble(pendingChecks[checkIndex]['amount']);

    setState(() {
      cleanCash += amount.toInt();
      totalCash = dirtyCash + cleanCash;
      widget.userData['clean_cash'] = cleanCash;

      pendingChecks.removeAt(checkIndex);
      widget.onStateChange(widget.userData);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Successfully withdrew \$${_formatCash(amount)} to your clean wallet."),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double currentBaseRate = _baseRates[_selectedDurationIndex];
    double totalRate = currentBaseRate + _perkBonus;

    double dirtyUsed = hasActiveDeposit ? activeDirtyUsed : min(_depositAmount, dirtyCash.toDouble());
    double cleanUsed = hasActiveDeposit ? activeCleanUsed : max(0, _depositAmount - dirtyCash.toDouble());
    double interestEarned = _depositAmount * totalRate;
    double totalPayout = _depositAmount + interestEarned;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // --- SECTION 1: TIME DEPOSIT ---
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                // 👇 UPDATED: .withValues() used here
                border: Border.all(color: hasActiveDeposit ? const Color(0xFF39FF14).withValues(alpha: 0.5) : Colors.white12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(hasActiveDeposit ? "ACTIVE DEPOSIT LOCKED" : "NEW TIME DEPOSIT", style: TextStyle(color: hasActiveDeposit ? const Color(0xFF39FF14) : Colors.white, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                      if (hasActiveDeposit) const Icon(Icons.lock_clock, color: Color(0xFF39FF14), size: 16),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),

                  // 1. DEPOSIT INPUT
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("DEPOSIT AMOUNT", style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                      if (!hasActiveDeposit) Text("Max Limit: ${_formatCash(currentBankCap)}", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  IgnorePointer(
                    ignoring: hasActiveDeposit,
                    child: Opacity(
                      opacity: hasActiveDeposit ? 0.6 : 1.0,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _amountController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.attach_money, color: Colors.grey, size: 20),
                                filled: true,
                                fillColor: const Color(0xFF1E1E1E),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                hintText: "0",
                                hintStyle: const TextStyle(color: Colors.white24),
                              ),
                              onChanged: _onAmountChanged,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: totalCash > 0 ? _setMax : null,
                            child: const Text("MAX", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. DURATION DROPDOWN
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("INVESTMENT DURATION", style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                      if (!hasActiveDeposit) Text("Trust Lvl: $bankTrustLevel", style: const TextStyle(color: Color(0xFF39FF14), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  IgnorePointer(
                    ignoring: hasActiveDeposit,
                    child: Opacity(
                      opacity: hasActiveDeposit ? 0.6 : 1.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(6)),
                        child: DropdownButton<int>(
                          value: _selectedDurationIndex,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1A1A1A),
                          underline: const SizedBox(),
                          icon: Icon(Icons.arrow_drop_down, color: hasActiveDeposit ? Colors.grey : const Color(0xFF39FF14)),
                          items: List.generate(_durations.length, (index) {
                            bool isLocked = index > bankTrustLevel;
                            return DropdownMenuItem<int>(
                              value: index,
                              enabled: !isLocked,
                              child: Row(
                                children: [
                                  if (isLocked) const Icon(Icons.lock, color: Colors.white24, size: 14),
                                  if (isLocked) const SizedBox(width: 8),
                                  Text(
                                    "${_durations[index]}  —  ${(_baseRates[index] * 100).toStringAsFixed(1)}%",
                                    style: TextStyle(color: isLocked ? Colors.white24 : Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                            );
                          }),
                          onChanged: (val) {
                            if (val != null && !hasActiveDeposit) setState(() => _selectedDurationIndex = val);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. PREVIEW GRAPH & STATS
                  const Text("TRANSACTION PREVIEW", style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    height: 240,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF121212), border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: _buildStackedBarChart(dirtyUsed, cleanUsed, interestEarned, totalPayout)),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatRow("Dirty Used", _formatCash(dirtyUsed), const Color(0xFF39FF14)),
                              const SizedBox(height: 8),
                              _buildStatRow("Clean Used", _formatCash(cleanUsed), Colors.blueAccent),
                              const SizedBox(height: 8),
                              // 👇 UPDATED: .withValues() used here
                              _buildStatRow("Interest Gain", "+${_formatCash(interestEarned)}", const Color(0xFF39FF14).withValues(alpha: 0.8)),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white24, height: 1)),
                              const Text("TOTAL PAYOUT", style: TextStyle(color: Colors.grey, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                              Text(_formatCash(totalPayout), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. ACTION BUTTON OR TIMER
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: hasActiveDeposit
                        ? Container(
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(6)),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.timer, color: Colors.white54, size: 18),
                          const SizedBox(width: 8),
                          Text("UNLOCKS IN: ${_getTimeLeft(activeDepositUnlockTime)}", style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ],
                      ),
                    )
                        : ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF39FF14), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                      onPressed: _depositAmount > 0 ? () => _processDeposit() : null,
                      child: const Text("CONFIRM DEPOSIT", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // --- SECTION 2: CHECK WITHDRAWALS ---
            const Text("INCOMING TRANSFERS", style: TextStyle(color: Colors.grey, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "WARNING: Uncleared funds will automatically liquidate into your street wallet after 24 hours, increasing risk of muggings.",
              style: TextStyle(color: Colors.redAccent, fontSize: 11, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),

            if (pendingChecks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
                child: const Text("No pending transfers found.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
              )
            else
              ...pendingChecks.asMap().entries.map((entry) {
                int index = entry.key;
                var check = entry.value;
                DateTime expiry = DateTime.parse(check['expires_at']).toLocal();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  // 👇 UPDATED: .withValues() used here
                  decoration: BoxDecoration(color: const Color(0xFF1E1E1E), border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Colors.blueAccent, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(check['source'] ?? "Unknown Source", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                            Text(_formatCash(_parseDouble(check['amount'])), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                            Text("Auto-liquidates in: ${_getTimeLeft(expiry)}", style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                        onPressed: () => _claimCheck(index),
                        child: const Text("CLAIM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildStatRow(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStackedBarChart(double dirty, double clean, double interest, double total) {
    if (total == 0) {
      return Container(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade800, width: 2))));
    }

    int interestFlex = max(1, ((interest / total) * 1000).toInt());
    int dirtyFlex = max(1, ((dirty / total) * 1000).toInt());
    int cleanFlex = max(1, ((clean / total) * 1000).toInt());

    List<Widget> bars = [];

    if (interest > 0) {
      bars.add(Flexible(
        flex: interestFlex,
        child: Container(
          width: 50,
          // 👇 UPDATED: .withValues() used here
          decoration: BoxDecoration(color: const Color(0xFF39FF14).withValues(alpha: 0.1), border: Border.all(color: const Color(0xFF39FF14), width: 1.5), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        ),
      ));
    }
    if (dirty > 0) {
      bars.add(Flexible(
        flex: dirtyFlex,
        child: Container(width: 50, decoration: BoxDecoration(color: const Color(0xFF39FF14), borderRadius: interest == 0 ? const BorderRadius.vertical(top: Radius.circular(4)) : BorderRadius.zero)),
      ));
    }
    if (clean > 0) {
      bars.add(Flexible(
        flex: cleanFlex,
        child: Container(width: 50, decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: (interest == 0 && dirty == 0) ? BorderRadius.circular(4) : const BorderRadius.vertical(bottom: Radius.circular(4)))),
      ));
    }

    return Column(mainAxisAlignment: MainAxisAlignment.end, children: bars);
  }
}