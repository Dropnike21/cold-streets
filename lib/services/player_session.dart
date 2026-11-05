// Establish internal Cold Streets player identity from a verified Supabase
// access token. Only the Node API may assign an internal integer player ID.
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_config.dart';
import 'game_http.dart' as game_http;

class PlayerSessionException implements Exception {
  final int statusCode;
  final String message;
  const PlayerSessionException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class PlayerSessionApi {
  // This is a username *suggestion*, not an authorization claim. The API
  // validates uniqueness and binds accounts only by verified Auth UUID.
  static String? get suggestedStreetName {
    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
    final raw = metadata?['street_name'];
    return raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
  }

  static Future<Map<String, dynamic>> establish({String? streetName}) async {
    final name = streetName?.trim();
    final response = await game_http.post(
      Uri.parse(ApiConfig.baseUrl + '/auth/session'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({if (name != null && name.isNotEmpty) 'username': name}),
    );
    Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw PlayerSessionException(
          response.statusCode, 'The game server returned an invalid response.');
    }
    if (response.statusCode != 200) {
      throw PlayerSessionException(
          response.statusCode, json['error']?.toString() ?? 'Unable to open player account.');
    }
    final user = json['user'];
    if (user is! Map) {
      throw const PlayerSessionException(502, 'The game server did not return a player profile.');
    }
    return Map<String, dynamic>.from(user);
  }
}
