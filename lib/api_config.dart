import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static String get baseUrl {
    // 1. Web bypass
    if (kIsWeb) return 'http://127.0.0.1:3000';

    // 2. Android (Emulator OR Physical Phone) uses the network IP
    if (Platform.isAndroid) return 'http://192.168.254.104:3000';

    // 3. Windows Desktop (running on the exact same machine as Node) uses loopback
    return 'http://127.0.0.1:3000';
  }
}