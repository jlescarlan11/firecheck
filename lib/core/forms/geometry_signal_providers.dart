// lib/core/forms/geometry_signal_providers.dart
//
// Streams the [GeometrySignal] for a given feature so form notifiers and
// applicability rules re-evaluate automatically when the user reshapes the
// feature mid-survey (Issue #44). Built on top of the existing
// FeatureRepository.watchAllFeatures() stream — the reshape commit lands in
// Drift, the stream emits, and the signal recomputes.
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the [GeometrySignal] for the feature with [featureId]. Emits
/// [GeometrySignal.empty] when the feature is not yet known (deleted, never
/// imported, or the stream hasn't produced a value yet).
final geometrySignalProvider = StreamProvider.autoDispose
    .family<GeometrySignal, String>((ref, featureId) async* {
  final repo = ref.watch(featureRepositoryProvider);
  await for (final features in repo.watchAllFeatures()) {
    final match = features
        .where((f) => f.id == featureId)
        .cast<dynamic>()
        .firstOrNull;
    if (match == null) {
      yield GeometrySignal.empty;
      continue;
    }
    yield geometrySignalFromGeojson(
      match.geometryGeojson as String,
      featureType: match.featureType as String,
    );
  }
});

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
