import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/reshape/data/feature_geometry_revisions_repository.dart';
import 'package:firecheck/features/map/reshape/domain/reshape_mode_state.dart';
import 'package:firecheck/features/map/reshape/presentation/reshape_mode_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reshapeModeControllerProvider =
    NotifierProvider<ReshapeModeController, ReshapeModeState>(
  ReshapeModeController.new,
);

final reshapeRepositoryProvider =
    Provider<FeatureGeometryRevisionsRepository>((ref) {
  return FeatureGeometryRevisionsRepository(ref.watch(appDatabaseProvider));
});
