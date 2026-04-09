import 'package:flutter/material.dart';
import 'views/auth_view.dart';

void main() {
  runApp(const ColdStreetsApp());
}

class ColdStreetsApp extends StatelessWidget {
  const ColdStreetsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cold Streets',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF39FF14),
        fontFamily: 'Courier',
        dividerColor: Colors.transparent,

        // Your existing Expansion Tile Theme
        expansionTileTheme: const ExpansionTileThemeData(
          collapsedIconColor: Color(0xFF39FF14),
          iconColor: Color(0xFF39FF14),
          textColor: Color(0xFF39FF14),
          collapsedTextColor: Colors.white70,
        ),

        // 🔥 NEW: Force all default text to be bright white
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white70),
        ),

        // 🔥 NEW: Protect your Neon Buttons globally
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1),
            side: const BorderSide(color: Color(0xFF39FF14)),
            foregroundColor: const Color(0xFF39FF14), // Text inside stays neon
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1),
          ),
        ),
      ),
      home: const AuthView(), // Go to login screen first!
    );
  }
}