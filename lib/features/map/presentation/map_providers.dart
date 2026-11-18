import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/new_feature/data/new_feature_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Features belong to the explicitly selected map.
final currentFeaturesProvider = StreamProvider<List<Feature>>((ref) {
  final assignment = ref.watch(currentAssignmentProvider).valueOrNull;
  if (assignment == null) return Stream.value([]);
  return ref
      .watch(featureRepositoryProvider)
      .watchFeaturesForAssignment(assignment.id);
});

/// Defaults to the fake renderer for widget tests / early-build safety.
/// main.dart overrides this with MapboxMapRenderer.
final mapRendererProvider = Provider<MapRenderer>((ref) {
  return FakeMapRenderer();
});

final newFeatureRepositoryProvider = Provider<NewFeatureRepository>((ref) {
  return NewFeatureRepository(ref.watch(appDatabaseProvider));
});
