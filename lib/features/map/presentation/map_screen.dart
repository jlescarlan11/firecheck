import 'dart:async';

import 'package:firecheck/core/analytics/analytics_providers.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/centroid.dart';
import 'package:firecheck/core/geo/polygon_bounds.dart';
import 'package:firecheck/features/map/presentation/camera_target.dart';
import 'package:firecheck/core/geo/point_in_polygon.dart';
import 'package:firecheck/core/geo/polyline_midpoint.dart';
import 'package:firecheck/core/location/distance.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/core/location/location_service.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/recenter_button.dart';
import 'package:firecheck/features/map/presentation/recenter_button_state.dart';
import 'package:firecheck/features/new_feature/presentation/feature_type_picker.dart';
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
  bool _addModeActive = false;

  RecenterButtonState _recenterState = RecenterButtonState.idle;
  CameraTarget? _cameraTarget;
  int _recenterRequestSeq = 0;
  bool _rationaleVisible = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final renderer = ref.watch(mapRendererProvider);
    final featuresAsync = ref.watch(currentFeaturesProvider);
    final assignmentAsync = ref.watch(currentAssignmentProvider);
    // Subscribe so the GPS stream is hot from mount, not first tap.
    ref.watch(currentPositionProvider);

    // Bug 13b: don't mount the Mapbox renderer until BOTH the assignment
    // AND the features list have loaded. currentFeaturesProvider returns
    // Stream.value([]) while the assignment is null (loading), so without
    // this gate the renderer would mount with an empty features list,
    // _onMapCreated would attach the click listener to a manager with 0
    // annotations, and subsequent feature emissions wouldn't register
    // tappable polygons (mapbox_maps_flutter 2.22 quirk — listener bound
    // to an empty manager doesn't pick up later annotations cleanly).
    final assignment = assignmentAsync.value;
    final features = featuresAsync.value;
    final mapReady = assignment != null && features != null;

    final bounds = assignment != null
        ? polygonBoundsFromGeojson(assignment.boundaryPolygonGeojson)
        : null;
    final initialCameraTarget = bounds != null
        ? CameraTarget(
            lat: bounds.center.lat,
            lng: bounds.center.lng,
            zoom: bounds.zoom,
            requestId: 0,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(l.mapTitle)),
      body: Stack(
        children: [
          SizedBox.expand(
            child: !mapReady
                ? const Center(child: CircularProgressIndicator())
                : renderer.build(
                    context,
                    features: features,
                    boundaryGeojson: assignment.boundaryPolygonGeojson,
                    onFeatureTap: _handleFeatureTap,
                    onLongPress: _handleLongPress,
                    addModeActive: _addModeActive,
                    initialCameraTarget: initialCameraTarget,
                    cameraTarget: _cameraTarget,
                  ),
          ),
          if (_addModeActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: const Color(0xFF3B82F6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    l.addModeBannerHint,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 84,
            child: RecenterButton(
              state: _recenterState,
              onTap: _onRecenterTap,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 18,
            child: Row(
              children: [
                // Scoped Consumer so lock-state stream emissions don't
                // rebuild the whole map (which would re-mount the Mapbox
                // renderer and lose its tap handlers — Bug 11, surfaced
                // during the first manual happy path).
                Expanded(
                  child: Consumer(
                    builder: (context, ref2, _) {
                      final isLocked =
                          ref2.watch(isAssignmentLockedProvider);
                      return _pill(
                        _addModeActive
                            ? l.addModePillActiveLabel
                            : l.newFeaturePlaceholder,
                        on: _addModeActive,
                        disabled: isLocked,
                        key: const Key('map.add-feature-pill'),
                        onTap: () => setState(
                          () => _addModeActive = !_addModeActive,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLongPress(double lat, double lng) async {
    if (!_addModeActive) return;
    final l = AppLocalizations.of(context)!;
    final assignment = ref.read(currentAssignmentProvider).value;
    final boundary = assignment?.boundaryPolygonGeojson ?? '';

    if (!pointInPolygonGeojson(lat, lng, boundary)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.outsideBoundarySnackbar)),
      );
      return;
    }

    if (!mounted) return;
    final type = await showFeatureTypePicker(context);
    if (type == null) {
      if (mounted) setState(() => _addModeActive = false);
      return;
    }

    final newFeatureRepo = ref.read(newFeatureRepositoryProvider);
    final feature = await newFeatureRepo.createNewFeature(
      assignmentId: assignment!.id,
      featureType: type,
      lat: lat,
      lng: lng,
    );

    if (!mounted) return;
    setState(() => _addModeActive = false);
    context.go('/feature/${feature.id}');
  }

  Future<void> _handleFeatureTap(Feature f) async {
    final pos = await _resolvePosition();
    if (!mounted) return;

    // Bug 14: GPS may be unavailable (denied permission, no fix yet on
    // emulator). The proximity check is best-effort — if we have a
    // position we enforce the 50m rule; if not, we proceed to the detail
    // screen without an override reason. The check is for compliance,
    // not security; the server doesn't reject far-away submissions.
    String? reason;
    if (pos != null) {
      final LatLng centroid;
      if (f.featureType == 'road') {
        final coords = decodePolylineGeojson(f.geometryGeojson);
        if (coords == null || coords.isEmpty) return;
        centroid = polylineMidpoint(coords);
      } else {
        final ring = decodePolygonGeojson(f.geometryGeojson);
        if (ring == null || ring.isEmpty) return;
        centroid = polygonCentroid(ring);
      }
      final meters = haversineMeters(
        pos.latitude,
        pos.longitude,
        centroid.lat,
        centroid.lng,
      );

      if (meters > 50.0) {
        if (!mounted) return;
        reason = await showOverrideReasonDialog(
          context,
          distanceMeters: meters,
        );
        if (reason == null || reason.trim().isEmpty) return;
      }
    }

    if (!mounted) return;
    final submissionRepo = ref.read(submissionRepositoryProvider);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      throw StateError('Map tap without authenticated user');
    }
    final submission = await submissionRepo.ensureDraftForFeature(
      featureId: f.id,
      enumeratorId: userId,
    );

    if (reason != null) {
      await submissionRepo.updateOverrideReason(submission.id, reason.trim());
    }

    if (!mounted) return;
    context.go('/feature/${f.id}');
  }

  Future<void> _onRecenterTap() async {
    if (_recenterState != RecenterButtonState.idle) return;
    if (_rationaleVisible) return;

    // Single increment per tap — used both for slow-path supersedence
    // detection AND as the CameraTarget.requestId for renderer dedup.
    final seq = ++_recenterRequestSeq;
    final analytics = ref.read(analyticsServiceProvider);
    final locationService = ref.read(locationServiceProvider);

    var perm = await locationService.checkPermission();

    // Rationale + OS prompt path lands in Task 15. For now, treat plain
    // `denied` the same as deniedForever — bail without a snackbar but
    // also without a fly. (Behavior tightened in Task 15.)

    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.unableToDetermine) {
      _showSettingsShortcutSnackbar(locationService);
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'permission_denied_forever',
      });
      return;
    }
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) {
      return; // tightened in Task 15
    }

    if (seq != _recenterRequestSeq) return;

    final cached = ref.read(currentPositionProvider).valueOrNull;
    if (cached != null && cached.accuracy <= 100.0) {
      _flyTo(cached, seq: seq);
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'recentered_from_cache',
        'accuracy_m': cached.accuracy.round(),
      });
      return;
    }

    setState(() => _recenterState = RecenterButtonState.loading);

    try {
      final accurate = await locationService
          .positionStream()
          .firstWhere((p) => p.accuracy <= 100.0)
          .timeout(const Duration(seconds: 8));

      if (!mounted || seq != _recenterRequestSeq) return;
      _flyTo(accurate, seq: seq);
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'recentered_after_wait',
        'accuracy_m': accurate.accuracy.round(),
      });
    } on TimeoutException {
      if (!mounted || seq != _recenterRequestSeq) return;
      final best = ref.read(currentPositionProvider).valueOrNull;
      if (best != null) _flyTo(best, seq: seq);
      _showLowAccuracySnackbar();
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'low_accuracy_timeout',
        'accuracy_m': best?.accuracy.round(),
      });
    } finally {
      if (mounted && seq == _recenterRequestSeq) {
        setState(() => _recenterState = RecenterButtonState.idle);
      }
    }
  }

  void _flyTo(Position p, {required int seq}) {
    setState(() {
      _cameraTarget = CameraTarget(
        lat: p.latitude,
        lng: p.longitude,
        zoom: 17,
        requestId: seq,
      );
    });
  }

  /// Returns a fresh GPS fix, blocking the UI with a small spinner if the
  /// stream hasn't emitted yet. Returns null if the user dismisses or the
  /// fix doesn't arrive within the timeout.
  Future<Position?> _resolvePosition() async {
    final l = AppLocalizations.of(context)!;
    // .valueOrNull instead of .value: AsyncValue.value re-throws when the
    // provider is in error state (location permission denied). Bug 14.
    final cached = ref.read(currentPositionProvider).valueOrNull;
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

  void _showLowAccuracySnackbar() {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.locationSnackbarLowAccuracy)),
    );
  }

  void _showSettingsShortcutSnackbar(LocationService locationService) {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.locationSnackbarPermanentlyDenied),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: l.locationSnackbarOpenSettings,
          onPressed: () => locationService.openAppSettings(),
        ),
      ),
    );
  }

  Widget _pill(
    String label, {
    Key? key,
    bool on = false,
    bool disabled = false,
    VoidCallback? onTap,
  }) {
    final color = on ? const Color(0xFF3B82F6) : const Color(0xFFEEEEEE);
    final fg = on ? Colors.white : const Color(0xFF555555);
    return Opacity(
      key: key,
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
