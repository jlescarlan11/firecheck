import 'dart:convert';
import 'package:firecheck/core/errors/failure.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends app-session credentials only. No Google access tokens or sign-in UI.
class GatewayClient {
  GatewayClient({
    required this.baseUri,
    required this.userId,
    required this.accessToken,
    required this.refresh,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    if (baseUri.scheme != 'https' &&
        !(baseUri.scheme == 'http' &&
            ['localhost', '127.0.0.1'].contains(baseUri.host))) {
      throw ArgumentError('Gateway requires HTTPS');
    }
    if (baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw ArgumentError('Invalid gateway URL');
    }
  }
  factory GatewayClient.supabase(Uri uri, SupabaseClient client) =>
      GatewayClient(
        baseUri: uri,
        userId: () => client.auth.currentUser?.id,
        accessToken: () => client.auth.currentSession?.accessToken,
        refresh: () async {
          await client.auth.refreshSession();
        },
      );
  final Uri baseUri;
  final String? Function() userId;
  final String? Function() accessToken;
  final Future<void> Function() refresh;
  final http.Client _client;
  void close() => _client.close();

  Future<http.StreamedResponse> send(
    String method,
    String path, {
    List<int>? bytes,
    Map<String, String> headers = const {},
    String? owner,
  }) async {
    final expected = owner ?? userId();
    if (expected == null || userId() != expected) {
      throw const AuthFailure(
        'Sign in with the account that owns this transfer.',
      );
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = accessToken();
      if (token == null || userId() != expected) {
        throw const AuthFailure('Please sign in to FireCheck.');
      }
      final relative = Uri.parse(path);
      if (!path.startsWith('/v1/') ||
          !relative.path.startsWith('/v1/') ||
          relative.hasScheme ||
          relative.hasAuthority ||
          path
              .split('?')
              .first
              .split('/')
              .map(Uri.decodeComponent)
              .any((segment) => segment == '..' || segment == '.')) {
        throw ArgumentError('Invalid gateway path');
      }
      final prefix = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
      final uri = baseUri.replace(
        path: '$prefix${relative.path}',
        query: relative.hasQuery ? relative.query : null,
      );
      final req = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll({...headers, 'Authorization': 'Bearer $token'});
      if (bytes != null) req.bodyBytes = bytes;
      final response =
          await _client.send(req).timeout(const Duration(seconds: 60));
      if (userId() != expected) {
        await response.stream.drain<void>();
        throw const AuthFailure('Your account changed. Please try again.');
      }
      if (response.statusCode == 401 && attempt == 0) {
        await response.stream.drain<void>();
        await refresh();
        continue;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      final raw = await response.stream
          .bytesToString()
          .timeout(const Duration(seconds: 15));
      String? code;
      try {
        code = (jsonDecode(raw) as Map<String, dynamic>)['code'] as String?;
      } catch (_) {}
      if (response.statusCode == 401) {
        throw const AuthFailure('Please sign in to FireCheck again.');
      }
      if (response.statusCode == 403) {
        throw const AuthFailure(
          'You do not have access to this assignment. Contact your supervisor.',
        );
      }
      if (code == 'ASSIGNMENT_CLOSED') throw const AssignmentClosedFailure();
      if (response.statusCode == 409) {
        throw NetworkFailure(
          'The transfer changed ($code). Retry to resume safely.',
        );
      }
      throw const NetworkFailure(
        'The file service is temporarily unavailable. Try again or contact your supervisor.',
      );
    }
    throw const AuthFailure('Please sign in to FireCheck again.');
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? owner,
  }) async {
    final r = await send(
      method,
      path,
      owner: owner,
      headers: {if (body != null) 'Content-Type': 'application/json'},
      bytes: body == null ? null : utf8.encode(jsonEncode(body)),
    );
    final raw =
        await r.stream.bytesToString().timeout(const Duration(seconds: 60));
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
