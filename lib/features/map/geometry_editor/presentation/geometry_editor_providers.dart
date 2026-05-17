import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/geometry_editor/data/feature_geometry_revisions_repository.dart';
import 'package:firecheck/features/map/geometry_editor/domain/geometry_editor_state.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final geometryEditorControllerProvider =
    NotifierProvider<GeometryEditorController, GeometryEditorState>(
  GeometryEditorController.new,
);

final reshapeRepositoryProvider =
    Provider<FeatureGeometryRevisionsRepository>((ref) {
  return FeatureGeometryRevisionsRepository(ref.watch(appDatabaseProvider));
});
