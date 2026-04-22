import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main_hub.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  // We separate the controllers so the data doesn't get tangled
  final TextEditingController _loginIdController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;

  final String apiUrl = "http://10.0.2.2:3000";

  Future<void> _submitAuth() async {
    setState(() => _isLoading = true);

    final String endpoint = _isLogin ? '/auth/login' : '/auth/register';
    final Uri url = Uri.parse('$apiUrl$endpoint');

    Map<String, dynamic> payload = {};

    // Build the dynamic payload based on our new backend rules
    if (_isLogin) {
      payload = {
        "login_id": _loginIdController.text.trim(), // The 3-Way Login!
        "password": _passwordController.text.trim(),
      };
    } else {
      payload = {
        "email": _emailController.text.trim(),
        "username": _usernameController.text.trim(),
        "password": _passwordController.text.trim(),
      };
    }

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(responseData['message'] ?? "Success!"), backgroundColor: Colors.green),
        );

        // GRAB THE SECURE USER DATA AND PASS IT TO THE HUB
        final Map<String, dynamic> activeUser = responseData['user'];

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainHub(userData: activeUser)),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(responseData['error'] ?? "Action failed."), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot connect to server."), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Color(0xFF39FF14)),
              const SizedBox(height: 20),
              const Text("COLD STREETS", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
              const SizedBox(height: 40),

              if (_isLogin) ...[
                // THE 3-WAY LOGIN FIELD
                TextField(
                  controller: _loginIdController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Email, Street Name, or ID",
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF39FF14))),
                  ),
                ),
              ] else ...[
                // SECURE EMAIL FIELD (Registration)
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: "Secure Email",
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF39FF14))),
                  ),
                ),
                const SizedBox(height: 16),
                // USERNAME FIELD (Registration)
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Street Name (In-Game Alias)",
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF39FF14))),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // PASSWORD FIELD (Always visible)
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Password",
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF39FF14))),
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF39FF14),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _isLoading ? null : _submitAuth,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(_isLogin ? "ENTER THE SYNDICATE" : "REGISTER ACCOUNT", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),

              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    // Clean up fields when swapping modes
                    _loginIdController.clear();
                    _emailController.clear();
                    _usernameController.clear();
                    _passwordController.clear();
                  });
                },
                child: Text(
                  _isLogin ? "Need an account? Register here." : "Already have an empire? Log in.",
                  style: const TextStyle(color: Color(0xFF39FF14)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}