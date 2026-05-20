// lib/features/assignment/data/assignment_name_resolver.dart
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AssignmentNameResolver {
  /// Returns the canonical Supabase assignment UUID for the given Drive
  /// folder name, or null if no match is found (offline, migration not yet
  /// applied, or no assignment with that name exists for this enumerator).
  Future<String?> resolveId(String folderName);
}

class SupabaseAssignmentNameResolver implements AssignmentNameResolver {
  const SupabaseAssignmentNameResolver(this._client);
  final SupabaseClient _client;

  @override
  Future<String?> resolveId(String folderName) async {
    // Drive folder sharing is the source of truth for who can access an
    // assignment, so successfully downloading it should also grant
    // Supabase membership. claim_assignment_by_name (033) resolves the
    // canonical UUID and self-joins assignment_members in one call,
    // which is SECURITY DEFINER so it bypasses the membership-gated
    // RLS on public.assignments for first-time downloaders.
    try {
      final result = await _client.rpc(
        'claim_assignment_by_name',
        params: {'p_name': folderName},
      );
      if (result is String) return result;
      return null;
    } catch (_) {
      return null;
    }
  }
}

class NoopAssignmentNameResolver implements AssignmentNameResolver {
  const NoopAssignmentNameResolver();

  @override
  Future<String?> resolveId(String folderName) async => null;
}
