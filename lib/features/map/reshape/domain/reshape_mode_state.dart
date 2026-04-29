import 'package:firecheck/core/db/database.dart' show Feature;
import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;
import 'package:firecheck/features/map/reshape/domain/reshape_op.dart';

class ReshapeModeState {
  const ReshapeModeState({
    this.originalFeature,
    this.workingRings = const [],
    this.undoStack = const [],
    this.selfIntersects = false,
    this.saving = false,
    this.overrideReason,
  });

  final Feature? originalFeature;
  final List<List<LngLat>> workingRings;
  final List<ReshapeOp> undoStack;
  final bool selfIntersects;
  final bool saving;
  final String? overrideReason;

  bool get isActive => originalFeature != null;
  bool get isDirty => undoStack.isNotEmpty;

  ReshapeModeState copyWith({
    Object? originalFeature = _sentinel,
    List<List<LngLat>>? workingRings,
    List<ReshapeOp>? undoStack,
    bool? selfIntersects,
    bool? saving,
    Object? overrideReason = _sentinel,
  }) {
    return ReshapeModeState(
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
    );
  }

  static const _sentinel = Object();
}
