import 'package:firecheck/features/map/geometry_editor/domain/sketch_validation_error.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';

String sketchErrorMessage(SketchValidationError e, AppLocalizations l) {
  return switch (e) {
    SketchValidationError.notEnoughVertices => l.sketchErrorNotEnoughVertices,
    SketchValidationError.vertexOutsideBoundary => l.outsideBoundarySnackbar,
    SketchValidationError.selfIntersection => l.reshapeErrorSelfIntersection,
    SketchValidationError.zeroLengthEdge => l.reshapeErrorZeroLengthEdge,
  };
}
