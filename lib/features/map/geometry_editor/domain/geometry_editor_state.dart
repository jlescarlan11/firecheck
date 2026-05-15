import 'package:firecheck/core/db/database.dart' show Feature;
import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;
import 'package:firecheck/features/map/geometry_editor/domain/reshape_op.dart';

class GeometryEditorState {
  const GeometryEditorState({
    this.originalFeature,
    this.workingRings = const [],
    this.undoStack = const [],
    this.selfIntersects = false,
    this.saving = false,
    this.overrideReason,
    this.isClosed = true,
  });

  final Feature? originalFeature;
  final List<List<LngLat>> workingRings;
  final List<ReshapeOp> undoStack;
  final bool selfIntersects;
  final bool saving;
  final String? overrideReason;

  /// `true` for polygon features (rings; midpoint wraps last→first; validated
  /// for self-intersection). `false` for polyline features (parts; no wrap;
  /// no polygon validity check).
  final bool isClosed;

  bool get isActive => originalFeature != null;
  bool get isDirty => undoStack.isNotEmpty;

  GeometryEditorState copyWith({
    Object? originalFeature = _sentinel,
    List<List<LngLat>>? workingRings,
    List<ReshapeOp>? undoStack,
    bool? selfIntersects,
    bool? saving,
    Object? overrideReason = _sentinel,
    bool? isClosed,
  }) {
    return GeometryEditorState(
      originalFeature: identical(originalFeature, _sentinel)
          ? this.originalFeature
          : originalFeature as Feature?,
      workingRings: workingRings ?? this.workingRings,
      undoStack: undoStack ?? this.undoStack,
      selfIntersects: selfIntersects ?? this.selfIntersects,
      saving: saving ?? this.saving,
      overrideReason: identical(overrideReason, _sentinel)
          ? this.overrideReason
          : overrideReason as String?,
      isClosed: isClosed ?? this.isClosed,
    );
  }

  static const _sentinel = Object();
}
