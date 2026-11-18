import 'dart:async';

import 'package:firecheck/features/map/presentation/annotation_style_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'serializes manager recreation and recovers after initialization failure',
      () async {
    final firstStarted = Completer<void>();
    final firstReady = Completer<void>();
    final events = <String>[];
    var attempts = 0;
    final lifecycle = AnnotationStyleLifecycle<String>(
      isCurrent: (_) => true,
      initialize: (map) async {
        events.add('start:$map');
        if (++attempts == 1) {
          firstStarted.complete();
          await firstReady.future;
          throw StateError('style no longer available');
        }
        events.add('ready:$map');
      },
      replayWorkingGeometry: () async {},
    );
    final first = lifecycle.reload('first');
    final firstFailure = expectLater(first, throwsStateError);
    await firstStarted.future;
    final second = lifecycle.reload('second');
    expect(events, ['start:first']);
    firstReady.complete();
    await firstFailure;
    await second;
    expect(events, ['start:first', 'start:second', 'ready:second']);
  });

  test(
      'replays latest working geometry after every deferred style initialization',
      () async {
    final started = Completer<void>();
    final ready = Completer<void>();
    var workingGeometry = 'before reload';
    String? renderedGeometry = 'before reload';
    var initializations = 0;
    final replayed = <String>[];
    final lifecycle = AnnotationStyleLifecycle<String>(
      isCurrent: (_) => true,
      initialize: (_) async {
        renderedGeometry = null; // Native manager removal discards its overlay.
        if (++initializations == 1) {
          started.complete();
          await ready.future;
        }
      },
      replayWorkingGeometry: () async {
        renderedGeometry = workingGeometry;
        replayed.add(workingGeometry);
      },
    );
    final reloading = lifecycle.reload('map');
    await started.future;
    workingGeometry = 'edited while style was loading';
    ready.complete();
    await reloading;
    expect(renderedGeometry, 'edited while style was loading');
    workingGeometry = 'second edit';
    await lifecycle.reload('map');
    expect(renderedGeometry, 'second edit');
    expect(replayed, ['edited while style was loading', 'second edit']);
  });

  test(
      'does not replay working geometry into a replaced map after awaiting init',
      () async {
    final started = Completer<void>();
    final ready = Completer<void>();
    var current = 'old';
    var replays = 0;
    final lifecycle = AnnotationStyleLifecycle<String>(
      isCurrent: (map) => map == current,
      initialize: (_) async {
        started.complete();
        await ready.future;
      },
      replayWorkingGeometry: () async {
        replays++;
      },
    );
    final reloading = lifecycle.reload('old');
    await started.future;
    current = 'new';
    ready.complete();
    await reloading;
    expect(replays, 0);
  });

  test('ignores queued initialization after the map is disposed or replaced',
      () async {
    var current = 'old';
    final initialized = <String>[];
    final lifecycle = AnnotationStyleLifecycle<String>(
      isCurrent: (map) => map == current,
      initialize: (map) async {
        initialized.add(map);
      },
      replayWorkingGeometry: () async {},
    );
    final pending = lifecycle.reload('old');
    current = 'new';
    await pending;
    expect(initialized, isEmpty);
    await lifecycle.reload('new');
    expect(initialized, ['new']);
  });
}
