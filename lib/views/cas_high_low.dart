import 'package:flutter/material.dart';

class CasHighLowView extends StatelessWidget {
  final Map<String, dynamic> userData;
  final Function(Map<String, dynamic>) onStateChange;
  final VoidCallback onBack;

  const CasHighLowView({
    super.key,
    required this.userData,
    required this.onStateChange,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text(
          'CASINO GAME PAUSED',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'This legacy Casino game surface is disabled. '
            'Casino gameplay will reopen only after the server-authoritative '
            'Token denomination, paytable and settlement rules are reconciled.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
        ),
      ),
    );
  }
}
