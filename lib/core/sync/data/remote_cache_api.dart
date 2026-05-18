import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// Network surface area for the phase-2 remote-cache pull paths.
/// Real impl wraps Supabase RPCs; tests stub this directly so they don't
/// have to mock the `PostgrestFilterBuilder` returned by `client.rpc()`.
abstract class RemoteCacheApi {
  Future<List<Map<String, dynamic>>> fetchAttributions(
    String assignmentId, {
    DateTime? since,
  });

  Future<List<Map<String, dynamic>>> fetchNewFeatures(
    String assignmentId, {
    DateTime? since,
  });
}

class SupabaseRemoteCacheApi implements RemoteCacheApi {
  SupabaseRemoteCacheApi(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchAttributions(
    String assignmentId, {
    DateTime? since,
  }) async {
    final raw = await _client.rpc<dynamic>(
      'fetch_remote_attributions',
      params: {
        'p_assignment_id': assignmentId,
        'p_since': since?.toUtc().toIso8601String(),
      },
    );
    return _coerce(raw);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNewFeatures(
    String assignmentId, {
    DateTime? since,
  }) async {
    final raw = await _client.rpc<dynamic>(
      'fetch_remote_new_features',
      params: {
        'p_assignment_id': assignmentId,
        'p_since': since?.toUtc().toIso8601String(),
      },
    );
    return _coerce(raw);
  }

  List<Map<String, dynamic>> _coerce(Object? raw) {
    if (raw is List) {
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }
}
