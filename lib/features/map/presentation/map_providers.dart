import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream of features for the currently-active assignment. Emits an empty
/// list until an assignment is downloaded.
final currentFeaturesProvider = StreamProvider<List<Feature>>((ref) {
  final assignment = ref.watch(currentAssignmentProvider).value;
  if (assignment == null) {
    return Stream.value(const <Feature>[]);
  }
  return ref
      .watch(featureRepositoryProvider)
      .watchFeaturesForAssignment(assignment.id);
});

/// Defaults to the fake renderer for widget tests / early-build safety.
/// main.dart overrides this with MapboxMapRenderer (T19).
final mapRendererProvider = Provider<MapRenderer>((ref) {
  return FakeMapRenderer();
});
