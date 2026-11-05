import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // Node.js game API (NOT the Supabase REST endpoint).
  static const _remote = String.fromEnvironment('API_BASE_URL');
  static String get baseUrl {
    if (_remote.isNotEmpty) {
      final uri = Uri.tryParse(_remote);
      if (uri == null || !uri.hasAuthority ||
          (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && (uri.host == 'localhost' ||
          uri.host == '127.0.0.1' || uri.host == '10.0.2.2')))) {
        throw StateError('API_BASE_URL must use HTTPS; localhost is for development only.');
      }
      return _remote.endsWith('/')
          ? _remote.substring(0, _remote.length - 1) : _remote;
    }
    // Emulator-only defaults. On physical devices use HTTPS API_BASE_URL.
    if (kIsWeb) return 'http://127.0.0.1:3000';
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://127.0.0.1:3000';
  }
}
