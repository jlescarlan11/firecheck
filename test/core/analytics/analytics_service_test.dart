import 'package:firecheck/core/analytics/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoopAnalyticsService', () {
    test('track is a no-op (no throw)', () {
      const service = NoopAnalyticsService();
      expect(() => service.track('any.event'), returnsNormally);
      expect(
        () => service.track('any.event', properties: {'k': 'v'}),
        returnsNormally,
      );
    });
  });

  group('ConsoleAnalyticsService', () {
    late List<String> printed;
    late DebugPrintCallback original;

    setUp(() {
      printed = <String>[];
      original = debugPrint;
      debugPrint = (String? msg, {int? wrapWidth}) => printed.add(msg ?? '');
    });

    tearDown(() => debugPrint = original);

    test('writes event name only when properties is null', () {
      const ConsoleAnalyticsService().track('map.recenter.tapped');
      expect(printed, ['[analytics] map.recenter.tapped']);
    });

    test('writes JSON-encoded properties when present', () {
      const ConsoleAnalyticsService()
          .track('map.recenter.tapped', properties: {'outcome': 'ok'});
      expect(printed, ['[analytics] map.recenter.tapped {"outcome":"ok"}']);
    });

    test('omits properties suffix when properties map is empty', () {
      const ConsoleAnalyticsService().track('e', properties: <String, Object?>{});
      expect(printed, ['[analytics] e']);
    });
  });

  group('RecordingAnalyticsService', () {
    test('records events in order with their properties', () {
      final svc = RecordingAnalyticsService()
        ..track('a', properties: {'k': 1})
        ..track('b')
        ..track('c', properties: {'k': 2});

      expect(svc.events, hasLength(3));
      expect(svc.events[0].event, 'a');
      expect(svc.events[0].properties, {'k': 1});
      expect(svc.events[1].event, 'b');
      expect(svc.events[1].properties, isNull);
      expect(svc.events[2].event, 'c');
      expect(svc.events[2].properties, {'k': 2});
    });
  });
}
