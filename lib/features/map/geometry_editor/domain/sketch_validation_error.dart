/// Errors surfaced by [GeometryEditorController.validateSketch]. Mapped to
/// snackbar copy by `sketchErrorMessage(...)` in the presentation layer.
enum SketchValidationError {
  /// Below the per-type minimum: 3 (building), 2 (road), 1 (point).
  notEnoughVertices,

  /// At least one vertex is outside the assignment boundary.
  vertexOutsideBoundary,

  /// Polygon outer ring crosses itself.
  selfIntersection,

  /// Two adjacent vertices coincide (zero-length segment).
  zeroLengthEdge,
}
