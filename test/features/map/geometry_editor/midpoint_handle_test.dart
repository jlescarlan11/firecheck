import 'package:firecheck/features/map/geometry_editor/presentation/midpoint_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MidpointHandle has 44x44 hit area', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: MidpointHandle()),
      ),
    ));
    final size = tester.getSize(find.byType(MidpointHandle));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
