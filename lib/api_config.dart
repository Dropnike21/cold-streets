import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // Set with --dart-define=API_BASE_URL=https://your-staging-api.example
  // Do not put secrets in dart-defines; compiled values can be inspected.
  static const String _configuredBaseUrl =
      String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.endsWith('/')
          ? _configuredBaseUrl.substring(0, _configuredBaseUrl.length - 1)
          : _configuredBaseUrl;
    }

    // Default endpoints for local development only.
    if (kIsWeb) return 'http://127.0.0.1:3000';
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    if (Platform.isIOS) return 'http://127.0.0.1:3000';
    return 'http://127.0.0.1:3000';
  }
}
