import 'dart:convert';

import 'package:flutter/material.dart';

import '../api_config.dart';
import '../services/game_http.dart' as http;

class BankView extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;

  const BankView({
    super.key,
    required this.userData,
    required this.onStateChange,
  });

  @override
  State<BankView> createState() => _BankViewState();
}

class _BankViewState extends State<BankView> {
  static const Color cBlack = Color(0xFF121212);
  static const Color cPanel = Color(0xFF1A1A1A);
  static const Color cGreen = Color(0xFF39FF14);

  bool _loading = true;
  String? _error;

  String _bankStatus = 'read_only_reconciliation';
  String _termsStatus = 'historical_code_only';
  String _conversionStatus = 'unresolved';
  String _checkProducerStatus = 'issuer contract unresolved';

  Map<String, dynamic> _account = {};
  List<Map<String, dynamic>> _deposits = [];
  List<Map<String, dynamic>> _checks = [];
  List<dynamic> _blockers = [];
  String? _claimingCheckId;

  @override
  void initState() {
    super.initState();
    _fetchBank();
  }

  Future<void> _fetchBank() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final userId = widget.userData['user_id'].toString();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/bank/status/$userId'),
      );

      if (response.statusCode != 200) {
        throw Exception('Bank returned ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        throw Exception('Invalid Bank response.');
      }

      if (!mounted) return;
      setState(() {
        _bankStatus =
            decoded['bank_status']?.toString() ?? 'read_only_reconciliation';
        _termsStatus =
            decoded['time_deposit_terms_status']?.toString() ??
                'historical_code_only';
        _conversionStatus =
            decoded['dirty_to_clean_conversion_status']?.toString() ??
                'unresolved';
        _checkProducerStatus =
            decoded['pending_check_creation_status']?.toString() ??
                'external_issuer_contract_unimplemented';

        _account = decoded['account'] is Map
            ? Map<String, dynamic>.from(decoded['account'])
            : <String, dynamic>{};

        _deposits = decoded['recorded_time_deposits'] is List
            ? (decoded['recorded_time_deposits'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];

        _checks = decoded['recorded_pending_checks'] is List
            ? (decoded['recorded_pending_checks'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : <Map<String, dynamic>>[];

        _blockers = decoded['blockers'] is List
            ? List<dynamic>.from(decoded['blockers'])
            : <dynamic>[];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _claimCheck(Map<String, dynamic> check) async {
    final checkId = check['id']?.toString();
    if (checkId == null || check['claim_available'] != true) return;

    setState(() => _claimingCheckId = checkId);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/bank/claim-check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'check_id': check['id']}),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 200) {
        final updated = Map<String, dynamic>.from(widget.userData);
        updated['dirty_cash'] = data['dirty_cash'];
        updated['clean_cash'] = data['clean_cash'];
        widget.onStateChange(updated);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deferred payout claimed: ${_formatCash(data['amount'])} ${_formatStatus(data['payout_currency'])}',
            ),
            backgroundColor: cGreen,
          ),
        );
        await _fetchBank();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error']?.toString() ?? 'Claim failed.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to claim deferred payout.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _claimingCheckId = null);
    }
  }

  String _formatInteger(dynamic value) {
    final raw = value?.toString() ?? '0';
    final match = RegExp(r'^(-?)(\d+)$').firstMatch(raw);
    if (match == null) return raw;

    final sign = match.group(1) ?? '';
    final digits = match.group(2) ?? '0';
    final out = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }

    return '$sign$out';
  }

  String _formatCash(dynamic value) => '\$${_formatInteger(value)}';

  String _formatStatus(dynamic value) =>
      (value?.toString() ?? 'unknown').replaceAll('_', ' ').toUpperCase();

  String _formatTimestamp(dynamic value) {
    if (value == null) return 'n/a';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return parsed.toLocal().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBlack,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'THE BANK',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        iconTheme: const IconThemeData(color: cGreen),
        actions: [
          IconButton(
            onPressed: _loading ? null : _fetchBank,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: cGreen))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _fetchBank,
                  color: cGreen,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _buildStatusBanner(),
                      const SizedBox(height: 12),
                      _buildBalances(),
                      const SizedBox(height: 18),
                      _sectionTitle('RECORDED TIME DEPOSITS'),
                      const SizedBox(height: 8),
                      if (_deposits.isEmpty)
                        _emptyCard('No recorded time deposits.')
                      else
                        ..._deposits.map(_buildDepositCard),
                      const SizedBox(height: 18),
                      _sectionTitle('RECORDED PENDING CHECKS'),
                      const SizedBox(height: 8),
                      if (_checks.isEmpty)
                        _emptyCard('No recorded pending checks.')
                      else
                        ..._checks.map(_buildCheckCard),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_outlined,
                color: Colors.redAccent, size: 34),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Unable to load Bank.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchBank,
              style: ElevatedButton.styleFrom(
                backgroundColor: cGreen,
                foregroundColor: Colors.black,
              ),
              child: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.07),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BANK PARTIALLY RECONCILED',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Time deposits remain paused because their interest and Dirty→Clean semantics conflict with the recovered economy. Fully contracted, unexpired deferred-payout checks can now be redeemed exactly once; legacy and expired checks remain read-only.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip('BANK', _bankStatus),
              _chip('TERMS', _termsStatus),
              _chip('DIRTY→CLEAN', _conversionStatus),
              _chip('CHECK SOURCE', _checkProducerStatus),
            ],
          ),
          if (_blockers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Blocked by: ${_blockers.map((e) => e.toString().replaceAll('_', ' ')).join(', ')}',
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBalances() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cPanel,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          _row('Dirty Cash', _formatCash(_account['dirty_cash']), cGreen),
          const SizedBox(height: 8),
          _row(
            'Clean Cash',
            _formatCash(_account['clean_cash']),
            Colors.blueAccent,
          ),
          const Divider(color: Colors.white12, height: 20),
          _row(
            'Recorded Bank Trust',
            _formatInteger(_account['bank_trust_level_recorded']),
            Colors.white70,
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Bank Trust progression is not currently source-reconciled and does not unlock executable deposit terms.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositCard(Map<String, dynamic> deposit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cPanel,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DEPOSIT #${deposit['deposit_id']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Text(
                'SETTLEMENT PAUSED',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row(
            'Dirty principal recorded',
            _formatCash(deposit['dirty_deposited']),
            cGreen,
          ),
          _row(
            'Clean principal recorded',
            _formatCash(deposit['clean_deposited']),
            Colors.blueAccent,
          ),
          _row(
            'Payout recorded',
            _formatCash(deposit['total_payout_recorded']),
            Colors.white70,
          ),
          _row(
            'Duration index recorded',
            deposit['duration_index_recorded']?.toString() ?? 'n/a',
            Colors.white54,
          ),
          _row(
            'Status',
            _formatStatus(deposit['status']),
            Colors.white54,
          ),
          _row(
            'Created',
            _formatTimestamp(deposit['created_at']),
            Colors.white38,
          ),
          _row(
            'Unlock timestamp',
            _formatTimestamp(deposit['unlocks_at']),
            Colors.white38,
          ),
          const SizedBox(height: 6),
          Text(
            deposit['timestamp_matured'] == true
                ? 'Timestamp has passed, but payout remains paused pending settlement reconciliation.'
                : 'Recorded unlock timestamp has not passed.',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckCard(Map<String, dynamic> check) {
    final claimable = check['claim_available'] == true;
    final checkId = check['id']?.toString();
    final claiming = checkId != null && _claimingCheckId == checkId;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cPanel,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  check['source']?.toString() ?? 'Unknown source',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                claimable ? 'CLAIMABLE' : _formatStatus(check['settlement_status']),
                style: TextStyle(
                  color: claimable ? cGreen : Colors.amber,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row(
            'Amount',
            _formatCash(check['amount_recorded']),
            check['payout_currency'] == 'dirty_cash'
                ? cGreen
                : Colors.blueAccent,
          ),
          _row(
            'Payout denomination',
            _formatStatus(check['payout_currency']),
            Colors.white70,
          ),
          _row(
            'Issuer',
            _formatStatus(check['issuer_type']),
            Colors.white54,
          ),
          _row(
            'Source reference',
            check['source_ref']?.toString() ?? 'legacy / unavailable',
            Colors.white38,
          ),
          _row('Status', _formatStatus(check['status']), Colors.white54),
          _row(
            'Created',
            _formatTimestamp(check['created_at']),
            Colors.white38,
          ),
          _row(
            'Expiry timestamp',
            _formatTimestamp(check['expires_at']),
            Colors.white38,
          ),
          if (check['claimed_at'] != null)
            _row(
              'Claimed',
              _formatTimestamp(check['claimed_at']),
              Colors.white38,
            ),
          const SizedBox(height: 8),
          if (claimable)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: claiming ? null : () => _claimCheck(check),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen,
                  foregroundColor: Colors.black,
                ),
                child: Text(claiming ? 'CLAIMING…' : 'CLAIM PAYOUT'),
              ),
            )
          else
            const Text(
              'Legacy, already-settled, or expired obligations remain read-only. Expired-check fallback settlement is intentionally unresolved.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cPanel,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: ${_formatStatus(value)}',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _row(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cPanel,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
    );
  }
}
