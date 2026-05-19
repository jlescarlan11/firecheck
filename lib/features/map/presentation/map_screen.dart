import 'dart:async';

import 'package:firecheck/core/analytics/analytics_providers.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/centroid.dart';
import 'package:firecheck/core/geo/polygon_bounds.dart';
import 'package:firecheck/core/geo/polygon_validator.dart';
import 'package:firecheck/core/geo/polyline_midpoint.dart';
import 'package:firecheck/core/location/distance.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/core/location/location_service.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/camera_target.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/recenter_button.dart';
import 'package:firecheck/features/map/presentation/recenter_button_state.dart';
import 'package:firecheck/features/map/presentation/zoom_button.dart';
import 'package:firecheck/features/map/presentation/zoom_button_state.dart';
import 'package:firecheck/features/map/presentation/zoom_direction.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_chip.dart';
import 'package:firecheck/features/map/geometry_editor/domain/geometry_editor_state.dart';
import 'package:firecheck/features/map/geometry_editor/domain/reshape_op.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/reshape_action_sheet.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_banner.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_overlay.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/sketch_error_messages.dart';
import 'package:firecheck/features/new_feature/presentation/feature_type_picker.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/override_reason_dialog.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  RecenterButtonState _recenterState = RecenterButtonState.idle;
  CameraTarget? _cameraTarget;
  int _cameraRequestSeq = 0;
  bool _rationaleVisible = false;

  double? _displayZoom;
  double? _displayLat;
  double? _displayLng;

  double? _commandedZoom;
  Timer? _animationSettleTimer;

  MapProjection? _reshapeProjection;
  // Incremented on every projection refresh — forces the editor overlay
  // to rebuild (and the preview painter to repaint) even when the
  // underlying projection instance is reused.
  int _projectionEpoch = 0;

  bool _lockBlockerShown = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final renderer = ref.watch(mapRendererProvider);
    final featuresAsync = ref.watch(currentFeaturesProvider);
    final assignmentAsync = ref.watch(currentAssignmentProvider);
    final editorState = ref.watch(geometryEditorControllerProvider);
    final reshapeActive = editorState.isActive && !editorState.isSketchMode;
    final sketchActive = editorState.isSketchMode;
    // Subscribe so the GPS stream is hot from mount, not first tap.
    ref.watch(currentPositionProvider);

    // Lock-while-reshape — if the assignment locks while the user is
    // mid-reshape, dirty edits are blocked behind a non-dismissable dialog
    // (Exit discards), and a clean session exits silently.
    final isLocked = ref.watch(isAssignmentLockedProvider);
    if (reshapeActive && isLocked) {
      if (editorState.isDirty && !_lockBlockerShown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showLockWhileDirtyBlocker();
        });
      } else if (!editorState.isDirty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(geometryEditorControllerProvider.notifier).cancel();
        });
      }
    }

    final assignment = assignmentAsync.value;
    final features = featuresAsync.value;
    final mapReady = !assignmentAsync.isLoading && !featuresAsync.isLoading;

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
                    features: features ?? [],
                    boundaryGeojson: assignment?.boundaryPolygonGeojson ?? '',
                    onFeatureTap: _handleFeatureTap,
                    onCameraChanged: _onCameraChanged,
                    sketchActive: sketchActive,
                    onMapTap: _onSketchTap,
                    initialCameraTarget: initialCameraTarget,
                    cameraTarget: _cameraTarget,
                    onPolygonLongPress: _handlePolygonLongPress,
                    // The CustomPaint preview inside GeometryEditorOverlay is
                    // now the single source of truth for the live working
                    // shape (both sketch and reshape). Keeping the Mapbox-
                    // annotation preview as well caused phantom trails: each
                    // drag fires an async delete+create on the polygon
                    // manager and the creates can land before earlier
                    // deletes, leaving stacked polygons. Always-null here.
                    reshapeWorkingPolygonGeojson: null,
                    reshapingFeatureId:
                        reshapeActive ? editorState.originalFeature?.id : null,
                    onProjectionReady: (p) {
                      // Always rebuild on every camera change — the
                      // renderer reuses the same projection instance and
                      // mutates its internal state on refresh, so identity
                      // equality would always be true and the overlay
                      // would never reproject as the user pans/zooms.
                      setState(() {
                        _reshapeProjection = p;
                        _projectionEpoch++;
                      });
                    },
                  ),
          ),
          if ((reshapeActive || sketchActive) && _reshapeProjection != null)
            Positioned.fill(
              child: GeometryEditorOverlay(
                key: ValueKey('editor-overlay-$_projectionEpoch'),
                projection: _reshapeProjection!,
              ),
            ),
          // Shows "👥 N edited by others" when the remote_attributions_cache
          // has rows from other enumerators. Hidden when count is zero. Sits
          // below the AppBar.
          if (!reshapeActive && !sketchActive)
            const Positioned(
              left: 12,
              top: 12,
              child: RemoteActivityChip(),
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
            right: 16,
            bottom: 144,
            child: ZoomButton(
              key: const Key('map.zoom-out-button'),
              direction: ZoomDirection.zoomOut,
              state: _zoomOutState(),
              onTap: _onZoomOut,
            ),
          ),
          Positioned(
            right: 16,
            bottom: 204,
            child: ZoomButton(
              key: const Key('map.zoom-in-button'),
              direction: ZoomDirection.zoomIn,
              state: _zoomInState(),
              onTap: _onZoomIn,
            ),
          ),
          if (!reshapeActive)
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
                          sketchActive
                              ? l.addModePillActiveLabel
                              : l.newFeaturePlaceholder,
                          on: sketchActive,
                          disabled:
                              sketchActive || reshapeActive || isLocked,
                          key: const Key('map.add-feature-pill'),
                          onTap: _onPlusPressed,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (reshapeActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GeometryEditorBanner(
                editCount: editorState.undoStack.length,
                undoEnabled: editorState.isDirty && !editorState.saving,
                saveEnabled: editorState.isDirty && !editorState.saving,
                // Disable Cancel while saving — the async commit transaction
                // would otherwise still complete in the background after the
                // UI exits edit mode, producing surprising state transitions.
                onCancel: editorState.saving ? null : _onReshapeCancel,
                onUndo: () => ref
                    .read(geometryEditorControllerProvider.notifier)
                    .undo(),
                onSave: _onReshapeSave,
              ),
            ),
          if (sketchActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GeometryEditorBanner(
                editCount: editorState.workingRings.isNotEmpty
                    ? editorState.workingRings[0].length
                    : 0,
                undoEnabled: editorState.undoStack.isNotEmpty,
                saveEnabled: _sketchFinishEnabled(editorState),
                onCancel: _onSketchCancel,
                onUndo: () => ref
                    .read(geometryEditorControllerProvider.notifier)
                    .undo(),
                onSave: _onSketchFinish,
              ),
            ),
        ],
      ),
    );
  }

  void _onReshapeCancel() {
    final state = ref.read(geometryEditorControllerProvider);
    final featureId = state.originalFeature?.id ?? '';
    final ops = state.undoStack.length;
    ref.read(geometryEditorControllerProvider.notifier).cancel();
    ref.read(analyticsServiceProvider).track(
      'map.reshape.cancelled',
      properties: {
        'feature_id': featureId,
        'ops_made': ops,
      },
    );
  }

  Future<void> _showLockWhileDirtyBlocker() async {
    if (!mounted) return;
    setState(() => _lockBlockerShown = true);
    final l = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Text(l.reshapeLockWhileDirtyBanner),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.reshapeLockExit),
          ),
        ],
      ),
    );
    if (!mounted) return;
    ref.read(geometryEditorControllerProvider.notifier).cancel();
    setState(() => _lockBlockerShown = false);
  }

  Future<void> _onReshapeSave() async {
    final l = AppLocalizations.of(context)!;
    final ctrl = ref.read(geometryEditorControllerProvider.notifier);
    final s = ref.read(geometryEditorControllerProvider);
    final assignment = ref.read(currentAssignmentProvider).value;
    if (s.originalFeature == null || assignment == null) return;

    // validateBuildingPolygon enforces polygon rules (closure, orientation,
    // self-intersection). Polyline reshape doesn't have those rules; skip
    // the check when the working geometry is open.
    //
    // Boundary handling: when the user provided an override reason at
    // reshape entry (e.g. they're editing a building from far away), also
    // skip the per-vertex boundary check. The user already justified the
    // edit; blocking on boundary here would force them to cancel and start
    // over even though they explicitly accepted responsibility. Pass the
    // empty-string sentinel to validateBuildingPolygon, which short-circuits
    // the boundary check the same way the morning fix for empty-coords
    // Polygons did.
    if (s.isClosed) {
      final boundaryForCheck = s.overrideReason != null
          ? ''
          : assignment.boundaryPolygonGeojson;
      final res = validateBuildingPolygon(
        s.workingRings,
        boundaryGeojson: boundaryForCheck,
      );
      if (!res.valid) {
        final msg = _validationMessage(res.error!, l);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        ref.read(analyticsServiceProvider).track(
          'map.reshape.validation_failed',
          properties: {
            'feature_id': s.originalFeature!.id,
            'rule': res.error!.name,
            'override_used': s.overrideReason != null,
          },
        );
        return;
      }
    }

    ctrl.markSaving(saving: true);
    final userId = ref.read(currentUserIdProvider) ?? '';
    final repo = ref.read(reshapeRepositoryProvider);
    final newGeojson = ctrl.serializeWorkingPolygon();
    final revisionId = const Uuid().v4();
    final start = DateTime.now();

    try {
      await repo.saveReshape(
        revisionId: revisionId,
        featureId: s.originalFeature!.id,
        prevGeojson: s.originalFeature!.geometryGeojson,
        newGeojson: newGeojson,
        editedBy: userId,
        editedAt: DateTime.now(),
        overrideReason: s.overrideReason,
      );
      ref.read(analyticsServiceProvider).track(
        'map.reshape.completed',
        properties: {
          'feature_id': s.originalFeature!.id,
          'vertex_count_before':
              _vertexCount(s.originalFeature!.geometryGeojson),
          'vertex_count_after': s.workingRings[0].length,
          'vertex_moves': s.undoStack.whereType<Move>().length,
          'vertex_adds': s.undoStack.whereType<Add>().length,
          'vertex_removes': s.undoStack.whereType<Remove>().length,
          'override_used': s.overrideReason != null,
          'duration_ms': DateTime.now().difference(start).inMilliseconds,
        },
      );
      ctrl.cancel(); // exits edit mode
    } on Object catch (e) {
      ctrl.markSaving(saving: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save reshape: $e')),
      );
    }
  }

  String _validationMessage(PolygonValidationError err, AppLocalizations l) {
    return switch (err) {
      PolygonValidationError.tooFewVertices => l.reshapeErrorTooFewVertices,
      PolygonValidationError.zeroOrNegativeArea => l.reshapeErrorZeroArea,
      PolygonValidationError.selfIntersection =>
        l.reshapeErrorSelfIntersection,
      PolygonValidationError.vertexOutsideBoundary =>
        l.reshapeErrorOutsideBoundary,
      PolygonValidationError.zeroLengthEdge => l.reshapeErrorZeroLengthEdge,
    };
  }

  Future<void> _onPlusPressed() async {
    final l = AppLocalizations.of(context)!;
    final assignment = ref.read(currentAssignmentProvider).value;
    if (assignment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.noAssignmentForEnumerator)),
      );
      return;
    }
    final type = await showFeatureTypePicker(context);
    if (type == null) return;
    ref
        .read(geometryEditorControllerProvider.notifier)
        .enterSketch(featureType: type);
    ref.read(analyticsServiceProvider).track(
      'map.sketch.entered',
      properties: {'feature_type': type},
    );
  }

  void _onSketchTap(double lat, double lng) {
    if (!ref.read(geometryEditorControllerProvider).isSketchMode) return;
    ref
        .read(geometryEditorControllerProvider.notifier)
        .appendSketchVertex((lng: lng, lat: lat));
  }

  bool _sketchFinishEnabled(GeometryEditorState s) {
    final n = s.workingRings.isNotEmpty ? s.workingRings[0].length : 0;
    switch (s.pendingFeatureType) {
      case 'building':
        return n >= 3;
      case 'road':
        return n >= 2;
      case 'point':
        return n >= 1;
      default:
        return false;
    }
  }

  Future<void> _onSketchFinish() async {
    final l = AppLocalizations.of(context)!;
    final assignment = ref.read(currentAssignmentProvider).value;
    if (assignment == null) return;
    final ctrl = ref.read(geometryEditorControllerProvider.notifier);
    final state = ref.read(geometryEditorControllerProvider);
    final type = state.pendingFeatureType;
    if (type == null) return;

    final err = ctrl.validateSketch(
      boundaryGeojson: assignment.boundaryPolygonGeojson,
    );
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sketchErrorMessage(err, l))),
      );
      ref.read(analyticsServiceProvider).track(
        'map.sketch.validation_failed',
        properties: {'feature_type': type, 'rule': err.name},
      );
      return;
    }

    // serializeWorking() handles polygon/polyline correctly; for point we
    // need to override since it's a single coord, not a ring.
    final geom = type == 'point'
        ? '{"type":"Point","coordinates":[${state.workingRings[0][0].lng},${state.workingRings[0][0].lat}]}'
        : ctrl.serializeWorking();

    final repo = ref.read(newFeatureRepositoryProvider);
    final feature = await repo.createFeature(
      assignmentId: assignment.id,
      featureType: type,
      geometryGeojson: geom,
    );

    ref.read(analyticsServiceProvider).track(
      'map.sketch.completed',
      properties: {
        'feature_type': type,
        'vertex_count': state.workingRings[0].length,
        'ops_made': state.undoStack.length,
      },
    );

    ctrl.cancel();
    if (!mounted) return;
    // Await the push so we can refresh after the user pops back. The Mapbox
    // annotation channel can briefly disconnect during the push transition;
    // if the initial _rerenderFeatures call silently fails on that dead
    // channel, the polygon stays invisible until something else mutates the
    // features list. Invalidating the provider on return forces a fresh
    // emission and a clean re-render on a healthy channel.
    await context.push('/feature/${Uri.encodeComponent(feature.id)}');
    if (!mounted) return;
    ref.invalidate(currentFeaturesProvider);
  }

  Future<void> _onSketchCancel() async {
    final l = AppLocalizations.of(context)!;
    final state = ref.read(geometryEditorControllerProvider);
    final type = state.pendingFeatureType ?? '';
    final vertexCount = state.workingRings.isNotEmpty
        ? state.workingRings[0].length
        : 0;

    if (vertexCount == 0) {
      ref.read(geometryEditorControllerProvider.notifier).cancel();
      ref.read(analyticsServiceProvider).track(
        'map.sketch.cancelled',
        properties: {'feature_type': type, 'vertex_count': 0, 'ops_made': 0},
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.sketchDiscardConfirmTitle),
        content: Text(l.sketchDiscardConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.sketchDiscardKeepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.sketchDiscardConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(geometryEditorControllerProvider.notifier).cancel();
      ref.read(analyticsServiceProvider).track(
        'map.sketch.cancelled',
        properties: {
          'feature_type': type,
          'vertex_count': vertexCount,
          'ops_made': state.undoStack.length,
        },
      );
    }
  }

  Future<void> _handlePolygonLongPress(Feature feature) async {
    final l = AppLocalizations.of(context)!;
    final locked = ref.read(isAssignmentLockedProvider);
    if (locked) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.reshapeLockedSnackbar)));
      return;
    }
    if (!mounted) return;
    final action = await showReshapeActionSheet(context, locked: locked);
    if (!mounted || action == null) return;
    switch (action) {
      case ReshapeAction.openForm:
        await _handleFeatureTap(feature);
      case ReshapeAction.reshape:
        await _enterReshape(feature);
    }
  }

  Future<void> _enterReshape(Feature feature) async {
    // Distance gate — mirrors _handleFeatureTap; await the resolved position.
    final pos = await _resolvePosition();
    if (!mounted) return;

    String? overrideReason;
    if (pos != null) {
      final LatLng centroid;
      if (feature.featureType == 'road') {
        final coords = decodePolylineGeojson(feature.geometryGeojson);
        if (coords == null || coords.isEmpty) return;
        centroid = polylineMidpoint(coords);
      } else {
        final ring = decodePolygonGeojson(feature.geometryGeojson);
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
        overrideReason = await showOverrideReasonDialog(
          context,
          distanceMeters: meters,
        );
        if (overrideReason == null || overrideReason.trim().isEmpty) {
          return; // user cancelled or empty
        }
      }
    }

    if (!mounted) return;
    ref.read(geometryEditorControllerProvider.notifier).enterReshape(
          feature: feature,
          overrideReason: overrideReason,
        );

    ref.read(analyticsServiceProvider).track(
      'map.reshape.entered',
      properties: {
        'feature_id': feature.id,
        'vertex_count': _vertexCount(feature.geometryGeojson),
        'override_used': overrideReason != null,
      },
    );
  }

  int _vertexCount(String geojson) {
    final ring = decodePolygonGeojson(geojson);
    if (ring == null || ring.isEmpty) return 0;
    // Strip the duplicated closing vertex if present.
    if (ring.first[0] == ring.last[0] && ring.first[1] == ring.last[1]) {
      return ring.length - 1;
    }
    return ring.length;
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
    context.push('/feature/${Uri.encodeComponent(f.id)}');
  }

  void _onCameraChanged(double zoom, double lat, double lng) {
    final prevRounded = _displayZoom?.round();
    _displayZoom = zoom;
    _displayLat = lat;
    _displayLng = lng;
    if (prevRounded != zoom.round()) {
      setState(() {});
    }
  }

  ZoomButtonState _zoomInState() {
    final z = _commandedZoom?.round() ?? _displayZoom?.round();
    if (z == null) return ZoomButtonState.idle;
    return z >= 22 ? ZoomButtonState.disabled : ZoomButtonState.idle;
  }

  ZoomButtonState _zoomOutState() {
    final z = _commandedZoom?.round() ?? _displayZoom?.round();
    if (z == null) return ZoomButtonState.idle;
    return z <= 0 ? ZoomButtonState.disabled : ZoomButtonState.idle;
  }

  Future<void> _onZoomIn() => _onZoom(1);
  Future<void> _onZoomOut() => _onZoom(-1);

  Future<void> _onZoom(int delta) async {
    // Anchor on commanded if a previous tap is still animating; otherwise
    // anchor on the live display zoom. Bail out cleanly if neither is set
    // (renderer hasn't fired its first onCameraChanged yet — sub-frame race).
    final base = _commandedZoom?.round() ?? _displayZoom?.round();
    final lat = _displayLat;
    final lng = _displayLng;
    if (base == null || lat == null || lng == null) return;

    final newZoom = (base + delta).clamp(0, 22);
    if (newZoom == base) return;

    ref.read(analyticsServiceProvider).track(
      'map.zoom.tapped',
      properties: {
        'direction': delta > 0 ? 'in' : 'out',
        'from_zoom': base,
      },
    );

    setState(() {
      _commandedZoom = newZoom.toDouble();
      _cameraTarget = CameraTarget(
        lat: lat,
        lng: lng,
        zoom: newZoom.toDouble(),
        requestId: ++_cameraRequestSeq,
        animation: CameraAnimation.ease,
      );
    });

    _animationSettleTimer?.cancel();
    _animationSettleTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _commandedZoom = null);
    });
  }

  Future<void> _onRecenterTap() async {
    if (_recenterState != RecenterButtonState.idle) return;
    if (_rationaleVisible) return;

    // Single increment per tap — used both for slow-path supersedence
    // detection AND as the CameraTarget.requestId for renderer dedup.
    final seq = ++_cameraRequestSeq;
    final analytics = ref.read(analyticsServiceProvider);
    final locationService = ref.read(locationServiceProvider);

    var perm = await locationService.checkPermission();

    if (perm == LocationPermission.denied) {
      final allow = await _showLocationRationale();
      if (allow != true) {
        analytics.track('map.recenter.tapped', properties: {
          'outcome': 'permission_rationale_dismissed',
        },);
        return;
      }
      perm = await locationService.requestPermission();
    }

    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.unableToDetermine) {
      _showSettingsShortcutSnackbar(locationService);
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'permission_denied_forever',
      },);
      return;
    }

    if (perm == LocationPermission.denied) {
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'permission_denied',
      },);
      return;
    }

    if (seq != _cameraRequestSeq) return;

    final cached = ref.read(currentPositionProvider).valueOrNull;
    if (cached != null && cached.accuracy <= 100.0) {
      _flyTo(cached, seq: seq);
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'recentered_from_cache',
        'accuracy_m': cached.accuracy.round(),
      },);
      return;
    }

    setState(() => _recenterState = RecenterButtonState.loading);

    try {
      final accurate = await locationService
          .positionStream()
          .firstWhere((p) => p.accuracy <= 100.0)
          .timeout(const Duration(seconds: 8));

      if (!mounted || seq != _cameraRequestSeq) return;
      _flyTo(accurate, seq: seq);
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'recentered_after_wait',
        'accuracy_m': accurate.accuracy.round(),
      },);
    } on TimeoutException {
      if (!mounted || seq != _cameraRequestSeq) return;
      final best = ref.read(currentPositionProvider).valueOrNull;
      if (best != null) _flyTo(best, seq: seq);
      _showLowAccuracySnackbar();
      analytics.track('map.recenter.tapped', properties: {
        'outcome': 'low_accuracy_timeout',
        'accuracy_m': best?.accuracy.round(),
      },);
    } finally {
      if (mounted && seq == _cameraRequestSeq) {
        setState(() => _recenterState = RecenterButtonState.idle);
      }
    }
  }

  @override
  void dispose() {
    _animationSettleTimer?.cancel();
    super.dispose();
  }

  void _flyTo(Position p, {required int seq}) {
    setState(() {
      // Recenter supersedes any in-flight zoom command; clear the commanded-
      // zoom anchor so the next zoom tap re-anchors on the post-recenter
      // display zoom rather than the stale pre-recenter target.
      _animationSettleTimer?.cancel();
      _commandedZoom = null;
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

  Future<bool?> _showLocationRationale() async {
    if (!mounted) return null;
    _rationaleVisible = true;
    try {
      final l = AppLocalizations.of(context)!;
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          title: Text(l.locationRationaleTitle),
          content: Text(l.locationRationaleBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(l.locationRationaleNotNow),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(l.locationRationaleAllow),
            ),
          ],
        ),
      );
    } finally {
      _rationaleVisible = false;
    }
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
