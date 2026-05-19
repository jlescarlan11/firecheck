import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/new_feature/data/new_feature_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream of every imported feature, across every downloaded assignment.
/// Each "Get Maps" / shapefile import creates its own assignment row, but
/// users expect prior folders to keep rendering after a new one is added —
/// so we don't filter by the latest assignment here. (See progress_repository,
/// which counts features the same unfiltered way.)
final currentFeaturesProvider = StreamProvider<List<Feature>>((ref) {
  return ref.watch(featureRepositoryProvider).watchAllFeatures();
});

/// Defaults to the fake renderer for widget tests / early-build safety.
/// main.dart overrides this with MapboxMapRenderer.
final mapRendererProvider = Provider<MapRenderer>((ref) {
  return FakeMapRenderer();
});

final newFeatureRepositoryProvider = Provider<NewFeatureRepository>((ref) {
  return NewFeatureRepository(ref.watch(appDatabaseProvider));
});
