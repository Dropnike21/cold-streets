import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/player_session.dart';
import 'main_hub.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  StreamSubscription<AuthState>? _authChanges;
  bool _isLogin = true;
  bool _isLoading = false;
  bool _needsStreetName = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Handles Supabase confirmation links returning to the application.
    // Avoid duplicate /auth/session calls while a manual login is in progress.
    _authChanges = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (mounted && !_isLoading &&
            state.event == AuthChangeEvent.signedIn) {
          _openGame();
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _message = 'Authentication could not be completed.');
      },
    );

    if (Supabase.instance.client.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openGame();
      });
    }
  }

  void _notify(String text) {
    if (!mounted) return;
    setState(() => _message = text);
  }

  Future<void> _openGame() async {
    if (_isLoading || !mounted) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      final inputName = _usernameController.text.trim();
      final username = inputName.isEmpty
          ? PlayerSessionApi.suggestedStreetName
          : inputName;

      final profile = await PlayerSessionApi.establish(streetName: username);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainHub(userData: profile)),
      );
    } on PlayerSessionException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 400 || e.statusCode == 409) {
        setState(() {
          _isLogin = true;
          _needsStreetName = true;
        });
      }
      _notify(e.message);
    } catch (_) {
      _notify('Cannot connect to the game server. Check the API configuration.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAuth() async {
    if (_isLoading) return;
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final name = _usernameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _notify('Enter your email and password.');
      return;
    }
    if (!_isLogin && !RegExp(r'^[A-Za-z0-9_]{3,24}$').hasMatch(name)) {
      _notify('Street Name must be 3-24 letters, digits, or underscores.');
      return;
    }

    // When a signed-in user needs to claim their first street name, do not
    // send another password login; the bearer token is already available.
    if (_isLogin && _needsStreetName &&
        Supabase.instance.client.auth.currentSession != null) {
      await _openGame();
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_isLogin) {
        await auth.signInWithPassword(email: email, password: password);
      } else {
        final signup = await auth.signUp(
          email: email,
          password: password,
          // Street name is a *hint* for later profile initialization, not a
          // role or entitlement. The Node server validates it independently.
          data: {'street_name': name},
        );

        if (signup.session == null) {
          if (!mounted) return;
          setState(() {
            _isLogin = true;
            _needsStreetName = false;
            _message = 'Check your inbox to confirm your email. Then sign in.';
          });
          return;
        }
      }
    } on AuthException catch (error) {
      _notify(error.message);
      return;
    } catch (_) {
      _notify('Could not reach Supabase Auth. Please try again.');
      return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (mounted) await _openGame();
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Color(0xFF39FF14)),
              const SizedBox(height: 20),
              const Text(
                'COLD STREETS',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                    color: Colors.white, letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              const Text('SECURE SYNDICATE ACCESS',
                  style: TextStyle(fontSize: 12, color: Colors.white54,
                      letterSpacing: 1.4)),
              const SizedBox(height: 30),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                style: const TextStyle(color: Colors.white),
                decoration: _field('Email Address'),
              ),
              if (!_isLogin || _needsStreetName) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.white),
                  decoration: _field(_isLogin
                      ? 'New Street Name (first-time profile)'
                      : 'Street Name (In-Game Alias)'),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                style: const TextStyle(color: Colors.white),
                decoration: _field('Password'),
                onSubmitted: (_) => _submitAuth(),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orangeAccent,
                        fontSize: 12)),
              ],
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF39FF14),
                      foregroundColor: Colors.black),
                  onPressed: _isLoading ? null : _submitAuth,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(_isLogin ? 'ENTER THE SYNDICATE' : 'REGISTER ACCOUNT',
                          style: const TextStyle(fontSize: 16,
                              fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _isLoading ? null : () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _needsStreetName = false;
                    _message = null;
                    _passwordController.clear();
                  });
                },
                child: Text(
                  _isLogin ? 'Need an account? Register here.'
                      : 'Already have an empire? Log in.',
                  style: const TextStyle(color: Color(0xFF39FF14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: Colors.grey[900],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF39FF14)),
        ),
      );
}
