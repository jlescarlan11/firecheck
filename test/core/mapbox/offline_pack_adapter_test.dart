import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FakeOfflinePackAdapter', () {
    test('emits progress events then complete', () async {
      final adapter = FakeOfflinePackAdapter(
        scriptedEvents: const [
          OfflinePackProgress(downloaded: 100, total: 1000),
          OfflinePackProgress(downloaded: 500, total: 1000),
          OfflinePackProgress(downloaded: 1000, total: 1000),
          OfflinePackComplete(),
        ],
      );

      final events = await adapter
          .createPack(
            regionGeojson: '{}',
            styleUri: 'mapbox://styles/x',
            minZoom: 12,
            maxZoom: 17,
          )
          .toList();

      expect(events, hasLength(4));
      expect(events[0], isA<OfflinePackProgress>());
      expect(events.last, isA<OfflinePackComplete>());
    });

    test('emits an error event on failure', () async {
      final adapter = FakeOfflinePackAdapter(
        scriptedEvents: const [
          OfflinePackProgress(downloaded: 100, total: 1000),
          OfflinePackError('boom'),
        ],
      );

      final events = await adapter
          .createPack(
            regionGeojson: '{}',
            styleUri: 'mapbox://styles/x',
            minZoom: 12,
            maxZoom: 17,
          )
          .toList();

      expect(events.last, isA<OfflinePackError>());
      expect((events.last as OfflinePackError).message, 'boom');
    });

    test('cancelAllPacks increments cancelCount', () async {
      final adapter = FakeOfflinePackAdapter();
      await adapter.cancelAllPacks();
      await adapter.cancelAllPacks();
      expect(adapter.cancelCount, 2);
    });

    test('estimateBytes returns configured value', () async {
      final adapter = FakeOfflinePackAdapter(estimateBytes: 123456789);
      final bytes = await adapter.estimateBytes(
        regionGeojson: '{}',
        styleUri: 'mapbox://styles/x',
        minZoom: 12,
        maxZoom: 17,
      );
      expect(bytes, 123456789);
    });
  });
}
