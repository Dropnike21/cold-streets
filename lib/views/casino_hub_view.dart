import 'dart:convert';
import 'package:flutter/material.dart';
import '../api_config.dart';
import '../services/game_http.dart' as http;

class CasinoHubView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final Function(int) onNavigate;

  const CasinoHubView({
    super.key,
    required this.userData,
    required this.onStateChange,
    required this.onNavigate,
  });

  @override
  State<CasinoHubView> createState() => _CasinoHubViewState();
}

class _CasinoHubViewState extends State<CasinoHubView> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _status = const {};

  int _intValue(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/casino/status'),
      );
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _status = data;
          _error = null;
          _loading = false;
        });
      } else {
        setState(() {
          _error = data['error']?.toString() ?? 'Casino status unavailable.';
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Casino status unavailable.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = _intValue(_status['token_balance']);
    final cap = _intValue(_status['effective_daily_token_spend_cap']);
    final spent = _intValue(_status['spent_today']);
    final remaining = _intValue(_status['remaining_daily_spend']);
    final vip = _status['vip_benefits_active'] == true;
    final subscriber = _status['subscriber_active'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        titleSpacing: 16,
        centerTitle: false,
        title: const Text(
          'THE UNDERGROUND',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _fetchStatus,
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    _panel(
                      'CASINO STATUS',
                      _error!,
                      Colors.redAccent,
                    )
                  else ...[
                    _panel(
                      'CASINO TOKENS',
                      '$balance available • $spent spent today • $remaining remaining of $cap',
                      Colors.cyanAccent,
                    ),
                    const SizedBox(height: 12),
                    _panel(
                      'PREMIUM STATUS',
                      subscriber
                          ? 'Subscriber active. VIP-level Casino cap applies.'
                          : vip
                              ? 'VIP-level Casino benefits active.'
                              : 'Standard Casino daily spend cap applies.',
                      Colors.amberAccent,
                    ),
                  ],
                  const SizedBox(height: 24),
                  _panel(
                    'PLAYER VS SYSTEM — PAUSED',
                    'Perya Color Game, Syndicate Slots and High-Low are recognized Token Games, but gameplay remains disabled until their paytables, issuance and settlement rules are fully reconciled.',
                    Colors.white54,
                  ),
                  const SizedBox(height: 12),
                  _panel(
                    'PLAYER VS PLAYER — PAUSED',
                    'PvP Casino settlement remains disabled until authoritative escrow, matchmaking, payout and rake interactions are complete.',
                    Colors.white54,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _panel(String title, String body, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
