import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late AppDatabase db;
  late _MockSupabaseClient supa;
  late AssignmentRepository repo;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    supa = _MockSupabaseClient();
    repo = AssignmentRepository(client: supa, db: db);
  });

  tearDown(() async => db.close());

  test('upsertBundle writes assignment + features in one transaction',
      () async {
    await repo.upsertBundle(
      assignment: {
        'id': 'a1',
        'enumerator_id': 'u1',
        'campaign_id': 'c1',
        'boundary_polygon': '{"type":"Polygon"}',
        'status': 'assigned',
        'created_at': DateTime.now().toIso8601String(),
      },
      features: [
        {
          'id': 'f1',
          'assignment_id': 'a1',
          'feature_type': 'building',
          'geometry': '{"type":"Polygon"}',
          'is_new': false,
          'created_at': DateTime.now().toIso8601String(),
        },
        {
          'id': 'f2',
          'assignment_id': 'a1',
          'feature_type': 'building',
          'geometry': '{"type":"Polygon"}',
          'is_new': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      ],
      ra9514Types: const [],
    );

    final assignments = await db.select(db.assignments).get();
    expect(assignments, hasLength(1));
    expect(assignments.first.id, 'a1');

    final features = await db.select(db.features).get();
    expect(features, hasLength(2));
  });

  test('upsertBundle rolls back all writes on a bad feature row', () async {
    expect(
      () => repo.upsertBundle(
        assignment: {
          'id': 'a1',
          'enumerator_id': 'u1',
          'campaign_id': 'c1',
          'boundary_polygon': '{}',
          'status': 'assigned',
          'created_at': DateTime.now().toIso8601String(),
        },
        features: [
          {
            'id': null, // bad — Drift insert will throw
            'assignment_id': 'a1',
            'feature_type': 'building',
            'geometry': '{}',
            'is_new': false,
            'created_at': DateTime.now().toIso8601String(),
          },
        ],
        ra9514Types: const [],
      ),
      throwsA(anything),
    );

    // Give the failed future a moment to complete before asserting state.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final assignments = await db.select(db.assignments).get();
    expect(
      assignments,
      isEmpty,
      reason: 'assignment must not persist on feature failure',
    );
  });

  test('getCurrentAssignment returns null when Drift is empty', () async {
    final result = await repo.getCurrentAssignment();
    expect(result, isNull);
  });

  test('watchCurrentAssignment emits the most recent assignment', () async {
    await repo.upsertBundle(
      assignment: {
        'id': 'a1',
        'enumerator_id': 'u1',
        'campaign_id': 'c1',
        'boundary_polygon': '{}',
        'status': 'assigned',
        'created_at': DateTime.now().toIso8601String(),
      },
      features: const [],
      ra9514Types: const [],
    );
    final snap = await repo.watchCurrentAssignment().first;
    expect(snap, isNotNull);
    expect(snap!.id, 'a1');
  });
}
