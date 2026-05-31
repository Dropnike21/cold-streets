import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static String get baseUrl {
    // 1. Web bypass
    if (kIsWeb) return 'http://127.0.0.1:3000';

    // 2. Android
    if (Platform.isAndroid) {
      // 🟢 The magic IP for Android Emulators to reach the host PC
      return 'http://10.0.2.2:3000';

      // ⚠️ Note: If you test on a PHYSICAL Android phone later,
      // you will need to switch back to your current Wi-Fi IPv4 address:
      // return 'http://192.168.254.104:3000';
    }

    // 3. iOS Simulator (If you ever use a Mac)
    if (Platform.isIOS) return 'http://127.0.0.1:3000';

    // 4. Windows/Mac Desktop
    return 'http://127.0.0.1:3000';
  }
}