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
        expansionTileTheme: const ExpansionTileThemeData(
          collapsedIconColor: Color(0xFF39FF14),
          iconColor: Color(0xFF39FF14),
          textColor: Color(0xFF39FF14),
          collapsedTextColor: Colors.white70,
        ),
      ),
      home: const AuthView(), // Go to login screen first!
    );
  }
}