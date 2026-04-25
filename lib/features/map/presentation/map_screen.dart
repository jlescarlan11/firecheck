import 'dart:async';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/centroid.dart';
import 'package:firecheck/core/location/distance.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/override_reason_dialog.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  bool _followMe = true;

  @override
  void initState() {
    super.initState();
    // Kick the OS permission prompt so currentPositionProvider can emit.
    // Without this, geolocator's stream silently errors on a denied
    // permission and taps just see a stuck "waiting for GPS" state.
    Future.microtask(() async {
      await ref.read(locationServiceProvider).requestPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final renderer = ref.watch(mapRendererProvider);
    final featuresAsync = ref.watch(currentFeaturesProvider);
    final assignmentAsync = ref.watch(currentAssignmentProvider);
    // Subscribe so the GPS stream is hot from mount, not first tap.
    ref.watch(currentPositionProvider);

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
    final pos = await _resolvePosition();
    if (pos == null || !mounted) return;

    final ring = decodePolygonGeojson(f.geometryGeojson);
    if (ring == null || ring.isEmpty) return;

    final centroid = polygonCentroid(ring);
    final meters =
        haversineMeters(pos.latitude, pos.longitude, centroid.lat, centroid.lng);

    String? reason;
    if (meters > 50.0) {
      if (!mounted) return;
      reason = await showOverrideReasonDialog(
        context,
        distanceMeters: meters,
      );
      if (reason == null || reason.trim().isEmpty) return;
    }

    if (!mounted) return;
    final submissionRepo = ref.read(submissionRepositoryProvider);
    final submission = await submissionRepo.ensureDraftForFeature(
      featureId: f.id,
      enumeratorId: 'admin',
    );

    if (reason != null) {
      await submissionRepo.updateOverrideReason(submission.id, reason.trim());
    }

    if (!mounted) return;
    context.go('/feature/${f.id}');
  }

  /// Returns a fresh GPS fix, blocking the UI with a small spinner if the
  /// stream hasn't emitted yet. Returns null if the user dismisses or the
  /// fix doesn't arrive within the timeout.
  Future<Position?> _resolvePosition() async {
    final l = AppLocalizations.of(context)!;
    final cached = ref.read(currentPositionProvider).value;
    if (cached != null) return cached;

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 14),
              Text(l.gpsWaitingSnackbar),
            ],
          ),
        ),
      ),
    ),);

    try {
      final pos = await ref
          .read(currentPositionProvider.future)
          .timeout(const Duration(seconds: 8));
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      return pos;
    } on Object {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      return null;
    }
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
