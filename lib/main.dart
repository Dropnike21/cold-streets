import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'views/auth_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // P0 security posture: keep refresh tokens in memory, not plain
  // SharedPreferences. Players sign in again after restarting the game.
  if (SupabaseConfig.configured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
      authOptions: const FlutterAuthClientOptions(persistSession: false),
    );
  }
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
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white70),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF39FF14).withValues(alpha: 0.1),
            side: const BorderSide(color: Color(0xFF39FF14)),
            foregroundColor: const Color(0xFF39FF14),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1),
          ),
        ),
      ),
      home: SupabaseConfig.configured
          ? const AuthView()
          : const Scaffold(
              body: Center(child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Cold Streets authentication is not configured.\n'
                  'Supply SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY '
                  'as build-time environment definitions.',
                  textAlign: TextAlign.center,
                ),
              )),
            ),
    );
  }
}
