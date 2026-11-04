// Authenticated HTTP adapter for existing Cold Streets views.
// Each request uses an unexpired Supabase session. Client-supplied player IDs
// are never authentication; the Node API verifies the bearer independently.
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as base_http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_config.dart';

Future<Map<String, String>> _authorized(Uri uri, Map<String, String>? headers) async {
  final api = Uri.parse(ApiConfig.baseUrl);
  final prefix = api.path.endsWith('/')
      ? api.path.substring(0, api.path.length - 1)
      : api.path;
  if (uri.origin != api.origin ||
      (prefix.isNotEmpty && uri.path != prefix &&
          !uri.path.startsWith('$prefix/'))) {
    throw StateError('Refusing to send an access token outside the game API.');
  }

  final auth = Supabase.instance.client.auth;
  var session = auth.currentSession;
  if (session == null) throw StateError('Sign in to Cold Streets first.');
  if (session.isExpired) {
    session = (await auth.refreshSession()).session;
  }
  if (session == null || session.isExpired) {
    throw StateError('Your game session has expired. Sign in again.');
  }
  // Header names are case-insensitive. Remove any alternate spelling of
  // Authorization before attaching the verified session token.
  final safeHeaders = Map<String, String>.from(headers ?? const {});
  safeHeaders.removeWhere((name, _) => name.toLowerCase() == 'authorization');
  return <String, String>{
    ...safeHeaders,
    'Authorization': 'Bearer ${session.accessToken}',
  };
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

Future<Map<String, String>> _postHeaders(
  Uri uri,
  Map<String, String>? headers,
) async {
  final result = await _authorized(uri, headers);
  final existing = result.entries
      .where((entry) => entry.key.toLowerCase() == 'idempotency-key')
      .toList();
  if (existing.isEmpty) {
    result['Idempotency-Key'] = _uuidV4();
  } else if (existing.length > 1) {
    throw StateError('Duplicate Idempotency-Key headers are not allowed.');
  }
  return result;
}

Future<base_http.Response> get(Uri url, {Map<String, String>? headers}) async =>
    base_http.get(url, headers: await _authorized(url, headers));

Future<base_http.Response> post(Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async => base_http.post(
  url, headers: await _postHeaders(url, headers), body: body, encoding: encoding,
);

Future<base_http.Response> put(Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async => base_http.put(
  url, headers: await _authorized(url, headers), body: body, encoding: encoding,
);

Future<base_http.Response> delete(Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async => base_http.delete(
  url, headers: await _authorized(url, headers), body: body, encoding: encoding,
);
