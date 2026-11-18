import 'dart:async';
import 'package:firecheck/features/map/presentation/boundary_outline.dart';
import 'package:flutter_test/flutter_test.dart';

const polygon = '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}';
void main() {
  test('replaces valid outline then clears invalid/empty assignment', () async {
    final events = <String>[];
    final outline = BoundaryOutline(
      clear: () async {
        events.add('clear');
      },
      draw: (ring) async {
        events.add('draw:${ring.length}');
      },
    );
    await outline.replace(polygon);
    await outline.replace('bad');
    await outline.replace('');
    expect(events, ['clear', 'draw:4', 'clear', 'clear']);
  });
  test('selection change during clear never draws the previous assignment',
      () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var clears = 0;
    var draws = 0;
    final outline = BoundaryOutline(
      clear: () async {
        if (clears++ == 0) {
          started.complete();
          await gate.future;
        }
      },
      draw: (_) async {
        draws++;
      },
    );
    final old = outline.replace(polygon);
    await started.future;
    final next = outline.replace('');
    gate.complete();
    await old;
    await next;
    expect(draws, 0);
  });
  test('style disposal prevents old in-flight clear from drawing stale rings',
      () async {
    final cleared = Completer<void>();
    final started = Completer<void>();
    var draws = 0;
    final old = BoundaryOutline(
      clear: () {
        started.complete();
        return cleared.future;
      },
      draw: (_) async {
        draws++;
      },
    );
    final replacing = old.replace(polygon);
    await started.future;
    old.dispose();
    cleared.complete();
    await replacing;
    expect(draws, 0);
    final fresh = BoundaryOutline(
      clear: () async {},
      draw: (_) async {
        draws++;
      },
    );
    await fresh.replace(polygon);
    expect(draws, 1);
  });
  test('queue failure does not prevent later boundary retry', () async {
    var attempts = 0;
    var draws = 0;
    final outline = BoundaryOutline(
      clear: () async {
        if (attempts++ == 0) throw StateError('style');
      },
      draw: (_) async {
        draws++;
      },
    );
    await expectLater(outline.replace(polygon), throwsStateError);
    await outline.replace(polygon);
    expect(draws, 1);
  });
}
