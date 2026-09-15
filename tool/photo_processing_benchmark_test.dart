// Run with flutter test tool/photo_processing_benchmark_test.dart --reporter expanded.
// Results measure host event-loop responsiveness, not Android frame timings.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firecheck/core/photos/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('measure event-loop delay while processing a camera-sized photo',
      () async {
    final temp = await Directory.systemTemp.createTemp('photo_benchmark_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}/source.jpg');
    final photo = img.Image(width: 3000, height: 2000);
    img.fill(photo, color: img.ColorRgb8(120, 80, 40));
    await source.writeAsBytes(img.encodeJpg(photo));

    final watch = Stopwatch()..start();
    var lastTick = 0;
    var maxGap = 0;
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = watch.elapsedMicroseconds;
      final gap = now - lastTick;
      if (gap > maxGap) maxGap = gap;
      lastTick = now;
      ticks++;
    });
    try {
      await const ImageProcessor().resizeAndCopyExif(
        sourcePath: source.path,
        destPath: '${temp.path}/result.jpg',
      );
      // Include any final blocked interval before cancelling the timer.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } finally {
      timer.cancel();
      watch.stop();
    }
    final result = {
      'elapsed_ms': watch.elapsedMicroseconds / 1000,
      'max_event_loop_gap_ms': maxGap / 1000,
      'timer_ticks': ticks,
      'output_bytes': await File('${temp.path}/result.jpg').length(),
    };
    // Machine-readable output for before/after comparisons; no timing threshold
    // because shared-host load varies. Device profiling is still required.
    stdout.writeln('PHOTO_BENCHMARK ${jsonEncode(result)}');
    expect(result['output_bytes'], greaterThan(0));
  });
}
