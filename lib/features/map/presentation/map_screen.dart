import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/domain/distance_check.dart';
import 'package:firecheck/features/map/presentation/feature_bottom_sheet.dart';
import 'package:firecheck/features/map/presentation/feature_too_far_modal.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  bool _followMe = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final renderer = ref.watch(mapRendererProvider);
    final featuresAsync = ref.watch(currentFeaturesProvider);
    final assignmentAsync = ref.watch(currentAssignmentProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.mapTitle)),
      body: Stack(
        children: [
          featuresAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (features) {
              final boundary =
                  assignmentAsync.value?.boundaryPolygonGeojson ?? '';
              return renderer.build(
                context,
                features: features,
                boundaryGeojson: boundary,
                onFeatureTap: _handleFeatureTap,
              );
            },
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 18,
            child: Row(
              children: [
                _pill(
                  l.followMe,
                  on: _followMe,
                  onTap: () => setState(() => _followMe = !_followMe),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _pill(l.newFeaturePlaceholder, disabled: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleFeatureTap(Feature f) async {
    // Phase 1 placeholder: use Brgy. Tisa coordinate as the "user" position
    // since real GPS wiring with the location_providers lands alongside the
    // real MapboxMapRenderer in T19. Centroid is also a fixed value because
    // geojson centroid math comes in Phase 2 with the form.
    const userLat = 10.31810;
    const userLng = 123.88270;
    final (centroidLat, centroidLng) = _centroidFallback(f.geometryGeojson);

    final result = distanceCheck(
      userLat: userLat,
      userLng: userLng,
      featureCentroidLat: centroidLat,
      featureCentroidLng: centroidLng,
    );

    final open = switch (result) {
      DistanceCheckPass() => true,
      DistanceCheckFail(:final meters) =>
        await showFeatureTooFarModal(context, distanceMeters: meters),
    };

    if (!open || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FeatureBottomSheet(
        feature: f,
        distanceMeters: result.meters,
      ),
    );
  }

  (double, double) _centroidFallback(String geojson) {
    // TODO(phase-2): real GeoJSON centroid. Returning a fixed Brgy. Tisa
    // coordinate keeps Phase 1 tap-testable.
    return (10.31810, 123.88270);
  }

  Widget _pill(
    String label, {
    bool on = false,
    bool disabled = false,
    VoidCallback? onTap,
  }) {
    final color = on ? const Color(0xFF3B82F6) : const Color(0xFFEEEEEE);
    final fg = on ? Colors.white : const Color(0xFF555555);
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
