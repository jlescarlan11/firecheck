import 'dart:async';
import 'dart:convert';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Events emitted while creating an offline tile region.
sealed class OfflinePackEvent {
  const OfflinePackEvent();
}

class OfflinePackProgress extends OfflinePackEvent {
  const OfflinePackProgress({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
}

class OfflinePackComplete extends OfflinePackEvent {
  const OfflinePackComplete();
}

class OfflinePackError extends OfflinePackEvent {
  const OfflinePackError(this.message);
  final String message;
}

/// Narrow wrapper around `mapbox_maps_flutter`'s [TileStore] so we can
/// swap in a scripted fake in tests.
abstract class OfflinePackAdapter {
  Stream<OfflinePackEvent> createPack({
    required String regionGeojson,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
  });

  Future<int> estimateBytes({
    required String regionGeojson,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
  });

  Future<void> cancelAllPacks();
}

/// Real adapter backed by Mapbox [TileStore].
///
/// Notes on MapboxMapRenderer wiring:
/// - Mapbox 2.22 `TileStore.loadTileRegion` takes the region `id`, a
///   [TileRegionLoadOptions], and an optional progress listener. It returns
///   a `Future<TileRegion>` that completes on success or throws on failure.
/// - `TileRegionLoadOptions.geometry` is a `Map<String?, Object?>` built from
///   decoded GeoJSON text.
/// - Creating a new region requires `descriptorsOptions` with
///   [TilesetDescriptorOptions] (styleURI + zoom range).
/// - There is no explicit "cancel" API on [TileStore]. We use best-effort
///   `removeRegion` for every known region. A pending load for the same id
///   is also implicitly canceled by kicking off another load (per the SDK
///   docs), but we don't rely on that here.
class MapboxOfflinePackAdapter implements OfflinePackAdapter {
  MapboxOfflinePackAdapter(this._tileStore);

  final TileStore _tileStore;

  /// Region id used when the caller doesn't care. In T19 the caller will
  /// pass a stable id so updates refresh instead of duplicate.
  static const String _defaultRegionId = 'firecheck-default-region';

  static const int _fallbackEstimateBytes = 100 * 1024 * 1024;

  TileRegionLoadOptions _buildLoadOptions({
    required String regionGeojson,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
  }) {
    final decoded = jsonDecode(regionGeojson);
    final geometry =
        (decoded is Map) ? decoded.cast<String?, Object?>() : <String?, Object?>{};
    return TileRegionLoadOptions(
      geometry: geometry,
      descriptorsOptions: <TilesetDescriptorOptions?>[
        TilesetDescriptorOptions(
          styleURI: styleUri,
          minZoom: minZoom,
          maxZoom: maxZoom,
        ),
      ],
      acceptExpired: true,
      networkRestriction: NetworkRestriction.NONE,
    );
  }

  @override
  Stream<OfflinePackEvent> createPack({
    required String regionGeojson,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
  }) {
    final controller = StreamController<OfflinePackEvent>();

    unawaited(() async {
      try {
        final options = _buildLoadOptions(
          regionGeojson: regionGeojson,
          styleUri: styleUri,
          minZoom: minZoom,
          maxZoom: maxZoom,
        );
        await _tileStore.loadTileRegion(_defaultRegionId, options, (progress) {
          if (controller.isClosed) return;
          controller.add(
            OfflinePackProgress(
              downloaded: progress.completedResourceCount,
              total: progress.requiredResourceCount,
            ),
          );
        });
        if (!controller.isClosed) {
          controller.add(const OfflinePackComplete());
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.add(OfflinePackError(e.toString()));
        }
      } finally {
        await controller.close();
      }
    }());

    return controller.stream;
  }

  @override
  Future<int> estimateBytes({
    required String regionGeojson,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
  }) async {
    try {
      final options = _buildLoadOptions(
        regionGeojson: regionGeojson,
        styleUri: styleUri,
        minZoom: minZoom,
        maxZoom: maxZoom,
      );
      final result = await _tileStore.estimateTileRegion(
        _defaultRegionId,
        options,
        null,
        null,
      );
      return result.transferSize;
    } catch (_) {
      return _fallbackEstimateBytes;
    }
  }

  @override
  Future<void> cancelAllPacks() async {
    // Best-effort: remove every existing region. Mapbox 2.22 has no explicit
    // "cancel in-flight download" API on TileStore. Per SDK docs, any pending
    // load for a region id fails with Canceled when the region is removed or
    // a new load for the same id is started.
    try {
      final regions = await _tileStore.allTileRegions();
      for (final region in regions) {
        try {
          await _tileStore.removeRegion(region.id);
        } catch (_) {
          // Swallow per-region failures; cancelAllPacks is best-effort.
        }
      }
    } catch (_) {
      // Swallow listing failures; cancelAllPacks is best-effort.
    }
  }
}

/// Scripted fake for tests. Yields [scriptedEvents] in order from
/// [createPack] and records [cancelAllPacks] calls via [cancelCount].
class FakeOfflinePackAdapter implements OfflinePackAdapter {
  FakeOfflinePackAdapter({
    this.scriptedEvents = const [],
    int estimateBytes = 100 * 1024 * 1024,
  }) : _estimateBytes = estimateBytes;

  final List<OfflinePackEvent> scriptedEvents;
  final int _estimateBytes;
  int cancelCount = 0;

  @override
  Stream<OfflinePackEvent> createPack({
    required String regionGeojson,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
  }) async* {
    for (final event in scriptedEvents) {
      yield event;
      await Future<void>.delayed(const Duration(microseconds: 1));
    }
  }

  @override
  Future<int> estimateBytes({
    required String regionGeojson,
    required String styleUri,
    required int minZoom,
    required int maxZoom,
  }) async =>
      _estimateBytes;

  @override
  Future<void> cancelAllPacks() async {
    cancelCount += 1;
  }
}
